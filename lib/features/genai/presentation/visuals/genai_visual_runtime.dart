/// Local animation scheduling for generated examples. Folding retains JS state,
/// but suspends timers and animation frames instead of running invisible work.
const genAiVisualScheduler = r'''
(()=>{
const later=window.setTimeout.bind(window), cancel=window.clearTimeout.bind(window);
const frame=window.requestAnimationFrame.bind(window), cancelFrame=window.cancelAnimationFrame.bind(window);
const jobs=new Map();let serial=0,active=null;
function arm(id,job){
  if(!active)return;
  const fire=(time)=>{
    job.handle=null;
    if(!jobs.has(id))return;
    if(job.kind!=='interval')jobs.delete(id);
    try{
      if(typeof job.callback==='function')job.callback.apply(window,job.kind==='frame'?[time]:job.args);
      else later(job.callback,0); // Native CSP still disallows string evaluation.
    }finally{
      if(job.kind==='interval' && jobs.has(id)){job.remaining=job.delay;arm(id,job);}
    }
  };
  job.due=performance.now()+job.remaining;
  job.handle=job.kind==='frame'?frame(fire):later(fire,job.remaining);
}
function add(kind,callback,delay,args){
  const id=++serial;
  const ms=Math.min(2147483647,Math.max(0,Number(delay)||0));
  const job={kind,callback,args,delay:ms,remaining:ms,handle:null,due:0};
  jobs.set(id,job);arm(id,job);return id;
}
function stop(id){
  const job=jobs.get(id);if(!job)return;
  if(job.handle!==null)(job.kind==='frame'?cancelFrame:cancel)(job.handle);
  jobs.delete(id);
}
window.setTimeout=(callback,delay,...args)=>add('timeout',callback,delay,args);
window.setInterval=(callback,delay,...args)=>add('interval',callback,delay,args);
window.clearTimeout=window.clearInterval=stop;
window.requestAnimationFrame=(callback)=>add('frame',callback,0,[]);
window.cancelAnimationFrame=stop;
function setActive(value){
  const next=value===true;if(active===next)return;active=next;
  document.documentElement.dataset.techpieActive=String(active);
  for(const [id,job] of jobs){
    if(active)arm(id,job);
    else if(job.handle!==null){
      (job.kind==='frame'?cancelFrame:cancel)(job.handle);
      job.handle=null;job.remaining=Math.max(0,job.due-performance.now());
    }
  }
  window.dispatchEvent(new CustomEvent('techpie-visibility',{detail:{active}}));
}
setActive(/*techpie-active*/true);
window.addEventListener('message',event=>{
  if(event.source===parent && event.data?.kind==='techpie-visual-active')setActive(event.data.active);
});
})();
''';

/// Native MathML output uses the platform's math fonts, not bundled web fonts.
/// A bad formula or unavailable optional library leaves readable TeX in place.
const genAiVisualMath = r'''
(()=>{
const rendered=new WeakMap();
const htmlNamespace='http://www.w3.org/1999/xhtml';
const ignored='script,style,noscript,pre,code,textarea,option,math,.katex,[data-math-ignore],[contenteditable]:not([contenteditable="false"])';
const delimiters=[
  {left:'$$',right:'$$',display:true},
  {left:'\\(',right:'\\)',display:false},
  {left:'\\[',right:'\\]',display:true}
];
const mathOptions={output:'mathml',throwOnError:true,trust:false,maxExpand:1000,maxSize:20};
const hasDelimiter=text=>text.includes('$$')||text.includes('\\(')||text.includes('\\[');
const eligible=element=>element?.namespaceURI===htmlNamespace&&!element.closest(ignored);
const subtrees=new Set(),textParents=new Set(),attributes=new Set();
let observer=null,queued=false,mutating=false;
function schedule(){
  if(queued)return;queued=true;
  requestAnimationFrame(flush);
}
function collect(records){
  for(const record of records){
    const target=record.target.nodeType===1?record.target:record.target.parentElement;
    if(!target)continue;
    const owner=target.closest('[data-latex]');
    if(owner&&eligible(owner)){attributes.add(owner);continue;}
    if(target.closest(ignored))continue;
    if(record.type==='attributes'){attributes.add(target);continue;}
    if(record.type==='characterData'){textParents.add(target);continue;}
    for(const node of record.addedNodes){
      if(node.nodeType===1)subtrees.add(node);
      else if(node.nodeType===3)textParents.add(target);
    }
  }
  if(subtrees.size||textParents.size||attributes.size)schedule();
}
function observe(){
  observer.observe(document.body,{
    subtree:true,childList:true,characterData:true,
    attributes:true,attributeFilter:['data-latex','data-display']
  });
}
function mutate(action){
  if(mutating)return action();
  // Preserve pending external changes before suppressing our own DOM writes.
  if(observer){collect(observer.takeRecords());observer.disconnect();}
  mutating=true;
  try{return action();}
  finally{mutating=false;if(observer)observe();}
}
function render(element,tex,options={}){
  if(!eligible(element))return;
  tex=String(tex);const displayMode=options.displayMode===true;
  const previous=rendered.get(element);
  if(previous&&previous.tex===tex&&previous.displayMode===displayMode&&
     previous.renderer===window.katex&&previous.markup===element.innerHTML){
    previous.attributeTex=element.getAttribute('data-latex');
    previous.attributeDisplay=element.getAttribute('data-display');
    return;
  }
  mutate(()=>{
    try{
      if(!window.katex)throw new Error('Math renderer unavailable');
      element.innerHTML=window.katex.renderToString(tex,{...mathOptions,displayMode});
      element.removeAttribute('data-math-error');
    }catch(_){element.textContent=tex;element.setAttribute('data-math-error','true');}
    rendered.set(element,{
      tex,displayMode,renderer:window.katex,markup:element.innerHTML,
      attributeTex:element.getAttribute('data-latex'),
      attributeDisplay:element.getAttribute('data-display')
    });
  });
}
function renderAttribute(element){
  if(!eligible(element)||!element.hasAttribute('data-latex'))return;
  const tex=element.getAttribute('data-latex'),display=element.getAttribute('data-display');
  const previous=rendered.get(element);
  // A setup/update helper may intentionally override an unchanged static attribute.
  const keepTex=previous&&previous.attributeTex===tex;
  const keepDisplay=previous&&previous.attributeDisplay===display;
  render(element,keepTex?previous.tex:tex,{
    displayMode:keepDisplay?previous.displayMode:display==='block'
  });
}
function renderText(parent){
  if(!eligible(parent)||parent.closest('[data-latex]')||!window.katex||
     typeof window.renderMathInElement!=='function')return;
  for(let node=parent.firstChild;node;){
    if(node.nodeType!==3){node=node.nextSibling;continue;}
    const nodes=[];let text='';
    while(node&&node.nodeType===3){nodes.push(node);text+=node.textContent;node=node.nextSibling;}
    if(!hasDelimiter(text))continue;
    // Render only this adjacent text group, retaining controls and their listeners.
    const span=document.createElement('span');span.textContent=text;
    try{
      window.renderMathInElement(span,{
        ...mathOptions,delimiters,errorCallback:()=>{}
      });
      if(!span.querySelector('math'))continue;
      const fragment=document.createDocumentFragment();
      while(span.firstChild)fragment.appendChild(span.firstChild);
      parent.insertBefore(fragment,nodes[0]);
      for(const original of nodes)original.remove();
    }catch(_){/* Keep original delimited text if optional rendering is unavailable. */}
  }
}
function scan(root){
  if(root.nodeType!==1||root.closest(ignored))return;
  if(eligible(root)&&root.hasAttribute('data-latex')){renderAttribute(root);return;}
  renderText(root);
  // Native SVG labels stay intact; XHTML inside foreignObject can render normally.
  for(const child of Array.from(root.children))scan(child);
}
function covered(element,roots){
  for(let node=element;node;node=node.parentElement)if(roots.has(node))return true;
  return false;
}
function flush(){
  queued=false;
  mutate(()=>{
    const roots=Array.from(subtrees),parents=Array.from(textParents),hosts=Array.from(attributes);
    const rootSet=new Set(roots);
    subtrees.clear();textParents.clear();attributes.clear();
    for(const host of hosts)if(host.isConnected)renderAttribute(host);
    for(const root of roots){
      if(root.isConnected&&!covered(root.parentElement,rootSet))scan(root);
    }
    for(const parent of parents){
      if(parent.isConnected&&!covered(parent,rootSet))renderText(parent);
    }
  });
}
window.techpieMath=Object.freeze({render});
window.addEventListener('DOMContentLoaded',()=>{
  mutate(()=>scan(document.body));
  observer=new MutationObserver(collect);observe();
});
})();
''';
