const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../entry/src/main/js/MainAbility/common');
function core() {
  const context = {makeSigner: require(root + '/sm2.js').makeSigner,
    points: require(root + '/sm2-points.json'), qrcode: require(root + '/vendor/qrcode.js')};
  vm.createContext(context);
  for (const file of ['offline-code.js', 'qr-matrix.js']) {
    vm.runInContext(fs.readFileSync(root + '/' + file, 'utf8').replace(/^import .*;\n/gm, '').replace(/export function /g, 'function '), context);
  }
  return context;
}
const grant = {cardID: 'fixture', privateKey: '0'.repeat(63) + '1', publicKey: '0232c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7',
  authorInfo: '5638A1B2C3D40080FF', deviceChecksum: 206, totalUses: null, expiresAt: 1798761600};
const now = Date.UTC(2026, 7, 31, 12);
function finish(step) {
  for (let i = 0; i < 256; i++) {
    const result = step();
    if (result) return result;
  }
  throw new Error('Job did not finish');
}
const deterministic = n => { const bytes = new Uint8Array(n).fill(1); bytes[n-1]++; return bytes; };
test('incremental signing preserves the shared signature and can reuse the prepared grant', () => {
  const c = core(), job = c.startOfflineCode(grant, null, deterministic, () => now, c.points);
  assert.equal(job.step(), null);
  const frame = finish(job.step);
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/offline-sm2.json')));
  assert.equal(Buffer.from(frame.payload).toString('hex'), fixture.payloadHex);
  assert.equal(frame.until, now + 30000);
  const next = c.startOfflineCode(grant, job.prepared, deterministic, () => now, c.points);
  assert.equal(Buffer.from(finish(next.step).payload).toString('hex'), fixture.payloadHex);
  const pending = c.startOfflineCode(grant, null, deterministic, () => grant.expiresAt * 1000, c.points);
  assert.throws(pending.step, /EXPIRED/);
});
test('fixed-base comb agrees with OpenSSL for full-length scalars', () => {
  const {createECDH} = require('node:crypto');
  const c = core(), ec = createECDH('SM2');
  for (const hex of ['1', '0123456789abcdef'.repeat(4), 'fedcba9876543210'.repeat(4)]) {
    ec.setPrivateKey(Buffer.from(hex.padStart(64, '0'), 'hex'));
    const job = c.makeSigner(c.points).makePublicJob(hex.padStart(64, '0'));
    finish(job.step);
    const p = job.result();
    assert.equal('04' + p.x + p.y, ec.getPublicKey('hex'));
  }
});
test('signing rejects unavailable entropy and a mismatched public key', () => {
  const c = core();
  assert.throws(() => finish(c.startOfflineCode(grant, null, () => { throw new Error('NO_NATIVE_ENTROPY'); }, () => now, c.points).step), /NO_NATIVE_ENTROPY/);
  assert.throws(() => finish(c.startOfflineCode({...grant, publicKey: '03' + grant.publicKey.slice(2)}, null, deterministic, () => now, c.points).step), /MISMATCH/);
});
test('incremental QR mask selection preserves the shared byte matrix', () => {
  const c = core(), fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/offline-sm2.json')));
  const step = c.startQr([...Buffer.from(fixture.payloadHex, 'hex')]);
  for (let mask = 0; mask < 8; mask++) assert.equal(step(), null);
  const encoded = step();
  assert.equal(encoded.size, fixture.matrixSize);
  assert.equal(Buffer.from(encoded.bytes).toString('base64'), fixture.matrixBase64);
});
module.exports = {core, grant, now};
