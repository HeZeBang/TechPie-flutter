const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const source = fs.readFileSync(__dirname + '/../entry/src/main/js/MainAbility/common/grant-vault.js', 'utf8')
  .replace(/^import .*;\n/gm, '').replace(/export function /g, 'function ');
function fixture() {
  let key, stored;
  const tags = new Proxy({}, {get: (_, name) => name});
  const sessions = new Map(); let id = 0;
  const huks = {HuksTag: tags, HuksKeyAlg: {HUKS_ALG_AES: 'AES'}, HuksKeyPadding: {HUKS_PADDING_NONE: 0}, HuksCipherMode: {HUKS_MODE_GCM: 'GCM'},
    HuksKeyPurpose: {HUKS_KEY_PURPOSE_ENCRYPT: 1, HUKS_KEY_PURPOSE_DECRYPT: 2},
    isKeyItemExist(alias, options, done) { done(key ? null : {code: 12000011}, !!key); },
    generateKeyItem(alias, options, done) { key = crypto.randomBytes(32); done(); },
    initSession(alias, options, done) {
      const p = Object.fromEntries(options.properties.map(p => [p.tag.replace('HUKS_TAG_', ''), p.value]));
      const cipher = p.PURPOSE === 1 ? crypto.createCipheriv('aes-256-gcm', key, p.NONCE) : crypto.createDecipheriv('aes-256-gcm', key, p.NONCE);
      cipher.setAAD(p.ASSOCIATED_DATA); if (p.AE_TAG) cipher.setAuthTag(p.AE_TAG);
      sessions.set(++id, {cipher, encrypt: p.PURPOSE === 1}); done(null, {handle: id});
    },
    updateSession(handle, options, done) { done(null, {outData: sessions.get(handle).cipher.update(options.inData)}); },
    finishSession(handle, options, done) {
      const s = sessions.get(handle); let final;
      try { final = s.cipher.final(); } catch (error) { done({code: 1}); return; }
      sessions.delete(handle); done(null, {outData: s.encrypt ? Buffer.concat([final, s.cipher.getAuthTag()]) : final});
    },
    abortSession(handle, options, done) { sessions.delete(handle); done(); },
  };
  const context = {huks, crypto: {createRandom: () => ({generateRandomSync: n => ({data: crypto.randomBytes(n)})})},
    writeJson(name, value, done) { stored = JSON.parse(JSON.stringify(value)); done(); },
    readJson(name, done) { done(null, stored); }};
  vm.createContext(context); vm.runInContext(source, context);
  return {context, stored: () => stored};
}
test('first-use vault creates a key, authenticates persisted credentials, and binds them to one owner', () => {
  const f = fixture(), c = f.context; let error, loaded;
  c.initializeVault(e => { error = e; }); assert.equal(error, null);
  c.saveCredential('owner-a', {privateKey: 'synthetic-fixture'}, e => { error = e; });
  assert.ok(error == null); assert.equal(JSON.stringify(f.stored()).includes('synthetic-fixture'), false);
  c.loadCredential('owner-a', (e, value) => { error = e; loaded = value; });
  assert.equal(error, null); assert.equal(loaded.privateKey, 'synthetic-fixture');
  c.loadCredential('owner-b', (e, value) => { loaded = value; }); assert.equal(loaded, null);
  f.stored().encrypted[0] ^= 1;
  c.loadCredential('owner-a', (e, value) => { error = e; loaded = value; });
  assert.equal(error, 'KEYSTORE_CIPHER_FAILED'); assert.equal(loaded, undefined);
  c.saveCredential(null, null, () => {}); assert.equal(f.stored(), null);
});
