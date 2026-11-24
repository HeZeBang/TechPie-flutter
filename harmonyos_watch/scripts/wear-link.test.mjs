import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../entry/src/main/js/MainAbility/common/wear-link.js', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export function WearLink', 'function WearLink');

function fixture(register) {
  const timers = new Map(), states = [], errors = [];
  let id = 0;
  const context = {
    config: {phonePackage: 'example.phone', phoneFingerprint: 'public-certificate'},
    console: {info() {}, error(message) { errors.push(message); }},
    setInterval(fn) { const key = ++id; timers.set(key, fn); return key; },
    Builder: function() { this.setDescription = function() {}; },
    Message: function() {},
    setTimeout(fn) { const key = ++id; timers.set(key, fn); return key; },
    clearInterval(key) { timers.delete(key); }, clearTimeout(key) { timers.delete(key); },
    P2pClient: function() {
      this.version = '402';
      this.setPeerPkgName = function() {};
      this.setPeerFingerPrint = function() {};
      this.registerReceiver = register;
      this.send = function(message, callback) { callback.onSendResult({code: 206}); };
      this.unregisterReceiver = function() {};
    },
    WatchConnection: function(send, changed) {
      this.reset = function() {}; this.tick = function() {};
      this.publish = function() { changed({error: this.error}); };
      this.notifyReady = function() { this.notified = true; };
    },
  };
  context.require = () => context;
  vm.createContext(context); vm.runInContext(source, context);
  const link = new context.WearLink(state => states.push(state));
  link.start(); const initialize = [...timers.values()][0];
  return {link, initialize, timers, states, errors};
}

test('native receiver exception becomes a visible service failure and stops polling', () => {
  const f = fixture(() => { throw new TypeError("Cannot read property 'registerReceiver' of undefined"); });
  assert.doesNotThrow(f.initialize);
  assert.equal(f.link.client, null);
  assert.equal(f.timers.size, 0);
  assert.match(f.states.at(-1).error, /接收服务启动失败/);
  assert.match(f.errors[0], /receiver registration: TypeError/);
});

test('receiver failure callback does not restart a timer for the cancelled connection', () => {
  const f = fixture(receiver => receiver.onFailure());
  f.initialize();
  assert.equal(f.link.client, null);
  assert.equal(f.timers.size, 0);
});

test('successful receiver setup starts the session clock', () => {
  const f = fixture(receiver => receiver.onSuccess());
  f.initialize();
  assert.ok(f.link.client);
  assert.equal(f.timers.size, 1);
  assert.equal(f.link.connection.notified, true);
  assert.equal(f.states.length, 0);
});

test('an undelivered ready announcement keeps the receiver available for a later handshake', () => {
  const f = fixture(receiver => receiver.onSuccess());
  f.initialize();
  f.link.enqueue('ready', true);
  assert.equal(f.link.receiving, true);
  assert.equal(f.link.sending, false);
  assert.equal(f.timers.size, 1);
  f.link.enqueue('required receipt');
  assert.equal(f.link.receiving, false);
});
