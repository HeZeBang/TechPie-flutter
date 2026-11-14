const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { fingerprint, validateConfig, prepareCompiled } = require('./validate-signing-config.cjs');

const release = '1C8155EE7940F2BEF76816F24FCE3044A7A083ED2032BB9DCEF3DE7BE4284A98';
const debug = 'A13C448FF7A7E886027767B8C6687937BCD2B7C481645C6492F4341A721E4D9E';
const workflow = `EXPECTED_CERT_SHA256: ${release.toLowerCase()}`;
const config = `export default {phonePackage: 'club.geekpie.techpie', phoneFingerprint: '${release}'};`;

test('release source matches actual Android release workflow', () => {
  const root = path.resolve(__dirname, '../..');
  const source = fs.readFileSync(path.join(root, 'harmonyos_watch/entry/src/main/js/MainAbility/common/wear-config.js'), 'utf8');
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/android-release.yml'), 'utf8');
  assert.equal(validateConfig(source, workflow).selected, release);
});

test('rejects wrong package, stale release certificate and malformed overrides', () => {
  assert.throws(() => validateConfig(config.replace(release, debug), workflow));
  assert.throws(() => validateConfig(config.replace('club.geekpie.techpie', 'wrong.package'), workflow));
  for (const value of ['', 'secret', debug + '0', debug + '\n']) {
    assert.throws(() => validateConfig(config, workflow, value));
  }
  assert.equal(fingerprint(debug.toLowerCase()), debug);
});

test('explicit debug override rewrites only generated JavaScript', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'techpie-watch-signing-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const bundle = path.join(dir, 'index.js');
  fs.writeFileSync(bundle, `const fingerprint = '${release}';`);
  fs.writeFileSync(path.join(dir, 'note.txt'), release);
  prepareCompiled(dir, validateConfig(config, workflow, debug));
  assert.ok(fs.readFileSync(bundle, 'utf8').includes(debug));
  assert.equal(fs.readFileSync(path.join(dir, 'note.txt'), 'utf8'), release);
  assert.ok(config.includes(release));
  // A cached debug bundle must never silently ship as a release companion.
  assert.throws(() => prepareCompiled(dir, validateConfig(config, workflow)), /Cannot locate/);
});

test('debug override fails if compiled identity is missing', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'techpie-watch-signing-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'index.js'), 'var other = 1;');
  assert.throws(() => prepareCompiled(dir, validateConfig(config, workflow, debug)), /Cannot locate/);
});
