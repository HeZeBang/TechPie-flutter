import sm2 from './vendor/sm2.js';
import integers from './vendor/jsbn.js';

function bytes(value) {
  var result = [];
  for (var i = 0; i < value.length; i += 2) result.push(parseInt(value.substr(i, 2), 16));
  return result;
}
export function prepareCredential(credential, random) {
  integers.setRandomSource(random);
  var key = credential.privateKey;
  if (typeof key !== 'string' || key.length !== 64) throw new Error('INVALID_OFFLINE_KEY');
  for (var i = 0; i < key.length; i++) if ('0123456789abcdef'.indexOf(key.charAt(i).toLowerCase()) < 0) throw new Error('INVALID_OFFLINE_KEY');
  var d = new integers.BigInteger(key, 16), max = new integers.BigInteger('FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54122', 16);
  if (d.signum() <= 0 || d.compareTo(max) >= 0) throw new Error('INVALID_OFFLINE_KEY');
  var publicKey = sm2.getPublicKeyFromPrivateKey(key);
  var compressed = (parseInt(publicKey.substr(-2), 16) % 2 ? '03' : '02') + publicKey.substr(2, 64);
  if (compressed.toLowerCase() !== credential.publicKey.toLowerCase()) throw new Error('OFFLINE_KEY_MISMATCH');
  return {grant: credential, publicKey: publicKey};
}
export function generateOfflineCode(prepared, now) {
  var grant = prepared.grant, seconds = Math.floor(now / 1000);
  if (now >= grant.expiresAt * 1000) throw new Error('OFFLINE_GRANT_EXPIRED');
  if (seconds < 0 || seconds > 4294967295) throw new Error('CLOCK_OUT_OF_RANGE');
  var stamp = [(seconds >>> 24) & 255, (seconds >>> 16) & 255, (seconds >>> 8) & 255, seconds & 255];
  stamp.push(grant.deviceChecksum ^ stamp[0] ^ stamp[1] ^ stamp[2] ^ stamp[3]);
  var message = bytes(grant.authorInfo).concat(stamp);
  var signature = sm2.doSignature(message, grant.privateKey, {hash: true, publicKey: prepared.publicKey});
  return {payload: message.concat(bytes(signature)), until: Math.min(now + 30000, grant.expiresAt * 1000)};
}
