import sm2 from './vendor/sm2.js';
import integers from './vendor/jsbn.js';

export function startOfflineCode(grant, prepared, random, now) {
  var key, k, multiply;
  integers.setRandomSource(random);
  if (!prepared || prepared.grant !== grant) {
    if (typeof grant.privateKey !== 'string' || grant.privateKey.length !== 64) throw new Error('INVALID_OFFLINE_KEY');
    for (var i = 0; i < 64; i++) if ('0123456789abcdef'.indexOf(grant.privateKey.charAt(i).toLowerCase()) < 0) throw new Error('INVALID_OFFLINE_KEY');
    key = new integers.BigInteger(grant.privateKey, 16);
    if (key.signum() <= 0 || key.compareTo(sm2.maxKey) >= 0) throw new Error('INVALID_OFFLINE_KEY');
    prepared = null;
    multiply = sm2.startMultiply(key);
  }
  var job = {prepared: prepared, step: function() {
    var at = now(), seconds = Math.floor(at / 1000);
    if (at >= grant.expiresAt * 1000) throw new Error('OFFLINE_GRANT_EXPIRED');
    if (seconds < 0 || seconds > 4294967295) throw new Error('CLOCK_OUT_OF_RANGE');
    if (!multiply) { k = sm2.nonce(); multiply = sm2.startMultiply(k); }
    var point = multiply();
    if (!point) return null;
    multiply = null;
    if (!job.prepared) {
      job.prepared = sm2.prepare(key, point, grant.publicKey);
      job.prepared.grant = grant;
      job.prepared.prefix = [];
      for (var i = 0; i < grant.authorInfo.length; i += 2) job.prepared.prefix.push(parseInt(grant.authorInfo.substr(i, 2), 16));
      return null;
    }
    var stamp = [(seconds >>> 24) & 255, (seconds >>> 16) & 255, (seconds >>> 8) & 255, seconds & 255];
    stamp.push(grant.deviceChecksum ^ stamp[0] ^ stamp[1] ^ stamp[2] ^ stamp[3]);
    var message = job.prepared.prefix.concat(stamp);
    var signature = sm2.signature(message, job.prepared, k, point);
    if (!signature) return null;
    return {payload: message.concat(signature), until: Math.min(at + 30000, grant.expiresAt * 1000)};
  }};
  return job;
}
