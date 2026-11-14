// Validate public companion identity before signing; never read signing secrets.
const fs = require('node:fs');
const path = require('node:path');

function fingerprint(value) {
  if (typeof value !== 'string' || !/^[a-fA-F0-9]{64}$/.test(value)) {
    throw new Error('Phone fingerprint must be a certificate SHA256 (64 hex characters).');
  }
  return value.toUpperCase();
}

function validateConfig(source, workflow, override) {
  const expected = fingerprint(workflow.match(/EXPECTED_CERT_SHA256:\s*([a-fA-F0-9]{64})/)?.[1]);
  const actual = fingerprint(source.match(/phoneFingerprint:\s*'([^']+)'/)?.[1]);
  if (!/phonePackage:\s*'club\.geekpie\.techpie'/.test(source) || actual !== expected) {
    throw new Error('Watch companion must match the Android release package and signing certificate.');
  }
  return { expected, selected: override === undefined ? expected : fingerprint(override) };
}

function prepareCompiled(directory, identity) {
  let replaced = 0;
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.name.endsWith('.js')) {
        const source = fs.readFileSync(file, 'utf8');
        if (source.includes(identity.selected)) { replaced++; continue; }
        if (!source.includes(identity.expected)) continue;
        fs.writeFileSync(file, source.split(identity.expected).join(identity.selected));
        replaced++;
      }
    }
  }
  visit(directory);
  if (!replaced) throw new Error('Cannot locate the companion fingerprint in compiled watch JavaScript.');
}

function main(args) {
  const root = path.resolve(__dirname, '../..');
  const source = fs.readFileSync(path.join(root, 'harmonyos_watch/entry/src/main/js/MainAbility/common/wear-config.js'), 'utf8');
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/android-release.yml'), 'utf8');
  const identity = validateConfig(source, workflow, process.env.HUAWEI_PHONE_FINGERPRINT);
  if (args.length) {
    if (args.length !== 2 || args[0] !== '--compiled-dir') throw new Error('Usage: --compiled-dir DIRECTORY');
    prepareCompiled(args[1], identity);
  }
  console.log('[techpie-lite] Companion signing configuration verified' +
    (identity.selected === identity.expected ? ' (Android release).' : ' (explicit local debug override).'));
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { fingerprint, validateConfig, prepareCompiled };
