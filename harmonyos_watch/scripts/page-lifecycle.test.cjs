const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/pages/index/index.js', 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default', 'var page =');

function fixture() {
  let id = 0, now = 1800000000000, observe;
  const timers = new Map(), counts = {signed: 0, focused: 0, drawn: 0, paused: 0, resumed: 0};
  const state = {connected: false, schedule: [], ddl: []}, grant = {};
  const api = {
    watchNow: () => now, watchCredential: () => grant, watchState: () => state,
    watchObserve(fn) { observe = fn; fn(state); },
    watchResume() { counts.resumed++; }, watchPause() { counts.paused++; },
    watchMatrix() { return () => ({size: 1, bytes: [128]}); }
  };
  class Clock extends Date { static now() { return now; } }
  const env = {
    Date: Clock, getApp: () => ({data: {api}}), console: {info() {}, error() {}},
    setTimeout(fn) { timers.set(++id, fn); return id; }, clearTimeout(i) { timers.delete(i); },
    startOfflineCode() { return {step() { counts.signed++; return {payload: [1], until: now + 30000}; }}; }
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
test('hide cancels queued signing and focus; late callbacks cannot reach a reopened view', () => {
  const f = fixture(), previous = [...f.timers.values()], observe = f.observe();
  assert.equal(f.counts.resumed, 1);
  f.page.onHide(); f.page.onPageChange({index: 0}); f.page.onDestroy();
  assert.equal(f.counts.paused, 1); assert.equal(f.timers.size, 0);
  f.page.onShow();
  for (const fn of previous) fn();
  observe(f.state);
  assert.equal(f.counts.focused, 0); assert.equal(f.counts.signed, 0);
  f.run(); assert.equal(f.counts.signed, 1); assert.equal(f.counts.focused, 1);
});
test('a canvas callback queued before hide cannot paint a newly shown page', () => {
  const f = fixture(); f.run(); f.run();
  const pending = [...f.timers.values()];
  assert.ok(f.page.codeVisible); assert.ok(pending.length);
  f.page.onHide(); f.page.onShow(); pending.forEach(fn => fn());
  assert.equal(f.counts.drawn, 0);
});
test('expired codes wait for a tap; suspended jobs discard an overdue timer without signing', () => {
  const f = fixture(); f.advance(3000); f.run();
  assert.equal(f.counts.signed, 0);
  f.page.refreshCode(); f.run(); f.run(); f.run();
  assert.equal(f.counts.drawn, 1); assert.equal(f.counts.signed, 1);
  f.advance(31000); f.observe()(f.state); f.run();
  assert.equal(f.page.codeVisible, false); assert.equal(f.counts.signed, 1);
  f.page.refreshCode(); f.run(); assert.equal(f.counts.signed, 2);
});
