const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/pages/index/index.js', 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default', 'var page =');

function fixture(withGrant = true) {
  let id = 0, now = 1800000000000, observe;
  const timers = new Map(), counts = {signed: 0, focused: 0, drawn: 0, requests: 0, paused: 0, resumed: 0};
  const state = {connected: false, schedule: [], ddl: []}, grant = {};
  const api = {
    watchNow: () => now, watchCredential: () => withGrant ? grant : null, watchState: () => state,
    watchObserve(fn) { observe = fn; fn(state); },
    watchCode() { counts.requests++; }, watchHideCode() {},
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
  return {page, api, state, counts, timers, run, observe: () => observe, advance(ms) { now += ms; }};
}
test('hide cancels queued signing and focus; late callbacks cannot reach a reopened view', () => {
  const f = fixture();
  const previous = [...f.timers.values()], observe = f.observe();
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

test('a connected watch without a grant requests online and expires the displayed code', () => {
  const f = fixture(false);
  f.state.connected = true;
  f.observe()(f.state); f.observe()(f.state);
  assert.equal(f.counts.requests, 1);
  f.state.code = {id: 'online', until: 1800000030000, bytes: [128], size: 1};
  f.observe()(f.state); f.run();
  assert.equal(f.counts.drawn, 1);
  f.state.code = null;
  f.advance(30000); f.observe()(f.state);
  assert.equal(f.page.codeVisible, false);
  f.page.refreshCode(); assert.equal(f.counts.requests, 2);
  assert.equal(f.counts.signed, 0);
});

test('losing the canvas ref while rendering never loops or leaves an expired picture visible', () => {
  const f = fixture(false);
  f.page.$refs.qr = undefined;
  f.state.code = {id: 'online', until: 1800000030000, bytes: [128], size: 1};
  f.observe()(f.state); f.run();
  assert.equal(f.page.codeVisible, false);
  f.observe()(f.state); f.run();
  assert.equal(f.counts.drawn, 0);
  const current = {getContext() { f.counts.drawn++; return {fillRect() {}}; }};
  f.page.$element = id => id === 'campusQr' ? current : null;
  f.state.code.id = 'replaced'; f.observe()(f.state); f.run();
  assert.equal(f.counts.drawn, 1);
  f.advance(31000); f.observe()(f.state);
  assert.equal(f.page.codeVisible, false);
});

test('opening generates once when the encrypted grant finishes loading, and leaving cancels it', () => {
  const f = fixture(false);
  const grant = {};
  f.page.onPageChange({index: 1});
  // Use the API captured by the page to simulate async grant restoration.
  f.api.watchCredential = () => grant;
  f.observe()(f.state); f.run();
  assert.equal(f.counts.signed, 0);
  f.page.onPageChange({index: 0});
  f.observe()(f.state);
  f.page.showAccount(); f.run();
  assert.equal(f.counts.signed, 0);
  f.page.goBack(); f.run(); f.run(); f.run();
  f.observe()(f.state); f.run();
  assert.equal(f.counts.signed, 1); assert.equal(f.counts.drawn, 1);
});

test('a pending online request takes priority and falls back to the restored grant on timeout', () => {
  const f = fixture(false);
  f.state.connected = true; f.observe()(f.state);
  const grant = {};
  f.api.watchCredential = () => grant;
  f.state.codeLoading = true; f.observe()(f.state); f.run();
  assert.equal(f.counts.requests, 1); assert.equal(f.counts.signed, 0);
  f.state.codeLoading = false; f.observe()(f.state); f.run(); f.run(); f.run();
  assert.equal(f.counts.signed, 1); assert.equal(f.counts.drawn, 1);
});
