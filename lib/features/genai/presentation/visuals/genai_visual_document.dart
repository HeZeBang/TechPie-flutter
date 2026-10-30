import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'genai_visual_runtime.dart';

/// Only these exact, versioned resources can be fetched by the host. Generated
/// frames themselves have no network access, including to library CDNs.
const genAiVisualLibraries = {
  'https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js',
  'https://cdn.jsdelivr.net/npm/chart.js@4.4.8/dist/chart.umd.js',
  'https://cdn.jsdelivr.net/npm/three@0.160.1/build/three.min.js',
};

const genAiVisualCsp = "default-src 'none'; script-src 'unsafe-inline'; "
    "style-src 'unsafe-inline'; img-src data: blob:; font-src data:; "
    "connect-src 'none'; frame-src 'none'; object-src 'none'; "
    "base-uri 'none'; form-action 'none'; worker-src 'none'";

class GenAiVisualException implements Exception {
  const GenAiVisualException(this.message);
  final String message;
}

/// Builds an inert outer shell around an opaque-origin, scripts-only frame.
/// The only bridge carries ready/error/height notifications, never app commands.
class GenAiVisualDocument {
  static const mathLibrary = 'https://cdn.jsdelivr.net/npm/katex@0.19.1/dist/katex.min.js';
  static const mathAutoRenderLibrary =
      'https://cdn.jsdelivr.net/npm/katex@0.19.1/dist/contrib/auto-render.min.js';
  static const maxSourceBytes = 256 * 1024;
  static final Map<String, Future<String>> _libraries = {};

  static Future<String> prepare(
    String source, {
    Future<String> Function(Uri)? loadLibrary,
  }) async {
    if (utf8.encode(source).length > maxSourceBytes) {
      throw const GenAiVisualException('内容过大，请查看源码');
    }
    final document = html.parse(source);
    // Discard document-level controls; policy is always host-owned and first.
    for (final element in document.querySelectorAll('meta, base, link')) {
      element.remove();
    }
    for (final script in document.querySelectorAll('script[src]')) {
      final url = script.attributes['src']!;
      if (!genAiVisualLibraries.contains(url)) {
        throw const GenAiVisualException('此示例引用了不支持的外部脚本');
      }
      final code = await (loadLibrary?.call(Uri.parse(url)) ?? _library(url));
      script.attributes.remove('src');
      script.attributes.remove('integrity');
      script.attributes.remove('crossorigin');
      script.attributes.remove('async');
      script.attributes.remove('defer');
      script.text = code.replaceAll(RegExp('</script', caseSensitive: false), r'<\/script');
    }
    final needsAutoRender =
        source.contains(r'\(') || source.contains(r'\[') || source.contains(r'$$');
    // Include script-created labels and aliased helper calls as well as initial DOM.
    final needsMath = needsAutoRender ||
        source.contains('data-latex') ||
        source.contains('techpieMath') ||
        RegExp(r'''dataset\s*(?:\.\s*latex\b|\[\s*['"]latex['"]\s*\])''').hasMatch(source);
    Future<String?> optionalMathLibrary(String url) async {
      try {
        return await (loadLibrary?.call(Uri.parse(url)) ?? _library(url));
      } catch (_) {
        // Math is optional: preserve readable formulas and the rest of the demo.
        return null;
      }
    }

    final mathScripts = needsMath
        ? await Future.wait([
            optionalMathLibrary(mathLibrary),
            if (needsAutoRender) optionalMathLibrary(mathAutoRenderLibrary),
          ])
        : const <String?>[];
    final head = document.head!;
    head.nodes.insertAll(0, [
      dom.Element.tag('meta')
        ..attributes['http-equiv'] = 'Content-Security-Policy'
        ..attributes['content'] = genAiVisualCsp,
      dom.Element.tag('meta')..attributes['charset'] = 'utf-8',
      dom.Element.tag('meta')
        ..attributes['name'] = 'viewport'
        ..attributes['content'] = 'width=device-width, initial-scale=1',
      dom.Element.tag('style')..text = _baseStyle,
      dom.Element.tag('script')..text = genAiVisualScheduler,
      dom.Element.tag('script')..text = _reporter,
      for (final mathCode in mathScripts)
        if (mathCode != null)
          dom.Element.tag('script')
            ..text = mathCode.replaceAll(RegExp('</script', caseSensitive: false), r'<\/script'),
      if (needsMath) dom.Element.tag('script')..text = genAiVisualMath,
    ]);
    return '<!doctype html>${document.documentElement!.outerHtml}';
  }

  static Future<String> _library(String url) async {
    final existing = _libraries[url];
    if (existing != null) return existing;
    final pending = _libraries.putIfAbsent(url, () => _download(Uri.parse(url)));
    try {
      return await pending;
    } catch (_) {
      unawaited(_libraries.remove(url));
      rethrow;
    }
  }

  static Future<String> _download(Uri uri) async {
    final client = http.Client();
    try {
      return await (() async {
        final response = await client.send(http.Request('GET', uri)..followRedirects = false);
        if (response.statusCode != 200) throw const FormatException();
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) throw const FormatException();
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })()
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const GenAiVisualException('可视化库加载失败，请重试');
    } finally {
      client.close();
    }
  }

  static String shell(
    String document, {
    required bool native,
    bool active = true,
    Map<String, String> theme = const {},
  }) {
    final encodedTheme = jsonEncode(theme).replaceAll('<', r'\u003c');
    final encoded = jsonEncode(
      document
          .replaceFirst('{/*techpie-theme*/}', encodedTheme)
          .replaceFirst('/*techpie-active*/true', '$active'),
    ).replaceAll('<', r'\u003c');
    final csp = const HtmlEscape(HtmlEscapeMode.attribute).convert(genAiVisualCsp);
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="$csp">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block;background:transparent}</style>
</head><body><iframe id="visual" title="交互示例" sandbox="allow-scripts" referrerpolicy="no-referrer" allow="camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'"></iframe><script>
const frame=document.getElementById('visual');
let theme=$encodedTheme,active=$active;
const sendActive=()=>frame.contentWindow.postMessage({kind:'techpie-visual-active',active},'*');
const sendTheme=()=>frame.contentWindow.postMessage({kind:'techpie-visual-theme',theme},'*');
window.addEventListener('message',event=>{
  if(event.source===parent && event.data?.kind==='techpie-visual-active'){
    active=event.data.active===true;sendActive();return;
  }
  if(event.source===parent && event.data?.kind==='techpie-visual-theme'){
    theme=event.data.theme;sendTheme();return;
  }
  if(event.source!==frame.contentWindow || !event.data || event.data.kind!=='techpie-visual')return;
  const d=event.data;
  if(d.event==='ready'){sendTheme();sendActive();}
  if(!['ready','error','height','escape'].includes(d.event))return;
  const safe={kind:'techpie-visual',event:d.event};
  if(d.event==='height')safe.height=Math.max(180,Math.min(560,Number(d.height)||360));
  ${native ? "TechPieVisual.postMessage(JSON.stringify(safe));" : "parent.postMessage(safe,'*');"}
});
frame.srcdoc=$encoded;
</script></body></html>''';
  }

  static const _baseStyle = '''
:root{color-scheme:light;--tp-bg:#fff;--tp-surface:#f5f5f5;--tp-text:#202124;--tp-muted:#666;--tp-primary:#67504b;--tp-on-primary:#fff;--tp-border:#ddd;font-family:system-ui,sans-serif;color:var(--tp-text);background:var(--tp-bg)}
*{box-sizing:border-box}body{margin:0;padding:16px;overflow-wrap:anywhere}
html[data-techpie-active=false] *,html[data-techpie-active=false] *::before,html[data-techpie-active=false] *::after{animation-play-state:paused!important}
math{color:inherit;font-size:1.05em}math[display=block]{overflow-x:auto;max-width:100%;padding:6px 0}
canvas,svg,img{max-width:100%}button,input,select{font:inherit}
button,input[type=range],select{min-height:40px}button{cursor:pointer}
html,body{background:var(--tp-bg)!important;color:var(--tp-text)!important}
h1,h2,h3,h4,h5,h6,label,p,pre{color:var(--tp-text)!important}
button,input,select,textarea{color:var(--tp-text)!important;background:var(--tp-surface)!important;border:1px solid var(--tp-border)!important;border-radius:8px;accent-color:var(--tp-primary)}
button{padding:6px 12px}button:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid var(--tp-primary);outline-offset:2px}
/* Older saved examples often hard-code light surfaces in these containers. */
.card,.panel,.controls,.controls>div,.toolbar,.wrap,.box,.head,fieldset{background:var(--tp-bg)!important;color:var(--tp-text)!important;border-color:var(--tp-border)!important;box-shadow:none!important}

@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;transition-duration:.01ms!important}}
''';
  static const _reporter = r'''
(()=>{
function applyTheme(theme){
  if(!theme || typeof theme!=='object')return;
  const safe={};
  for(const name of ['bg','surface','text','muted','primary','on-primary','border']){
    const value=theme[name];
    if(typeof value==='string' && /^#[0-9a-f]{6,8}$/i.test(value)){
      safe[name]=value;document.documentElement.style.setProperty('--tp-'+name,value);
    }
  }
  safe.mode=theme.mode==='dark'?'dark':'light';
  document.documentElement.style.colorScheme=safe.mode;
  document.documentElement.dataset.theme=safe.mode;
  window.techpieTheme=Object.freeze(safe);
  window.dispatchEvent(new CustomEvent('techpie-theme',{detail:window.techpieTheme}));
}
applyTheme({/*techpie-theme*/});
window.addEventListener('message',event=>{
  if(event.source===parent && event.data?.kind==='techpie-visual-theme')applyTheme(event.data.theme);
});
const emit=(event,extra={})=>parent.postMessage({kind:'techpie-visual',event,...extra},'*');
window.addEventListener('keydown',event=>{if(event.key==='Escape')emit('escape');});
window.addEventListener('error',()=>emit('error'));
window.addEventListener('unhandledrejection',()=>emit('error'));
window.addEventListener('securitypolicyviolation',()=>emit('error'));
window.addEventListener('DOMContentLoaded',()=>{
  emit('ready');
  let queued=false;
  const resize=()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;emit('height',{height:document.body.scrollHeight});});};
  new ResizeObserver(resize).observe(document.body);resize();
});
})();
''';
}
