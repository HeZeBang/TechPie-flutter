const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const pageRoot = path.join(__dirname, '../benchmark/index');
const common = path.join(__dirname, '../entry/src/main/js/MainAbility/common');
const points = require(path.join(common, 'sm2-points.json'));
const {opts, expected} = require(path.join(pageRoot, 'signature-fixture'));

test('the Lite port produces the independently verified public fixture signature', () => {
  const {makeSigner} = require(path.join(common, 'sm2'));
  const job = makeSigner(points).makeSignJob(opts);
  let steps = 1;
  while (!job.step()) assert.ok(++steps <= 32);
  assert.equal(job.result(), expected);
});

test('hiding the benchmark cancels queued work and returning requires a new tap', () => {
  const src = fs.readFileSync(path.join(pageRoot, 'index.js'), 'utf8')
    .replace(/^import .*;\n/gm, '').replace('export default', 'var page =');
  const callbacks = [];
  const env = {setTimeout: fn => callbacks.push(fn), clearTimeout() {},
    require() { assert.fail('a hidden benchmark loaded a module'); }};
  vm.createContext(env);
  vm.runInContext(src, env);
  const p = Object.assign(env.page, env.page.data);
  p.onShow();
  assert.equal(callbacks.length, 0);
  p.sign(); p.onHide(); p.onShow();
  callbacks.shift()();
  assert.equal(p.busy, false);
  assert.equal(callbacks.length, 0);
});

test('signed comb and sparse-prime reduction match OpenSSL points for edge and varied nonces', () => {
  const {createECDH, createHash} = require('node:crypto');
  const {makeSigner} = require(path.join(common, 'sm2'));
  const n = BigInt('0xfffffffeffffffffffffffffffffffff7203df6b21c6052b53bbf40939d54123');
  const p = BigInt('0xfffffffeffffffffffffffffffffffffffffffff00000000ffffffffffffffff');
  const hex = value => value.toString(16).padStart(64, '0');
  const hash = data => createHash('sm3').update(data).digest();
  const ec = createECDH('SM2');
  const point = scalar => {
    ec.setPrivateKey(Buffer.from(hex(scalar),'hex'));
    return ec.getPublicKey().subarray(1);
  };
  const id = Buffer.from('1234567812345678');
  const curveB = '28e9fa9e9d9f5e344d5a9e4bcf6509a7f39789f515ab8f92ddbcbd414d940e93';
  const curve = Buffer.concat([Buffer.from(hex(p-3n)+curveB,'hex'), point(1n)]);
  const nonces = [1n, 2n, n-1n, n-2n, 1n<<127n, 1n<<255n, n-((1n<<256n)-1n-n)];
  for (let i=0;i<32;i++) nonces.push(BigInt('0x'+hash('public scalar '+i).toString('hex'))%(n-1n)+1n);
  for (const [i,k] of nonces.entries()) {
    const d = BigInt('0x'+hash('public test key '+i).toString('hex'))%(n-2n)+1n;
    const pub = point(d), message = Buffer.from('test case '+i);
    const za = hash(Buffer.concat([Buffer.from([0,id.length*8]),id,curve,pub]));
    const e = BigInt('0x'+hash(Buffer.concat([za,message])).toString('hex'));
    const x = BigInt('0x'+point(k).subarray(0,32).toString('hex'));
    const kLimbs = Array.from({length:16},(_,j)=>Number((k>>BigInt(16*j))&65535n));
    const job = makeSigner(points).makeSignJob({privateKeyHex:hex(d),
      publicKeyXHex:pub.subarray(0,32).toString('hex'), publicKeyYHex:pub.subarray(32).toString('hex'),
      message:[...message], kLimbs});
    let rounds = 1;
    while (!job.step()) assert.ok(++rounds <= 16);
    assert.equal(rounds,16);
    const sig = job.result();
    const r = BigInt('0x'+sig.slice(0,64)), s = BigInt('0x'+sig.slice(64));
    assert.equal(r,(x+e)%n);
    assert.equal((s*(1n+d)+r*d)%n,k);
  }
});

test('folding the SM2 prime matches exact products, including in-place squares', () => {
  const native = require('node:crypto');
  const p = BigInt('0xfffffffeffffffffffffffffffffffffffffffff00000000ffffffffffffffff');
  const context = vm.createContext({module: {exports: {}}});
  const code = fs.readFileSync(path.join(common, 'sm2.js'), 'utf8');
  vm.runInContext(code, context);
  const field = context.primeField(p.toString(16));
  const limbs = n => Array.from({length:16}, (_, i) => Number(n >> BigInt(i*16) & 65535n));
  const fromLimbs = a => a.reduceRight((acc, v) => (acc<<16n)+BigInt(v),0n);
  const values = [0n,1n,p-1n,p-2n,(1n<<224n)-1n,1n<<128n];
  for (let i=0; i<24; i++) {
    const hash = native.createHash('sha256').update('field fixture '+i).digest('hex');
    values.push(BigInt('0x'+hash)%p);
  }
  // Isolate every product column and every off-diagonal square term.
  const basis = Array.from({length: 16}, (_, i) => 1n << BigInt(16 * i));
  for (const x of basis) {
    for (const y of basis) {
      const left = limbs(x);
      field.mulInto(left, left, limbs(y));
      assert.equal(fromLimbs(left), x * y % p);
      const pair = limbs(x + y);
      field.mulInto(pair, pair, pair);
      assert.equal(fromLimbs(pair), (x + y) ** 2n % p);
    }
  }
  for (const x of values) {
    const square = limbs(x);
    field.mulInto(square,square,square);
    assert.equal(fromLimbs(square),x*x%p);
    for (const y of values) {
      const product = limbs(y);
      field.mulInto(product,limbs(x),product);
      assert.equal(fromLimbs(product),x*y%p);
    }
  }
});

test('a later slice reports the original exception and permits a fresh attempt', () => {
  const src = fs.readFileSync(path.join(pageRoot, 'index.js'), 'utf8')
    .replace(/^import .*;\n/gm, '').replace('export default', 'var page =');
  const pending = [], env = {setTimeout: f => pending.push(f), clearTimeout() {},
    console: {info() {}, error() {}}, require: name => {
      if (name.includes('fixture')) return {expected:'signature', opts:{}};
      return {makeSigner: () => ({makeSignJob() {
        let calls = 0;
        return {step() { if (++calls === 9) throw new ReferenceError('fixture error'); return false; }};
      }})};
    }};
  vm.createContext(env); vm.runInContext(src, env);
  const page = Object.assign(env.page, env.page.data);
  page.onShow(); page.sign();
  for (let limit=0; pending.length && limit<12; limit++) pending.shift()();
  assert.match(page.status,/计算失败/);
  assert.match(page.timing,/ReferenceError: fixture error/);
  assert.equal(page.busy,false);
  page.sign(); assert.equal(pending.length,1);
});
