const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/pages/index/index.js', 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default', 'var page =');

function fixture() {
  let id = 0, now = 1800000000000, observe;
  const timers = new Map(), counts = {requests: 0, focused: 0, drawn: 0, paused: 0, resumed: 0};
  const state = {connected: false, schedule: [], ddl: []};
  const api = {
    watchNow: () => now, watchState: () => state,
    watchObserve(fn) { observe = fn; fn(state); },
    watchResume() { counts.resumed++; }, watchPause() { counts.paused++; },
    watchCode() { if (state.connected) counts.requests++; }, watchHideCode() { state.code = null; }
  };
  class Clock extends Date { static now() { return now; } }
  const env = {
    Date: Clock, getApp: () => ({data: {api}}), console: {info() {}, error() {}},
    setTimeout(fn) { timers.set(++id, fn); return id; }, clearTimeout(i) { timers.delete(i); },
  };
  vm.createContext(env); vm.runInContext(source, env);
  const page = env.page;
  Object.assign(page, page.data, {$refs: {
    deck: {rotation() { counts.focused++; }},
    qr: {getContext() { counts.drawn++; return {fillRect() {}}; }}
  }});
  page.onInit(); page.onReady(); page.onShow();
  function run() {
    for (const [key, fn] of [...timers]) { timers.delete(key); fn(); }
  }
  return {page, state, counts, timers, run, observe: () => observe, advance(ms) { now += ms; }};
}
test('the campus page requests a code after connecting and drops expired frames', () => {
  const f = fixture();
  assert.equal(f.counts.requests, 0);
  f.state.connected = true; f.observe()(f.state); f.observe()(f.state);
  assert.equal(f.counts.requests, 1);
  f.state.code = {id: 'online1', size: 1, bytes: [128], until: 1800000030000};
  f.observe()(f.state); f.run();
  assert.equal(f.page.codeVisible, true); assert.equal(f.counts.drawn, 1);
  f.advance(30000); f.observe()(f.state);
  assert.equal(f.page.codeVisible, false); assert.equal(f.counts.requests, 1);
  f.page.refreshCode(); assert.equal(f.counts.requests, 2);
});
test('a canvas callback queued before hide cannot paint a reopened view', () => {
  const f = fixture();
  f.state.connected = true;
  f.state.code = {id: 'online1', size: 1, bytes: [128], until: 1800000030000};
  f.observe()(f.state);
  const callbacks = [...f.timers.values()];
  f.page.onHide(); f.page.onShow(); callbacks.forEach(fn => fn());
  assert.equal(f.counts.paused, 1); assert.equal(f.counts.drawn, 0);
  f.run(); assert.equal(f.counts.drawn, 1);
});
