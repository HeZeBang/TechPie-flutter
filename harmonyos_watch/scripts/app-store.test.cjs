const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/app.js', 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default', 'var application =');

test('cached content and transport remain usable while the optional vault is unavailable', () => {
  let changed, storeOptions, restored = false, started = 0;
  const context = {
    console: {info() {}}, setInterval: () => 1, clearInterval() {},
    readJson(name, done) { done(null, {owner: 'owner'}); }, writeJson(name, data, done) { done(); },
    require() { throw new Error('Optional crypto module unavailable'); },
    WearLink: function(publish, options) {
      changed = publish; storeOptions = options;
      this.connection = {cacheBinding: 'owner', restore() { restored = true; return true; },
        publish() { changed({name: 'cached-user', connected: false}); }, tick() {}, reset() {},
        phoneNow: () => 1000};
      this.start = () => { started++; }; this.stop = () => {};
    },
  };
  vm.createContext(context); vm.runInContext(source, context);
  const app = context.application;
  assert.ok(app.data); // Lite getApp() requires the exported data object.
  app.onCreate(); const api = app.data.api; api.watchResume();
  assert.equal(restored, true); assert.equal(started, 1);
  assert.equal(storeOptions.offlineEnabled(), false);
  let state; api.watchObserve(value => { state = value; });
  changed({name: 'cached-user', connected: false});
  assert.equal(state.name, 'cached-user'); api.watchPause();
});

test('cold starts read existing UTF-8 snapshots and encrypted grants larger than 4 KiB', () => {
  const json = JSON.stringify({course: '课程 % 😀'.repeat(900)});
  const bytes = Buffer.from(json);
  assert.ok(bytes.length > 4096);
  const file = {readArrayBuffer({success}) { success({buffer: new Uint8Array(bytes)}); }};
  const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/common/watch-files.js', 'utf8');
  const context = {require: () => ({default: file})};
  vm.createContext(context);
  vm.runInContext(source.replace(/export function /g, 'function '), context);
  let result;
  context.readJson('watch-cache-v1.json', (error, value) => {
    assert.equal(error, null);
    result = value;
  });
  assert.equal(JSON.stringify(result), json);
});
