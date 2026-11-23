import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../entry/src/main/js/MainAbility/common/wear-connection.js', import.meta.url), 'utf8');
const { WatchConnection } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
function frames(message) {
  const bytes = Buffer.from(JSON.stringify(message));
  return Array.from({length: Math.ceil(bytes.length / 512)}, (_, i) => JSON.stringify({
    v: 1, mid: message.id, i, n: Math.ceil(bytes.length / 512),
    data: bytes.subarray(i * 512, (i + 1) * 512).toString('base64')
  }));
}
function fixture(options) {
  let now = 1000000, state;
  const outgoing = [];
  const link = new WatchConnection(frame => outgoing.push(JSON.parse(frame)), s => {state = s;}, () => now, options);
  function send(type, body = {}, extra = {}) {
    const m = {v: 1, id: 'p' + (++send.count), type, body, sentAtMs: now,
      sessionId: type.startsWith('session.h') || type === 'session.open' ? null : 'session',
      bindingId: type.startsWith('session.h') || type === 'session.open' ? null : 'binding', ...extra};
    frames(m).forEach(f => link.receive(f)); return m;
  }
  send.count = 0;
  const last = () => JSON.parse(Buffer.from(outgoing.at(-1).data, 'base64').toString());
  function open() {
    send('session.hello', {nonce: 'nonce', versions: [1]});
    send('session.open', {nonce: 'nonce', sessionId: 'session', bindingId: 'binding',
      phoneTimeMs: now, leaseUntilMs: now + 86400000});
  }
  return {link, send, last, open, outgoing, state: () => state,
    advance: ms => {now += ms; link.tick();},
    advanceWithoutTick: ms => {now += ms;}};
}
test('two-stage handshake advertises only implemented capabilities', () => {
  const f = fixture();
  f.send('session.hello', {nonce: 'nonce', versions: [1]});
  assert.equal(f.state().connected, false);
  assert.deepEqual(f.last().body.capabilities, ['account.display', 'ddl.display', 'schedule.display', 'reminder.watchLocal', 'campusCode.qrMatrix', 'connection.heartbeat']);
  f.send('session.open', {nonce: 'wrong', sessionId: 'session', bindingId: 'binding', phoneTimeMs: 1000000, leaseUntilMs: 2000000});
  assert.equal(f.state().connected, false);
  f.open(); assert.equal(f.state().connected, true);
  assert.equal(f.last().type, 'session.opened');
});
test('Dart-compatible UTF8 fragmentation accepts Chinese and out-of-order parts', () => {
  const f = fixture(); f.open();
  const m = {v: 1, id: 'chinese', type: 'account.snapshot', sentAtMs: 1000000,
    sessionId: 'session', bindingId: 'binding', body: {
      revision: 1, validUntilMs: 2000000, padding: 'x'.repeat(600),
      data: {name: '测试😀'.repeat(20), studentId: '00123'}
    }};
  assert.ok(frames(m).length > 1);
  frames(m).reverse().forEach(frame => f.link.receive(frame));
  assert.equal(f.state().name, m.body.data.name);
  assert.equal(f.last().body.revision, 1);
});
test('duplicate acknowledgements are idempotent; old sessions cannot change the user', () => {
  const f = fixture(); f.open();
  const m = f.send('account.snapshot', {revision: 1, validUntilMs: 2000000, data: {name: '张三', studentId: '00123'}});
  const ack = f.last(); frames(m).forEach(frame => f.link.receive(frame));
  assert.deepEqual(f.last(), ack);
  f.send('account.snapshot', {revision: 2, validUntilMs: 2000000, data: {name: '李四', studentId: '9'}}, {sessionId: 'old'});
  assert.equal(f.state().name, '张三');
  f.send('account.snapshot', {revision: 1, validUntilMs: 2000000, data: {name: '李四', studentId: '9'}});
  assert.equal(f.last().body.status, 'error'); assert.equal(f.state().name, '张三');
});
test('heartbeat loss and explicit close hide account and reset connection', () => {
  const f = fixture(); f.open();
  f.advance(20000); f.send('session.ping'); f.advance(20000);
  assert.equal(f.state().connected, true);
  f.advance(10000); assert.equal(f.state().connected, false);
  f.open(); f.send('session.close'); assert.equal(f.state().connected, false);
  assert.equal(f.state().name, '');
});
test('malformed/oversized/conflicting fragments and account payloads are rejected', () => {
  const f = fixture(); f.open();
  f.link.receive('x'.repeat(1025)); f.link.receive('{');
  f.send('account.snapshot', {revision: 1, validUntilMs: 2000000, data: {name: '', studentId: '123'}});
  assert.equal(f.last().body.status, 'error'); assert.equal(f.state().name, '');
  const m = f.send('session.ping', {padding: 'x'.repeat(900)});
  const partial = JSON.parse(frames({...m, id: 'conflict'})[0]);
  f.link.receive(JSON.stringify(partial));
  partial.data = Buffer.alloc(512, 65).toString('base64'); f.link.receive(JSON.stringify(partial));
  assert.equal(f.link.assembly, null);
});

test('DDL snapshots replace atomically, sort, and retain cached data past the transport TTL', () => {
  const f = fixture(); f.open();
  const items = [
    {id: 'later', title: '实验报告', courseName: '物理', dueAtMs: 1500000, status: 'open'},
    {id: 'earlier', title: '作业', courseName: '数学', dueAtMs: 1200000, status: 'completed'}
  ];
  f.send('ddl.snapshot', {revision: 2, validUntilMs: 1020000, items});
  assert.deepEqual(f.state().ddl.map(i => i.id), ['earlier', 'later']);
  assert.equal(f.last().body.revision, 2);
  f.send('ddl.snapshot', {revision: 1, validUntilMs: 1020000, items: []});
  assert.equal(f.last().body.code, 'STALE_REVISION');
  f.send('ddl.snapshot', {revision: 3, validUntilMs: 1020000, items: [...items, {...items[0]}]});
  assert.equal(f.last().body.code, 'INVALID_PAYLOAD');
  assert.equal(f.state().ddl.length, 2);
  f.advance(20000);
  assert.equal(f.state().connected, true);
  assert.equal(f.state().ddlReady, true);
  assert.equal(f.state().ddl.length, 2);
});

test('QR only accepts a requested matrix and hides expired or dismissed codes', () => {
  const f = fixture(); f.open();
  const body = {codeId: 'code1', purpose: 'campus', format: 'qrBytes',
    matrixSize: 21, matrixEncoding: 'base64-msb', matrix: Buffer.alloc(56, 255).toString('base64'),
    validFromMs: 1000000, validUntilMs: 1005000};
  f.send('campusCode.snapshot', body, {replyTo: 'unsolicited'});
  assert.equal(f.state().code, null);
  f.link.request('code'); const id = f.last().id;
  assert.equal(f.state().codeLoading, true);
  f.send('campusCode.snapshot', {...body, matrix: 'AA=='}, {replyTo: id});
  assert.equal(f.last().body.code, 'INVALID_PAYLOAD');
  f.send('campusCode.snapshot', body, {replyTo: id});
  assert.equal(f.state().code.bytes.length, 56);
  assert.equal(f.state().codeSeconds, 5);
  f.advance(5000); assert.equal(f.state().code, null);
  f.link.request('code'); const dismissed = f.last().id;
  f.link.hideCode();
  f.send('campusCode.snapshot', {...body, validUntilMs: 1010000}, {replyTo: dismissed});
  assert.equal(f.state().code, null);
});

test('requests surface phone errors and timeouts without corrupting cached account', () => {
  const f = fixture(); f.open();
  f.link.request('code'); const id = f.last().id;
  f.send('result', {status: 'error', code: 'ACCOUNT_NOT_READY'}, {replyTo: id});
  assert.match(f.state().error, /账号绑定/);
  assert.equal(f.state().codeLoading, false);
  f.link.request('sync');
  f.advance(20000); f.send('session.ping'); f.advance(10000);
  assert.equal(f.state().syncing, false);
  assert.match(f.state().error, /未响应/);
  f.send('session.close');
  assert.deepEqual(f.state().ddl, []);
  assert.equal(f.state().code, null);
});


test('accepts newly issued QR between ticks without accepting a future code', () => {
  const f = fixture(); f.open();
  f.link.request('code'); const replyTo = f.last().id;
  f.advanceWithoutTick(100);
  const body = {codeId: 'newCode', purpose: 'campus', format: 'qrBytes',
    matrixSize: 21, matrixEncoding: 'base64-msb', matrix: Buffer.alloc(56).toString('base64'),
    validFromMs: 1000100, validUntilMs: 1030100};
  f.send('campusCode.snapshot', {...body, validFromMs: 1001100}, {replyTo});
  assert.equal(f.state().code, null);
  f.send('campusCode.snapshot', body, {replyTo});
  assert.equal(f.state().code.id, 'newCode');
  assert.equal(f.link.phoneNow(), 1000100);
  f.advance(900);
  assert.equal(f.link.phoneNow(), 1001000);
});

test('refresh failure retains valid QR, but publish hides it at actual expiry', () => {
  const f = fixture(); f.open();
  f.link.request('code'); const first = f.last().id;
  f.send('campusCode.snapshot', {codeId: 'oldCode', purpose: 'campus', format: 'qrBytes',
    matrixSize: 21, matrixEncoding: 'base64-msb', matrix: Buffer.alloc(56).toString('base64'),
    validFromMs: 1000000, validUntilMs: 1005000}, {replyTo: first});
  f.link.request('code'); const retry = f.last().id;
  assert.equal(f.state().code.id, 'oldCode');
  assert.equal(f.state().codeLoading, true);
  f.send('result', {status: 'error', code: 'RATE_LIMITED'}, {replyTo: retry});
  assert.equal(f.state().code.id, 'oldCode');
  assert.equal(f.state().codeLoading, false);
  f.advanceWithoutTick(5000); f.link.publish();
  assert.equal(f.state().code, null);
});

test('successful refresh atomically replaces previous code', () => {
  const f = fixture(); f.open();
  function code(id) {
    f.link.request('code'); const replyTo = f.last().id;
    f.send('campusCode.snapshot', {codeId: id, purpose: 'campus', format: 'qrBytes',
      matrixSize: 21, matrixEncoding: 'base64-msb', matrix: Buffer.alloc(56).toString('base64'),
      validFromMs: 1000000, validUntilMs: 1005000}, {replyTo});
  }
  code('oldCode'); code('newCode');
  assert.equal(f.state().code.id, 'newCode');
  assert.equal(f.state().codeLoading, false);
});

test('snapshot resynchronizes a delayed opening clock without moving it backwards', () => {
  const f = fixture(); f.open();
  f.link.request('code'); const replyTo = f.last().id;
  f.advanceWithoutTick(100);
  f.send('campusCode.snapshot', {codeId: 'fresh', purpose: 'campus', format: 'qrBytes',
    matrixSize: 21, matrixEncoding: 'base64-msb', matrix: Buffer.alloc(56).toString('base64'),
    validFromMs: 1000250, validUntilMs: 1030250}, {replyTo, sentAtMs: 1000250});
  assert.equal(f.state().code.id, 'fresh');
  assert.equal(f.link.phoneNow(), 1000250);
  f.send('session.ping', {}, {sentAtMs: 1000100});
  assert.equal(f.link.phoneNow(), 1000250);
});


test('timetable outlives the session TTL and clears only on explicit revocation', () => {
  const f = fixture(); f.open();
  const item = {name: '物理😀', location: '教学楼 201', startAtMs: 1050000, endAtMs: 1100000};
  f.send('schedule.snapshot', {revision: 2, validUntilMs: 1020000, items: [item]});
  assert.equal(f.state().scheduleReady, true);
  assert.equal(f.last().body.resource, 'schedule');
  f.send('schedule.snapshot', {revision: 1, validUntilMs: 1020000, items: []});
  assert.equal(f.last().body.code, 'STALE_REVISION');
  f.send('schedule.snapshot', {revision: 3, validUntilMs: 1020000, items: [{...item, endAtMs: 0}]});
  assert.equal(f.last().body.code, 'INVALID_PAYLOAD');
  assert.equal(f.state().schedule.length, 1);
  f.advance(20000); assert.equal(f.state().schedule.length, 1);
  f.send('schedule.snapshot', {revision: 3, validUntilMs: 1050000, items: [item]});
  f.send('session.clear'); assert.equal(f.state().schedule.length, 0);
});
test('sync requests negotiate timetable support from the phone hello', () => {
  const f = fixture(); f.open(); f.link.request('sync');
  assert.deepEqual(f.last().body.resources, ['account', 'ddl']);
  f.send('session.hello', {nonce: 'nonce', versions: [1], capabilities: ['schedule.display']});
  f.send('session.open', {nonce: 'nonce', sessionId: 'session', bindingId: 'binding', phoneTimeMs: 1000000, leaseUntilMs: 2000000});
  f.link.request('sync'); assert.deepEqual(f.last().body.resources, ['account', 'ddl', 'schedule']);
});
test('local reminder fires once, ignores old or completed deadlines, and clears on revoke', () => {
  const f = fixture(); f.open();
  const item = {id: 'ddl', title: '实验报告', courseName: '物理', dueAtMs: 1100000, status: 'open', remindAtMs: [1002000]};
  f.send('ddl.snapshot', {revision: 1, validUntilMs: 1200000, remindersEnabled: true, items: [item,
    {...item, id: 'old', remindAtMs: [999000]}, {...item, id: 'done', status: 'completed'}]});
  assert.equal(f.state().alert, null);
  f.advance(2000); assert.equal(f.state().alert.title, '实验报告'); assert.equal(f.state().alert.count, 1);
  f.link.alert = null; f.advance(1000); assert.equal(f.state().alert, null);
  f.send('ddl.snapshot', {revision: 2, validUntilMs: 1200000, remindersEnabled: false, items: [item]});
  assert.equal(f.state().remindersEnabled, false);
  f.send('session.close'); assert.equal(f.state().alert, null);
});
test('malformed reminder times reject the entire snapshot', () => {
  const f = fixture(); f.open();
  f.send('ddl.snapshot', {revision: 1, validUntilMs: 1200000, items: [
    {id: 'a', title: '作业', courseName: '', dueAtMs: 1100000, status: 'open', remindAtMs: ['invalid']} ]});
  assert.equal(f.last().body.code, 'INVALID_PAYLOAD'); assert.equal(f.state().ddlReady, false);
});


test('cached account and resources survive heartbeat loss, stop and a new process', () => {
  const f = fixture(); f.open();
  f.send('account.snapshot', {revision: 1, validUntilMs: 1020000, data: {name: '张三', studentId: '00123'}});
  f.send('ddl.snapshot', {revision: 1, validUntilMs: 1020000, items: [{id: 'a', title: '作业', courseName: '数学', dueAtMs: 9000000, status: 'open'}]});
  f.send('schedule.snapshot', {revision: 1, validUntilMs: 1020000, items: [{name: '物理', location: '201', startAtMs: 8000000, endAtMs: 9000000}]});
  const saved = JSON.parse(JSON.stringify(f.link.exportCache()));
  f.advance(7200000); f.link.reset(false);
  assert.equal(f.state().connected, false); assert.equal(f.state().name, '张三');
  assert.equal(f.state().ddl.length, 1); assert.equal(f.state().schedule.length, 1);
  const restarted = fixture({cache: saved});
  assert.equal(restarted.state().name, '张三'); assert.equal(restarted.state().ddl.length, 1);
  assert.equal(restarted.state().connected, false); assert.equal(restarted.state().code, null);
  assert.equal('session' in saved, false); assert.equal('code' in saved, false);
  restarted.open(); assert.equal(restarted.state().name, '张三');
  restarted.send('session.hello', {nonce: 'next', versions: [1]});
  restarted.send('session.open', {nonce: 'next', sessionId: 'other', bindingId: 'other-owner', phoneTimeMs: 1000000, leaseUntilMs: 2000000});
  assert.equal(restarted.state().name, ''); assert.equal(restarted.state().ddl.length, 0);
});

test('positive snapshot receipts wait for persistence; failed writes are reported', () => {
  const writes = [];
  const f = fixture({onCache(cache, done) { writes.push({cache, done}); }});
  f.open(); writes.shift().done();
  f.send('account.snapshot', {revision: 1, validUntilMs: 2000000, data: {name: '张三', studentId: '00123'}});
  assert.equal(f.last().type, 'session.opened');
  writes.shift().done('DISK_FULL'); assert.equal(f.last().body.code, 'STORAGE_FAILED');
  f.send('account.snapshot', {revision: 1, validUntilMs: 2000000, data: {name: '张三', studentId: '00123'}});
  writes.shift().done(); assert.equal(f.last().body.status, 'ok');
  f.send('session.clear'); const deletion = writes.shift();
  assert.equal(deletion.cache.owner, null); assert.equal(deletion.cache.account, null);
  deletion.done(); assert.equal(f.last().body.status, 'ok');
});

test('online-only watches reject a legacy grant message', () => {
  const f = fixture();
  f.open();
  f.send('campusCode.authorization', {credential: null});
  assert.equal(f.last().body.code, 'UNSUPPORTED_OPERATION');
});
