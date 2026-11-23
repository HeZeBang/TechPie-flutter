// Signing subset of sm-crypto 0.3.13 (MIT); see vendor/THIRD_PARTY.md.
const {BigInteger} = require('./jsbn');
const _ = require('./utils');
const {sm3} = require('./sm3');
const {curve, G, n} = _.generateEcparam();
function doSignature(msg, privateKey, {
  pointPool, der, hash, publicKey, userId
} = {}) {
  let hashHex = typeof msg === 'string' ? _.utf8ToHex(msg) : _.arrayToHex(msg)

  if (hash) {
    // sm3杂凑
    publicKey = publicKey || getPublicKeyFromPrivateKey(privateKey)
    hashHex = getHash(hashHex, publicKey, userId)
  }

  const dA = new BigInteger(privateKey, 16)
  const e = new BigInteger(hashHex, 16)

  // k
  let k = null
  let r = null
  let s = null

  do {
    do {
      let point
      if (pointPool && pointPool.length) {
        point = pointPool.pop()
      } else {
        point = getPoint()
      }
      k = point.k

      // r = (e + x1) mod n
      r = e.add(point.x1).mod(n)
    } while (r.equals(BigInteger.ZERO) || r.add(k).equals(n))

    // s = ((1 + dA)^-1 * (k - r * dA)) mod n
    s = dA.add(BigInteger.ONE).modInverse(n).multiply(k.subtract(r.multiply(dA))).mod(n)
  } while (s.equals(BigInteger.ZERO))

  if (der) throw new Error('DER_NOT_SUPPORTED') // asn.1 der 编码

  return _.leftPad(r.toString(16), 64) + _.leftPad(s.toString(16), 64)
}

function getHash(hashHex, publicKey, userId = '1234567812345678') {
  // z = hash(entl || userId || a || b || gx || gy || px || py)
  userId = _.utf8ToHex(userId)
  const a = _.leftPad(G.curve.a.toBigInteger().toRadix(16), 64)
  const b = _.leftPad(G.curve.b.toBigInteger().toRadix(16), 64)
  const gx = _.leftPad(G.getX().toBigInteger().toRadix(16), 64)
  const gy = _.leftPad(G.getY().toBigInteger().toRadix(16), 64)
  let px
  let py
  if (publicKey.length === 128) {
    px = publicKey.substr(0, 64)
    py = publicKey.substr(64, 64)
  } else {
    const point = G.curve.decodePointHex(publicKey)
    px = _.leftPad(point.getX().toBigInteger().toRadix(16), 64)
    py = _.leftPad(point.getY().toBigInteger().toRadix(16), 64)
  }
  const data = _.hexToArray(userId + a + b + gx + gy + px + py)

  const entl = userId.length * 4
  data.unshift(entl & 0x00ff)
  data.unshift(entl >> 8 & 0x00ff)

  const z = sm3(data)

  // e = hash(z || msg)
  return _.arrayToHex(sm3(z.concat(_.hexToArray(hashHex))))
}

/**
 * 计算公钥
 */
function getPublicKeyFromPrivateKey(privateKey) {
  const PA = G.multiply(new BigInteger(privateKey, 16))
  const x = _.leftPad(PA.getX().toBigInteger().toString(16), 64)
  const y = _.leftPad(PA.getY().toBigInteger().toString(16), 64)
  return '04' + x + y
}

/**
 * 获取椭圆曲线点
 */
function getPoint() {
  const keypair = _.generateKeyPairHex()
  const PA = curve.decodePointHex(keypair.publicKey)

  keypair.k = new BigInteger(keypair.privateKey, 16)
  keypair.x1 = PA.getX().toBigInteger()

  return keypair
}


module.exports = {doSignature, getPublicKeyFromPrivateKey};
