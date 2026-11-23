import huks from '@ohos.security.huks';
import crypto from '@ohos.security.cryptoFramework';
import {readJson, writeJson} from './watch-files.js';

var alias = 'TechPieOfflineGrantV1';
function array(value) { return Array.prototype.slice.call(value || []); }
function encode(text) {
  var value = encodeURIComponent(text), result = [];
  for (var i = 0; i < value.length; i++) {
    if (value.charAt(i) === '%') { result.push(parseInt(value.substr(i + 1, 2), 16)); i += 2; }
    else result.push(value.charCodeAt(i));
  }
  return new Uint8Array(result);
}
function decode(value) {
  var text = '';
  for (var i = 0; i < value.length; i++) text += '%' + ('0' + value[i].toString(16)).slice(-2);
  return decodeURIComponent(text);
}
export function randomBytes(length) {
  return crypto.createRandom().generateRandomSync(length).data;
}
function param(name, value) { return {tag: huks.HuksTag['HUKS_TAG_' + name], value: value}; }
function properties(purpose) {
  return [param('ALGORITHM', huks.HuksKeyAlg.HUKS_ALG_AES), param('KEY_SIZE', 256),
    param('PURPOSE', purpose), param('BLOCK_MODE', huks.HuksCipherMode.HUKS_MODE_GCM),
    param('PADDING', huks.HuksKeyPadding.HUKS_PADDING_NONE)];
}
function crypt(encrypt, input, nonce, owner, done) {
  var purpose = encrypt ? huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT : huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT;
  var props = properties(purpose).concat([param('NONCE', new Uint8Array(nonce)), param('ASSOCIATED_DATA', encode(owner))]);
  if (!encrypt) props.push(param('AE_TAG', new Uint8Array(input.slice(-16))));
  var data = new Uint8Array(encrypt ? input : input.slice(0, -16));
  try {
    huks.initSession(alias, {properties: props}, function(error, session) {
      if (error) { console.info('TechPie HUKS init code=' + error.code); done('KEYSTORE_INIT_FAILED'); return; }
      function failed(error) {
        console.info('TechPie HUKS cipher code=' + error.code);
        huks.abortSession(session.handle, {properties: []}, function() {});
        done('KEYSTORE_CIPHER_FAILED');
      }
      huks.updateSession(session.handle, {properties: props, inData: data}, function(error, updated) {
        if (error) { failed(error); return; }
        huks.finishSession(session.handle, {properties: props, inData: new Uint8Array(0)}, function(error, finished) {
          if (error) { failed(error); return; }
          done(null, array(updated.outData).concat(array(finished.outData)));
        });
      });
    });
  } catch (error) { done('KEYSTORE_UNAVAILABLE'); }
}
export function initializeVault(done) {
  try {
    randomBytes(32);
    huks.isKeyItemExist(alias, {properties: []}, function(error, exists) {
      if (error && error.code !== 12000011 && error.code !== -13) { done('KEYSTORE_UNAVAILABLE'); return; }
      function probe() {
        var nonce = randomBytes(12);
        crypt(true, [84, 80], nonce, 'probe', function(error, encrypted) {
          if (error) { done(error); return; }
          crypt(false, encrypted, nonce, 'probe', function(error, plain) {
            done(error || (plain.length === 2 && plain[0] === 84 && plain[1] === 80 ? null : 'KEYSTORE_SELF_TEST_FAILED'));
          });
        });
      }
      if (exists) probe();
      else huks.generateKeyItem(alias, {properties: properties(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT)},
        function(error) { if (error) done('KEYSTORE_GENERATE_FAILED'); else probe(); });
    });
  } catch (error) { done('KEYSTORE_UNAVAILABLE'); }
}
export function saveCredential(owner, credential, done) {
  if (!credential) { writeJson('offline-grant-v1.json', null, done); return; }
  var nonce = array(randomBytes(12));
  crypt(true, encode(JSON.stringify(credential)), nonce, owner, function(error, encrypted) {
    if (error) { done(error); return; }
    writeJson('offline-grant-v1.json', {version: 1, owner: owner, nonce: nonce, encrypted: encrypted}, done);
  });
}
export function loadCredential(owner, done) {
  readJson('offline-grant-v1.json', function(error, stored) {
    if (error || !stored || stored.owner !== owner) { done(error, null); return; }
    if (stored.version !== 1 || !Array.isArray(stored.nonce) || stored.nonce.length !== 12 ||
        !Array.isArray(stored.encrypted) || stored.encrypted.length < 16 || stored.encrypted.length > 16384) {
      done('INVALID_OFFLINE_CACHE'); return;
    }
    crypt(false, stored.encrypted, stored.nonce, owner, function(error, plain) {
      if (error) { done(error); return; }
      var value;
      try { value = JSON.parse(decode(plain)); } catch (error) { done('INVALID_OFFLINE_CACHE'); return; }
      done(null, value);
    });
  });
}
