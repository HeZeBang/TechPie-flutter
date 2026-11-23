// Signing subset of sm-crypto 0.3.13 (MIT); see vendor/THIRD_PARTY.md.
const {BigInteger, SecureRandom} = require('./jsbn');
const {generateEcparam, leftPad, hexToArray} = require('./utils');
const {sm3} = require('./sm3');
const {curve, G, n} = generateEcparam();
const one = BigInteger.ONE;
const maxKey = n.subtract(one);
const rng = new SecureRandom();

// Four-column fixed-base comb. The public columns are [2^(64*i)]G.
const table = [curve.infinity, G];
const columns = [
  '0495afbd1155c1da54ba220b99df9f9a14673891d791caa486e18bd546b5824517e8a6d82c517388c22eee750f4053017cc3c7d1898a53f20d8e4450eb334acdcb',
  '04b692e5b574d55da93db7b24888c21f3a2b2308f6484e1b38eae3d9a9d13a42eda175051b0f3fb6135a924f85544926f9db61ac1773438e6dd186469de295e5ab',
  '04793fae7af016424544c0757f3bb8b60016888d8ee4003187ad8bc68ce031d616e03d7a8d19b3219a65c5b129f5f7ad5d08666ff52dbd25f9210cd042973f333b',
];
function startMultiply(scalar) {
  if (table.length === 2) {
    for (let i = 0; i < columns.length; i++) {
      const base = curve.decodePointHex(columns[i]);
      const offset = table.length;
      for (let j = 0; j < offset; j++) table.push(j ? table[j].add(base) : base);
    }
  }
  let row = 63, point = curve.infinity;
  return function step() {
    let digit = 0;
    for (let col = 0; col < 4; col++) {
      if (scalar.testBit(row + 64 * col)) digit += 1 << col;
    }
    point = point.twice();
    if (digit) point = point.add(table[digit]);
    return --row < 0 ? point : null;
  };
}
function hex(value) { return leftPad(value.toString(16), 64); }
function prepare(key, point, expected) {
  const yValue = point.getY().toBigInteger();
  const x = hex(point.getX().toBigInteger()), y = hex(yValue);
  if ((yValue.testBit(0) ? '03' : '02') + x !== expected.toLowerCase()) throw new Error('OFFLINE_KEY_MISMATCH');
  const domain = hex(curve.a.toBigInteger()) + hex(curve.b.toBigInteger()) +
    hex(G.getX().toBigInteger()) + hex(G.getY().toBigInteger());
  // ENTL=128, default SM2 user ID 1234567812345678.
  return {key, inverse: key.add(one).modInverse(n),
    za: sm3(hexToArray('008031323334353637383132333435363738' + domain + x + y))};
}
function nonce() { return new BigInteger(n.bitLength(), rng).mod(maxKey).add(one); }
function signature(message, prepared, k, point) {
  const e = new BigInteger(sm3(prepared.za.concat(message)).map(b => leftPad(b.toString(16), 2)).join(''), 16);
  const r = e.add(point.getX().toBigInteger()).mod(n);
  if (!r.signum() || r.add(k).equals(n)) return null;
  const s = prepared.inverse.multiply(k.subtract(r.multiply(prepared.key))).mod(n);
  return s.signum() ? hexToArray(hex(r) + hex(s)) : null;
}
module.exports = {startMultiply, prepare, nonce, signature, maxKey};
