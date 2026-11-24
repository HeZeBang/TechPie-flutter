// Adapted from steven42121/techpie_wear, commit 8348b36 (Apache-2.0).
// GT 6 Pro diagnostic port: compact lazy point table, Lite-compatible arrays,
// and a stepped signing entry point. See LICENSE.techpie_wear.
// AUTO-GENERATED from /tmp/sm2opt (SM3 + Montgomery CIOS + Jacobian SM2).
// Byte-compatible with Dart Sm2OfflineCrypto (verified against dart-sm2.json fixture).


const CONSTS = {
  P: 'fffffffeffffffffffffffffffffffffffffffff00000000ffffffffffffffff',
  N: 'fffffffeffffffffffffffffffffffff7203df6b21c6052b53bbf40939d54123',
  A: 'fffffffeffffffffffffffffffffffffffffffff00000000fffffffffffffffc',
  B: '28e9fa9e9d9f5e344d5a9e4bcf6509a7f39789f515ab8f92ddbcbd414d940e93',
  GX: '32c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7',
  GY: 'bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0',
  montN: { Rmod: '000000010000000000000000000000008dfc2094de39fad4ac440bf6c62abedd', R2: '1eb5e412a22b3d3b620fc84c3affe0d43464504ade6fa2fa901192af7c114f20', n0inv: 2421 },
  // Affine coordinates of signed comb points. Block h, mask m, top sign +1:
  // sum(sign[j] * 2^(128*h + 16*j) * G) for j in [0,7].
}


// SM3 hash (GB/T 32918.4). Pure JS, 32-bit ops, no BigInt.

function rotl(x, n) { return ((x << n) | (x >>> (32 - n))) >>> 0 }

function sm3Bytes(input) {
  const len = input.length
  const bitLen = len * 8
  const padded = []
  for (let i = 0; i < len; i++) padded.push(input[i] & 0xff)
  padded.push(0x80)
  const blocks = Math.ceil((padded.length + 8) / 64)
  const total = blocks * 64
  while (padded.length < total - 8) padded.push(0)
  // 64-bit big-endian bit length (JS numbers cover up to 2^53 bits)
  const hi = Math.floor(bitLen / 0x100000000)
  const lo = bitLen >>> 0
  padded.push((hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff)
  padded.push((lo >>> 24) & 0xff, (lo >>> 16) & 0xff, (lo >>> 8) & 0xff, lo & 0xff)

  let v0 = 0x7380166f, v1 = 0x4914b2b9, v2 = 0x172442d7, v3 = 0xda8a0600,
      v4 = 0xa96f30bc, v5 = 0x163138aa, v6 = 0xe38dee4d, v7 = 0xb0fb0e4e

  const w = new Array(68)
  const w1 = new Array(64)

  for (let off = 0; off < total; off += 64) {
    for (let j = 0; j < 16; j++) {
      const i = off + j * 4
      w[j] = ((padded[i] << 24) | (padded[i + 1] << 16) | (padded[i + 2] << 8) | padded[i + 3]) >>> 0
    }
    for (let j = 16; j < 68; j++) {
      const x = w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)
      w[j] = (x ^ rotl(x, 15) ^ rotl(x, 23) ^ rotl(w[j - 13], 7) ^ w[j - 6]) >>> 0
    }
    for (let j = 0; j < 64; j++) w1[j] = (w[j] ^ w[j + 4]) >>> 0

    let a = v0, b = v1, c = v2, d = v3, e = v4, f = v5, g = v6, h = v7
    for (let j = 0; j < 64; j++) {
      const tj = j < 16 ? 0x79cc4519 : 0x7a879d8a
      const a12 = rotl(a, 12)
      const ss1 = (rotl((a12 + e + rotl(tj, j % 32)) >>> 0, 7)) >>> 0
      const ss2 = (ss1 ^ a12) >>> 0
      let ff, gg
      if (j < 16) {
        ff = (a ^ b ^ c) >>> 0
        gg = (e ^ f ^ g) >>> 0
      } else {
        ff = ((a & b) | (a & c) | (b & c)) >>> 0
        gg = ((e & f) | (~e & g)) >>> 0
      }
      const tt1 = (ff + d + ss2 + w1[j]) >>> 0
      const tt2 = (gg + h + ss1 + w[j]) >>> 0
      d = c
      c = rotl(b, 9)
      b = a
      a = (tt1) >>> 0
      h = g
      g = rotl(f, 19)
      f = e
      e = (tt2 ^ rotl(tt2, 9) ^ rotl(tt2, 17)) >>> 0 // P0(TT2)
    }
    v0 = (v0 ^ a) >>> 0; v1 = (v1 ^ b) >>> 0; v2 = (v2 ^ c) >>> 0; v3 = (v3 ^ d) >>> 0
    v4 = (v4 ^ e) >>> 0; v5 = (v5 ^ f) >>> 0; v6 = (v6 ^ g) >>> 0; v7 = (v7 ^ h) >>> 0
  }

  const out = new Array(32)
  const regs = [v0, v1, v2, v3, v4, v5, v6, v7]
  for (let j = 0; j < 8; j++) {
    out[j * 4] = (regs[j] >>> 24) & 0xff
    out[j * 4 + 1] = (regs[j] >>> 16) & 0xff
    out[j * 4 + 2] = (regs[j] >>> 8) & 0xff
    out[j * 4 + 3] = regs[j] & 0xff
  }
  return out
}

function bytesToHex(bytes) {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += ('0' + bytes[i].toString(16)).slice(-2)
  return s
}

function hexToBytes(hex) {
  const out = new Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16)
  return out
}

function sm3Hex(inputBytes) { return bytesToHex(sm3Bytes(inputBytes)) }



// 256-bit modular arithmetic, 16-bit limbs, no BigInt in the hot paths.
// Plain ctx: add/sub/inv (generic odd modulus).
// Mont ctx: CIOS Montgomery multiplication for fast field arithmetic.

const LIMBS = 16

function hexToLimbs(hex) {
  const out = new Array(LIMBS)
  for (let i = 0; i < LIMBS; i++) {
    const end = hex.length - i * 4
    out[i] = parseInt(hex.substring(end - 4, end), 16)
  }
  return out
}

function limbsToHex(a) {
  let s = ''
  for (let i = LIMBS - 1; i >= 0; i--) s += ('000' + a[i].toString(16)).slice(-4)
  return s
}

function clear(array) { for (let i = 0; i < array.length; i++) array[i] = 0; return array }
function zeros() { return clear(new Array(LIMBS)) }

function cmp(a, b) {
  for (let i = LIMBS - 1; i >= 0; i--) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1
  }
  return 0
}

function subInto(r, a, b) {
  let borrow = 0
  for (let i = 0; i < LIMBS; i++) {
    let d = a[i] - b[i] - borrow
    if (d < 0) { d += 0x10000; borrow = 1 } else { borrow = 0 }
    r[i] = d
  }
  return borrow
}

function addInto(r, a, b) {
  let carry = 0
  for (let i = 0; i < LIMBS; i++) {
    let s = a[i] + b[i] + carry
    if (s >= 0x10000) { s -= 0x10000; carry = 1 } else { carry = 0 }
    r[i] = s
  }
  return carry
}

function isZero(a) { for (let i = 0; i < LIMBS; i++) if (a[i] !== 0) return false; return true }
function isOne(a) {
  if (a[0] !== 1) return false
  for (let i = 1; i < LIMBS; i++) if (a[i] !== 0) return false
  return true
}
function isEven(a) { return (a[0] & 1) === 0 }
// Generic modulus context (modulus M odd, < 2^256).
function ModCtx(modHex) {
  const M = hexToLimbs(modHex)

  function add(a, b) {
    const r = zeros()
    const carry = addInto(r, a, b)
    if (carry || cmp(r, M) >= 0) subInto(r, r, M)
    return r
  }
  function double(a) { return add(a, a) }
  function triple(a) { return add(a, double(a)) }
  function sub(a, b) {
    const r = zeros()
    const borrow = subInto(r, a, b)
    if (borrow) addInto(r, r, M)
    return r
  }
  // Binary extended Euclid inverse mod odd M.
  // 原地二进制扩展欧几里得：每实例一套固定缓冲，每次求逆零分配。
  const iu = zeros()
  const iv = zeros()
  const ix1 = zeros()
  const ix2 = zeros()
  function shiftRight1Into(r, a) {
    for (let i = 0; i < LIMBS; i++) {
      const next = i + 1 < LIMBS ? a[i + 1] : 0
      r[i] = (a[i] >> 1) | ((next & 1) ? 0x8000 : 0)
    }
  }
  function halveSumInto(r, a, b) {
    const carry = addInto(r, a, b)
    let high = carry
    for (let i = LIMBS - 1; i >= 0; i--) {
      const cur = r[i]
      r[i] = (cur >> 1) | (high ? 0x8000 : 0)
      high = cur & 1
    }
  }
  function inv(a) {
    for (let i = 0; i < LIMBS; i++) {
      iu[i] = a[i]
      iv[i] = M[i]
    }
    clear(ix1)
    ix1[0] = 1
    clear(ix2)
    while (!isOne(iu) && !isOne(iv)) {
      if (isEven(iu)) {
        shiftRight1Into(iu, iu)
        if (isEven(ix1)) shiftRight1Into(ix1, ix1)
        else halveSumInto(ix1, ix1, M)
      } else if (isEven(iv)) {
        shiftRight1Into(iv, iv)
        if (isEven(ix2)) shiftRight1Into(ix2, ix2)
        else halveSumInto(ix2, ix2, M)
      } else if (cmp(iu, iv) >= 0) {
        subInto(iu, iu, iv)
        const borrow = subInto(ix1, ix1, ix2)
        if (borrow) addInto(ix1, ix1, M)
      } else {
        subInto(iv, iv, iu)
        const borrow = subInto(ix2, ix2, ix1)
        if (borrow) addInto(ix2, ix2, M)
      }
    }
    const out = new Array(LIMBS)
    const src = isOne(iu) ? ix1 : ix2
    for (let i = 0; i < LIMBS; i++) out[i] = src[i]
    return out
  }
  return { M, add, double, triple, sub, inv }
}

// Montgomery CIOS context for modulus M.
// R = 2^256. Values "in Montgomery form" are a*R mod M.
// montMul(x, y) = x*y*R^-1 mod M.
function MontCtx(modHex, RmodHex, R2Hex, n0inv) {
  const M = hexToLimbs(modHex)
  const ONE = hexToLimbs(RmodHex) // R mod M
  const R2 = hexToLimbs(R2Hex) // R^2 mod M
  const plain = ModCtx(modHex)

  // CIOS with the 16x16 inner loops unrolled 4x (20% faster on QuickJS).
  // 写入调用方缓冲的版本：点运算热路径用它，零分配。
  const t = new Array(18)
function montMulInto(r, a, b) {
  t[0]=t[1]=t[2]=t[3]=t[4]=t[5]=t[6]=t[7]=t[8]=t[9]=t[10]=t[11]=t[12]=t[13]=t[14]=t[15]=0; t[16]=0; t[17]=0
  for (let i = 0; i < 16; i++) {
    let C = 0
    const bi = b[i]
    { const v = t[0] + a[0] * bi + C; t[0] = v & 0xffff; C = v >>> 16 }
    { const v = t[1] + a[1] * bi + C; t[1] = v & 0xffff; C = v >>> 16 }
    { const v = t[2] + a[2] * bi + C; t[2] = v & 0xffff; C = v >>> 16 }
    { const v = t[3] + a[3] * bi + C; t[3] = v & 0xffff; C = v >>> 16 }
    { const v = t[4] + a[4] * bi + C; t[4] = v & 0xffff; C = v >>> 16 }
    { const v = t[5] + a[5] * bi + C; t[5] = v & 0xffff; C = v >>> 16 }
    { const v = t[6] + a[6] * bi + C; t[6] = v & 0xffff; C = v >>> 16 }
    { const v = t[7] + a[7] * bi + C; t[7] = v & 0xffff; C = v >>> 16 }
    { const v = t[8] + a[8] * bi + C; t[8] = v & 0xffff; C = v >>> 16 }
    { const v = t[9] + a[9] * bi + C; t[9] = v & 0xffff; C = v >>> 16 }
    { const v = t[10] + a[10] * bi + C; t[10] = v & 0xffff; C = v >>> 16 }
    { const v = t[11] + a[11] * bi + C; t[11] = v & 0xffff; C = v >>> 16 }
    { const v = t[12] + a[12] * bi + C; t[12] = v & 0xffff; C = v >>> 16 }
    { const v = t[13] + a[13] * bi + C; t[13] = v & 0xffff; C = v >>> 16 }
    { const v = t[14] + a[14] * bi + C; t[14] = v & 0xffff; C = v >>> 16 }
    { const v = t[15] + a[15] * bi + C; t[15] = v & 0xffff; C = v >>> 16 }
    { const v = t[16] + C; t[16] = v & 0xffff; t[17] = v >>> 16 }
    const m = (t[0] * n0inv) & 0xffff
    { const v = t[0] + M[0] * m; C = v >>> 16 }
    { const v = t[1] + M[1] * m + C; t[0] = v & 0xffff; C = v >>> 16 }
    { const v = t[2] + M[2] * m + C; t[1] = v & 0xffff; C = v >>> 16 }
    { const v = t[3] + M[3] * m + C; t[2] = v & 0xffff; C = v >>> 16 }
    { const v = t[4] + M[4] * m + C; t[3] = v & 0xffff; C = v >>> 16 }
    { const v = t[5] + M[5] * m + C; t[4] = v & 0xffff; C = v >>> 16 }
    { const v = t[6] + M[6] * m + C; t[5] = v & 0xffff; C = v >>> 16 }
    { const v = t[7] + M[7] * m + C; t[6] = v & 0xffff; C = v >>> 16 }
    { const v = t[8] + M[8] * m + C; t[7] = v & 0xffff; C = v >>> 16 }
    { const v = t[9] + M[9] * m + C; t[8] = v & 0xffff; C = v >>> 16 }
    { const v = t[10] + M[10] * m + C; t[9] = v & 0xffff; C = v >>> 16 }
    { const v = t[11] + M[11] * m + C; t[10] = v & 0xffff; C = v >>> 16 }
    { const v = t[12] + M[12] * m + C; t[11] = v & 0xffff; C = v >>> 16 }
    { const v = t[13] + M[13] * m + C; t[12] = v & 0xffff; C = v >>> 16 }
    { const v = t[14] + M[14] * m + C; t[13] = v & 0xffff; C = v >>> 16 }
    { const v = t[15] + M[15] * m + C; t[14] = v & 0xffff; C = v >>> 16 }
    { const v = t[16] + C; t[15] = v & 0xffff; t[16] = t[17] + (v >>> 16); t[17] = 0 }
  }
  for (let j = 0; j < 16; j++) r[j] = t[j]
  if (t[16] !== 0 || cmp(r, M) >= 0) subInto(r, r, M)
}

function montMul(a, b) {
  const r = new Array(16)
  montMulInto(r, a, b)
  return r
}

  function toMont(a) { return montMul(a, R2) }
  const PLAIN_ONE = hexToLimbs('0000000000000000000000000000000000000000000000000000000000000001')
  function fromMont(a) { return montMul(a, PLAIN_ONE) }

  function add(a, b) { return plain.add(a, b) }
  function double(a) { return plain.double(a) }
  function sub(a, b) { return plain.sub(a, b) }
  function triple(a) { return plain.triple(a) }
  // inverse of Montgomery value a = x*R: returns x^-1 * R.
  function inv(a) { return toMont(plain.inv(fromMont(a))) }

  return { M, ONE, montMul, montMulInto, toMont, fromMont, add, double, sub, triple, inv, plain }
}



// Ordinary field residues in radix B = 2^16. The SM2 field prime satisfies
// B^16 = B^14 + B^6 - B^4 + 1 (mod p). The largest folded coefficient
// is below 2^40, within the exact integer range of a JS Number.
function primeField(pHex) {
  const plain = ModCtx(pHex)
  const t = new Array(31)
  function mulInto(out, a, b) {
    // Column k collects a[i] * b[k-i]. A column fits in 36 exact integer
    // bits. Cache the input limbs and write each scratch column once.
    // Squaring doubles each off-diagonal pair and adds the diagonal once.
    const a0 = a[0], a1 = a[1], a2 = a[2], a3 = a[3]
    const a4 = a[4], a5 = a[5], a6 = a[6], a7 = a[7]
    const a8 = a[8], a9 = a[9], a10 = a[10], a11 = a[11]
    const a12 = a[12], a13 = a[13], a14 = a[14], a15 = a[15]
    if (a === b) {
      t[0] = a0 * a0
      t[1] = 2 * (a0 * a1)
      t[2] = 2 * (a0 * a2) + a1 * a1
      t[3] = 2 * (a0 * a3 + a1 * a2)
      t[4] = 2 * (a0 * a4 + a1 * a3) + a2 * a2
      t[5] = 2 * (a0 * a5 + a1 * a4 + a2 * a3)
      t[6] = 2 * (a0 * a6 + a1 * a5 + a2 * a4) + a3 * a3
      t[7] = 2 * (a0 * a7 + a1 * a6 + a2 * a5 + a3 * a4)
      t[8] = 2 * (a0 * a8 + a1 * a7 + a2 * a6 + a3 * a5) + a4 * a4
      t[9] = 2 * (a0 * a9 + a1 * a8 + a2 * a7 + a3 * a6 + a4 * a5)
      t[10] = 2 * (a0 * a10 + a1 * a9 + a2 * a8 + a3 * a7 + a4 * a6) + a5 * a5
      t[11] = 2 * (a0 * a11 + a1 * a10 + a2 * a9 + a3 * a8 + a4 * a7 + a5 * a6)
      t[12] = 2 * (a0 * a12 + a1 * a11 + a2 * a10 + a3 * a9 + a4 * a8 + a5 * a7) + a6 * a6
      t[13] = 2 * (a0 * a13 + a1 * a12 + a2 * a11 + a3 * a10 + a4 * a9 + a5 * a8 + a6 * a7)
      t[14] = 2 * (a0 * a14 + a1 * a13 + a2 * a12 + a3 * a11 + a4 * a10 + a5 * a9 + a6 * a8) + a7 * a7
      t[15] = 2 * (a0 * a15 + a1 * a14 + a2 * a13 + a3 * a12 + a4 * a11 + a5 * a10 + a6 * a9 + a7 * a8)
      t[16] = 2 * (a1 * a15 + a2 * a14 + a3 * a13 + a4 * a12 + a5 * a11 + a6 * a10 + a7 * a9) + a8 * a8
      t[17] = 2 * (a2 * a15 + a3 * a14 + a4 * a13 + a5 * a12 + a6 * a11 + a7 * a10 + a8 * a9)
      t[18] = 2 * (a3 * a15 + a4 * a14 + a5 * a13 + a6 * a12 + a7 * a11 + a8 * a10) + a9 * a9
      t[19] = 2 * (a4 * a15 + a5 * a14 + a6 * a13 + a7 * a12 + a8 * a11 + a9 * a10)
      t[20] = 2 * (a5 * a15 + a6 * a14 + a7 * a13 + a8 * a12 + a9 * a11) + a10 * a10
      t[21] = 2 * (a6 * a15 + a7 * a14 + a8 * a13 + a9 * a12 + a10 * a11)
      t[22] = 2 * (a7 * a15 + a8 * a14 + a9 * a13 + a10 * a12) + a11 * a11
      t[23] = 2 * (a8 * a15 + a9 * a14 + a10 * a13 + a11 * a12)
      t[24] = 2 * (a9 * a15 + a10 * a14 + a11 * a13) + a12 * a12
      t[25] = 2 * (a10 * a15 + a11 * a14 + a12 * a13)
      t[26] = 2 * (a11 * a15 + a12 * a14) + a13 * a13
      t[27] = 2 * (a12 * a15 + a13 * a14)
      t[28] = 2 * (a13 * a15) + a14 * a14
      t[29] = 2 * (a14 * a15)
      t[30] = a15 * a15
    } else {
      const b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3]
      const b4 = b[4], b5 = b[5], b6 = b[6], b7 = b[7]
      const b8 = b[8], b9 = b[9], b10 = b[10], b11 = b[11]
      const b12 = b[12], b13 = b[13], b14 = b[14], b15 = b[15]
      t[0] = a0 * b0
      t[1] = a0 * b1 + a1 * b0
      t[2] = a0 * b2 + a1 * b1 + a2 * b0
      t[3] = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
      t[4] = a0 * b4 + a1 * b3 + a2 * b2 + a3 * b1 + a4 * b0
      t[5] = a0 * b5 + a1 * b4 + a2 * b3 + a3 * b2 + a4 * b1 + a5 * b0
      t[6] = a0 * b6 + a1 * b5 + a2 * b4 + a3 * b3 + a4 * b2 + a5 * b1 + a6 * b0
      t[7] = a0 * b7 + a1 * b6 + a2 * b5 + a3 * b4 + a4 * b3 + a5 * b2 + a6 * b1 + a7 * b0
      t[8] = a0 * b8 + a1 * b7 + a2 * b6 + a3 * b5 + a4 * b4 + a5 * b3 + a6 * b2 + a7 * b1 + a8 * b0
      t[9] = a0 * b9 + a1 * b8 + a2 * b7 + a3 * b6 + a4 * b5 + a5 * b4 + a6 * b3 + a7 * b2 + a8 * b1
        + a9 * b0
      t[10] = a0 * b10 + a1 * b9 + a2 * b8 + a3 * b7 + a4 * b6 + a5 * b5 + a6 * b4 + a7 * b3 + a8 * b2
        + a9 * b1 + a10 * b0
      t[11] = a0 * b11 + a1 * b10 + a2 * b9 + a3 * b8 + a4 * b7 + a5 * b6 + a6 * b5 + a7 * b4 + a8 * b3
        + a9 * b2 + a10 * b1 + a11 * b0
      t[12] = a0 * b12 + a1 * b11 + a2 * b10 + a3 * b9 + a4 * b8 + a5 * b7 + a6 * b6 + a7 * b5 + a8 * b4
        + a9 * b3 + a10 * b2 + a11 * b1 + a12 * b0
      t[13] = a0 * b13 + a1 * b12 + a2 * b11 + a3 * b10 + a4 * b9 + a5 * b8 + a6 * b7 + a7 * b6
        + a8 * b5 + a9 * b4 + a10 * b3 + a11 * b2 + a12 * b1 + a13 * b0
      t[14] = a0 * b14 + a1 * b13 + a2 * b12 + a3 * b11 + a4 * b10 + a5 * b9 + a6 * b8 + a7 * b7
        + a8 * b6 + a9 * b5 + a10 * b4 + a11 * b3 + a12 * b2 + a13 * b1 + a14 * b0
      t[15] = a0 * b15 + a1 * b14 + a2 * b13 + a3 * b12 + a4 * b11 + a5 * b10 + a6 * b9 + a7 * b8
        + a8 * b7 + a9 * b6 + a10 * b5 + a11 * b4 + a12 * b3 + a13 * b2 + a14 * b1 + a15 * b0
      t[16] = a1 * b15 + a2 * b14 + a3 * b13 + a4 * b12 + a5 * b11 + a6 * b10 + a7 * b9 + a8 * b8
        + a9 * b7 + a10 * b6 + a11 * b5 + a12 * b4 + a13 * b3 + a14 * b2 + a15 * b1
      t[17] = a2 * b15 + a3 * b14 + a4 * b13 + a5 * b12 + a6 * b11 + a7 * b10 + a8 * b9 + a9 * b8
        + a10 * b7 + a11 * b6 + a12 * b5 + a13 * b4 + a14 * b3 + a15 * b2
      t[18] = a3 * b15 + a4 * b14 + a5 * b13 + a6 * b12 + a7 * b11 + a8 * b10 + a9 * b9 + a10 * b8
        + a11 * b7 + a12 * b6 + a13 * b5 + a14 * b4 + a15 * b3
      t[19] = a4 * b15 + a5 * b14 + a6 * b13 + a7 * b12 + a8 * b11 + a9 * b10 + a10 * b9 + a11 * b8
        + a12 * b7 + a13 * b6 + a14 * b5 + a15 * b4
      t[20] = a5 * b15 + a6 * b14 + a7 * b13 + a8 * b12 + a9 * b11 + a10 * b10 + a11 * b9 + a12 * b8
        + a13 * b7 + a14 * b6 + a15 * b5
      t[21] = a6 * b15 + a7 * b14 + a8 * b13 + a9 * b12 + a10 * b11 + a11 * b10 + a12 * b9 + a13 * b8
        + a14 * b7 + a15 * b6
      t[22] = a7 * b15 + a8 * b14 + a9 * b13 + a10 * b12 + a11 * b11 + a12 * b10 + a13 * b9 + a14 * b8
        + a15 * b7
      t[23] = a8 * b15 + a9 * b14 + a10 * b13 + a11 * b12 + a12 * b11 + a13 * b10 + a14 * b9 + a15 * b8
      t[24] = a9 * b15 + a10 * b14 + a11 * b13 + a12 * b12 + a13 * b11 + a14 * b10 + a15 * b9
      t[25] = a10 * b15 + a11 * b14 + a12 * b13 + a13 * b12 + a14 * b11 + a15 * b10
      t[26] = a11 * b15 + a12 * b14 + a13 * b13 + a14 * b12 + a15 * b11
      t[27] = a12 * b15 + a13 * b14 + a14 * b13 + a15 * b12
      t[28] = a13 * b15 + a14 * b14 + a15 * b13
      t[29] = a14 * b15 + a15 * b14
      t[30] = a15 * b15
    }
    for (let i = 30; i >= 16; i--) {
      const high = t[i]
      t[i - 2] += high; t[i - 10] += high
      t[i - 12] -= high; t[i - 16] += high
    }
    let carry = 0
    do {
      t[14] += carry; t[6] += carry; t[4] -= carry; t[0] += carry
      carry = 0
      for (let i = 0; i < 16; i++) {
        const value = t[i] + carry
        carry = Math.floor(value / 65536)
        t[i] = value - carry * 65536
      }
    } while (carry)
    for (let i = 0; i < 16; i++) out[i] = t[i]
    if (cmp(out, plain.M) >= 0) subInto(out, out, plain.M)
  }
  return {M: plain.M, mulInto: mulInto, inv: plain.inv}
}

function makeEc(field) {
  const mulInto = field.mulInto, MODP = field.M
  const ONE = zeros()
  ONE[0] = 1
  const S = []
  for (let i = 0; i < 22; i++) S.push(zeros())

  function zeroTo(r) { for (let i = 0; i < 16; i++) r[i] = 0; return r }
  function copyTo(r, a) { for (let i = 0; i < 16; i++) r[i] = a[i]; return r }
  function addTo(r, a, b) {
    const carry = addInto(r, a, b)
    if (carry || cmp(r, MODP) >= 0) subInto(r, r, MODP)
    return r
  }
  function subTo(r, a, b) {
    const borrow = subInto(r, a, b)
    if (borrow) addInto(r, r, MODP)
    return r
  }
  function dblTo(r, a) { return addTo(r, a, a) }
  function tripleTo(r, a) {
    dblTo(S[15], a)
    return addTo(r, S[15], a)
  }


  // dbl-2001-b (a = -3)：8 次模乘，比 dbl-2007-bl 少 1 次。out 不得与 P 别名。
  function dblInto(out, P) {
    const X = P.X, Y = P.Y, Z = P.Z
    if (isZero(Z)) {
      zeroTo(out.X); zeroTo(out.Y); zeroTo(out.Z)
      return
    }
    const delta = S[0], gamma = S[1], beta = S[2], alpha = S[3]
    const tmp = S[4], tmp2 = S[5]
    mulInto(delta, Z, Z)
    mulInto(gamma, Y, Y)
    mulInto(beta, X, gamma)
    subTo(tmp, X, delta)
    addTo(tmp2, X, delta)
    mulInto(tmp, tmp, tmp2)
    tripleTo(alpha, tmp) // alpha = 3*(X-delta)*(X+delta)
    mulInto(out.X, alpha, alpha)
    dblTo(tmp, beta)
    dblTo(tmp2, tmp)
    dblTo(tmp, tmp2) // 8*beta
    subTo(out.X, out.X, tmp) // X3
    addTo(tmp, Y, Z)
    mulInto(out.Z, tmp, tmp)
    subTo(out.Z, out.Z, gamma)
    subTo(out.Z, out.Z, delta) // Z3
    dblTo(tmp, beta)
    dblTo(tmp2, tmp) // 4*beta
    subTo(tmp2, tmp2, out.X)
    mulInto(out.Y, alpha, tmp2)
    mulInto(tmp, gamma, gamma)
    dblTo(tmp2, tmp)
    dblTo(tmp, tmp2)
    dblTo(tmp2, tmp) // 8*gamma^2
    subTo(out.Y, out.Y, tmp2) // Y3
  }

  // madd-2007-bl: Jacobian P + affine Q。out 不得与 P 别名。
  function maddInto(out, P, Q) {
    const X1 = P.X, Y1 = P.Y, Z1 = P.Z
    if (isZero(Z1)) {
      copyTo(out.X, Q.x)
      copyTo(out.Y, Q.y)
      copyTo(out.Z, ONE)
      return
    }
    const Z1Z1 = S[0], U2 = S[1], S2 = S[2], H = S[3], HH = S[4]
    const I = S[5], J = S[6], r = S[7], V = S[8], HpZ1 = S[9]
    const tmp = S[10], tmp2 = S[11]
    mulInto(Z1Z1, Z1, Z1)
    mulInto(U2, Q.x, Z1Z1)
    mulInto(tmp, Q.y, Z1)
    mulInto(S2, tmp, Z1Z1)
    subTo(H, U2, X1)
    if (isZero(H)) {
      addTo(tmp, S2, Y1)
      if (isZero(tmp)) {
        zeroTo(out.X); zeroTo(out.Y); zeroTo(out.Z)
        return
      }
      dblInto(out, P)
      return
    }
    mulInto(HH, H, H)
    dblTo(tmp, HH)
    dblTo(I, tmp) // I = 4HH
    mulInto(J, H, I)
    subTo(tmp, S2, Y1)
    dblTo(r, tmp) // r = 2*(S2-Y1)
    mulInto(V, X1, I)
    mulInto(tmp, r, r)
    dblTo(tmp2, V)
    subTo(tmp, tmp, J)
    subTo(tmp, tmp, tmp2) // X3 = r^2 - J - 2V
    addTo(HpZ1, Z1, H)
    mulInto(out.Z, HpZ1, HpZ1)
    subTo(out.Z, out.Z, Z1Z1)
    subTo(out.Z, out.Z, HH) // Z3
    subTo(tmp2, V, tmp)
    mulInto(out.Y, r, tmp2) // r*(V-X3)
    mulInto(tmp2, Y1, J)
    dblTo(tmp2, tmp2)
    subTo(out.Y, out.Y, tmp2) // Y3
    copyTo(out.X, tmp)
  }

  // For T = (k + 2^256 - 1)/2 mod n, the 256 signed bits
  // (2*bit(T,i)-1) sum to k when weighted by 2^i.
  function makeMulG(t, table) {
    let row = 15, secondAdd = false
    const acc = {X: S[16], Y: S[17], Z: S[18]}
    const next = {X: S[19], Y: S[20], Z: S[21]}
    const negative = {x: null, y: zeros()}
    function point(block) {
      let mask = 0
      for (let j = 0; j < 8; j++) mask |= ((t[block * 8 + j] >>> row) & 1) << j
      const positive = (mask & 128) !== 0
      const q = table(128 * block + (positive ? mask & 127 : 127 - mask))
      if (positive) return q
      negative.x = q.x
      subInto(negative.y, MODP, q.y)
      return negative
    }
    return {
      step() {
        if (row === 15) {
          const first = point(0)
          copyTo(next.X, first.x); copyTo(next.Y, first.y); copyTo(next.Z, ONE)
          maddInto(acc, next, point(1))
        } else if (!secondAdd) {
          dblInto(next, acc)
          maddInto(acc, next, point(0))
          secondAdd = true
          return false
        } else {
          maddInto(next, acc, point(1))
          copyTo(acc.X, next.X); copyTo(acc.Y, next.Y); copyTo(acc.Z, next.Z)
          secondAdd = false
        }
        return --row < 0
      },
      result() { return acc }
    }
  }

  function affineX(point) {
    if (isZero(point.Z)) return null
    const x = field.inv(point.Z)
    mulInto(x, x, x)
    mulInto(x, point.X, x)
    return x
  }
  function affineXY(point) {
    if (isZero(point.Z)) return null
    const inv = field.inv(point.Z), inv2 = zeros(), x = zeros(), y = zeros()
    mulInto(inv2, inv, inv)
    mulInto(x, point.X, inv2)
    mulInto(y, point.Y, inv2)
    mulInto(y, y, inv)
    return {x: limbsToHex(x), y: limbsToHex(y)}
  }
  return {makeMulG: makeMulG, affineX: affineX, affineXY: affineXY}
}

function makeSm2(consts, points) {
  const ctxN = ModCtx(consts.N)
  const montN = MontCtx(consts.N, consts.montN.Rmod, consts.montN.R2, consts.montN.n0inv)
  const ec = makeEc(primeField(consts.P))

  // scalar-arithmetic muls mod n via Montgomery (~12x faster than shift-add)
  function mulN(a, b) {
    return montN.fromMont(montN.montMul(montN.toMont(a), montN.toMont(b)))
  }

  // Decode only the public points selected by this signature.
  const decoded = []
  function table(index) {
    if (decoded[index]) return decoded[index]
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const row = typeof points === 'function' ? points(index) : points[index]
    if (typeof row !== 'string' || row.length !== 88) throw Error('POINT_RESOURCE_MISSING')
    const x = zeros(), y = zeros()
    let bits = 0, carry = 0, count = 0
    for (let i = 0; count < 64; i++) {
      carry = (carry << 6) | alphabet.indexOf(row.charAt(i))
      bits += 6
      if (bits < 8) continue
      bits -= 8
      const byte = (carry >>> bits) & 255
      carry &= (1 << bits) - 1
      const coord = count < 32 ? x : y
      const limb = 15 - ((count & 31) >>> 1)
      coord[limb] |= byte << ((count & 1) ? 0 : 8)
      count++
    }
    decoded[index] = {x: x, y: y}
    return decoded[index]
  }

  const N = hexToLimbs(consts.N)
  const maskModN = hexToLimbs('000000010000000000000000000000008dfc2094de39fad4ac440bf6c62abedc')
  function signedCombScalar(k) {
    const t = ctxN.add(k, maskModN)
    let high = (t[0] & 1) ? addInto(t, t, N) : 0
    for (let i = 15; i >= 0; i--) {
      const limb = t[i]
      t[i] = (high << 15) | (limb >>> 1)
      high = limb & 1
    }
    return t
  }
  const ONE_N = zeros(); ONE_N[0] = 1
  const defaultUserId = '1234567812345678'

  function strBytes(s) {
    // ASCII only (user IDs, device codes in this protocol)
    const out = new Array(s.length)
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
    return out
  }

  function zaBytes(pubXHex, pubYHex, userId) {
    const idBytes = strBytes(userId)
    const bitLen = idBytes.length * 8
    return sm3Bytes([(bitLen >> 8) & 0xff, bitLen & 0xff].concat(idBytes,
      hexToBytes(consts.A), hexToBytes(consts.B), hexToBytes(consts.GX),
      hexToBytes(consts.GY), hexToBytes(pubXHex), hexToBytes(pubYHex)))
  }

  function digestForSignature(pubXHex, pubYHex, message, userId) {
    const za = zaBytes(pubXHex, pubYHex, userId || defaultUserId)
    return sm3Bytes(za.concat(message))
  }

  function subN(v) {
    const t = zeros()
    subInto(t, v, N)
    return t
  }

  function reduceModN(bytes32) {
    let v = hexToLimbs(bytesToHex(bytes32))
    if (cmp(v, N) >= 0) v = subN(v) // one subtract: value < 2^256 < 2n
    return v
  }

  // Deterministic k: SM3(d || e || message || counter), reject outside [1, n-1].
  function deriveK(dBytes, eBytes, message, counter) {
    const h = sm3Bytes(dBytes.concat(eBytes, message, [counter & 0xff]))
    const k = hexToLimbs(bytesToHex(h))
    if (isZero(k) || cmp(k, N) >= 0) return null
    return k
  }

  // r = (e + x1) mod n; s = (k - r*d) * (1+d)^-1 mod n. sync, cheap.
  function finish(eLimbs, kLimbs, dLimbs, x1Limbs, dInv) {
    // x1 < p, may exceed n by at most one subtraction
    let x1 = x1Limbs
    if (cmp(x1, N) >= 0) x1 = subN(x1)
    const r = ctxN.add(eLimbs, x1)
    if (isZero(r)) return null
    const rd = mulN(r, dLimbs)
    if (isZero(ctxN.add(r, kLimbs))) return null // r + k == n
    const num = ctxN.sub(kLimbs, rd)
    const inv = dInv
    const s = mulN(num, inv)
    if (isZero(s)) return null
    return { r, s }
  }

  // (1+d)^-1 只与私钥有关：同一凭证的每次签名复用，省一次模逆。
  const invCache = {}
  function invFor(hexKey, dLimbs) {
    let v = invCache[hexKey]
    if (!v) {
      v = ctxN.inv(ctxN.add(dLimbs, ONE_N))
      invCache[hexKey] = v
    }
    return v
  }

  // Step machine: sign(message) with optional fixed k (tests).
  // drive: while (!job.step()) {} then job.result() -> uppercase 128-hex or null.
  function makeSignJob(opts) {
    decoded.length = 0
    const dLimbs = hexToLimbs(opts.privateKeyHex)
    const dInv = invFor(opts.privateKeyHex, dLimbs)
    const message = opts.message
    const userId = opts.userId || defaultUserId
    const eLimbs = reduceModN(digestForSignature(
      opts.publicKeyXHex, opts.publicKeyYHex, message, userId))
    const dBytes = hexToBytes(opts.privateKeyHex)
    const eBytes = hexToBytes(limbsToHex(eLimbs))
    let counter = 0
    let kLimbs = opts.kLimbs || null
    let inner = null
    let done = false
    let result = null

    function restart() {
      if (kLimbs === null) {
        let k = null
        while (k === null && counter < 256) {
          k = deriveK(dBytes, eBytes, message, counter)
          counter++
        }
        if (k === null) { done = true; return }
        kLimbs = k
      }
      inner = ec.makeMulG(signedCombScalar(kLimbs), table)
    }

    return {

      step() {
        if (done) return true
        if (inner === null) restart()
        if (done) return true
        const finished = inner.step()
        if (!finished) return false
        const pt = inner.result()
        const x = ec.affineX(pt)
        const sig = x === null ? null : finish(eLimbs, kLimbs, dLimbs, x, dInv)
        if (sig !== null) {
          result = (limbsToHex(sig.r) + limbsToHex(sig.s)).toUpperCase()
          done = true
        } else {
          // retry with fresh k (fixed-k mode must not retry)
          if (opts.kLimbs) { done = true; result = null } else { kLimbs = null; inner = null }
        }
        return done
      },
      result() { return result },
    }
  }

  function makePublicJob(privateHex) {
    const d = hexToLimbs(privateHex)
    if (isZero(d) || cmp(d, N) >= 0 || isZero(ctxN.add(d, ONE_N))) throw Error('INVALID_OFFLINE_KEY')
    const job = ec.makeMulG(signedCombScalar(d), table)
    return {step: job.step, result: function() { return ec.affineXY(job.result()) }}
  }
  return {makeSignJob: makeSignJob, makePublicJob: makePublicJob}
}

module.exports = { makeSigner: function(points) { return makeSm2(CONSTS, points) } }
