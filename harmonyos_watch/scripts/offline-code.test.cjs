const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../entry/src/main/js/MainAbility/common');
function core() {
  const context = {sm2: require(root + '/vendor/sm2.js'), integers: require(root + '/vendor/jsbn.js'),
    qrcode: require(root + '/vendor/qrcode.js')};
  vm.createContext(context);
  for (const file of ['offline-code.js', 'qr-matrix.js']) {
    vm.runInContext(fs.readFileSync(root + '/' + file, 'utf8').replace(/^import .*;\n/gm, '').replace(/export function /g, 'function '), context);
  }
  return context;
}
const grant = {cardID: 'fixture', privateKey: '0'.repeat(63) + '1', publicKey: '0232c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7',
  authorInfo: '5638A1B2C3D40080FF', deviceChecksum: 206, totalUses: null, expiresAt: 1798761600};
const now = Date.UTC(2026, 7, 31, 12);
test('SM2 fixture preserves author bytes and time CRC and matches the cross-language signature', () => {
  const c = core(), prepared = c.prepareCredential(grant, n => new Uint8Array(n).fill(1));
  const frame = c.generateOfflineCode(prepared, now);
  const value = Buffer.from(frame.payload).toString('hex');
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/offline-sm2.json')));
  assert.equal(value, fixture.payloadHex); assert.equal(value.slice(0, 28), '5638a1b2c3d40080ff6a956cc09d');
  assert.equal(frame.until, now + 30000);
  assert.throws(() => c.generateOfflineCode(prepared, grant.expiresAt * 1000), /EXPIRED/);
});
test('signing rejects unavailable native entropy and a mismatched public key', () => {
  const c = core();
  const prepared = c.prepareCredential(grant, () => { throw new Error('NO_NATIVE_ENTROPY'); });
  assert.throws(() => c.generateOfflineCode(prepared, now), /NO_NATIVE_ENTROPY/);
  assert.throws(() => c.prepareCredential({...grant, publicKey: '03' + grant.publicKey.slice(2)}, n => new Uint8Array(n)), /MISMATCH/);
});
test('byte-only QR subset retains the upstream matrix for NUL, high bytes and a full campus payload', () => {
  const c = core();
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/offline-sm2.json')));
  const bytes = [...Buffer.from(fixture.payloadHex, 'hex')];
  const encoded = c.encodeQr(bytes);
  assert.equal(encoded.size, fixture.matrixSize);
  assert.equal(Buffer.from(encoded.bytes).toString('base64'), fixture.matrixBase64);
});
module.exports = {core, grant, now};
