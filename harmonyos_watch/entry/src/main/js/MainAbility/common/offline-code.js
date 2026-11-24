import {makeSigner} from './sm2.js';

function hexBytes(hex) {
  var out = [];
  for (var i = 0; i < hex.length; i += 2) out.push(parseInt(hex.substr(i, 2), 16));
  return out;
}

export function startOfflineCode(grant, prepared, random, now, table) {
  var key = grant.privateKey;
  if (!prepared || prepared.grant !== grant) {
    if (typeof key !== 'string' || key.length !== 64) throw Error('INVALID_OFFLINE_KEY');
    var signer = makeSigner(table);
    prepared = {grant: grant, signer: signer, publicJob: signer.makePublicJob(key)};
  }
  var sign, message, until;
  return {prepared: prepared, step: function() {
    var at = now();
    if (at >= grant.expiresAt * 1000) throw Error('OFFLINE_GRANT_EXPIRED');
    if (prepared.publicJob) {
      if (!prepared.publicJob.step()) return null;
      var point = prepared.publicJob.result();
      var compressed = (parseInt(point.y.slice(-1), 16) % 2 ? '03' : '02') + point.x;
      if (compressed.toLowerCase() !== grant.publicKey.toLowerCase()) throw Error('OFFLINE_KEY_MISMATCH');
      prepared.point = point; prepared.publicJob = null;
      return null;
    }
    if (!sign) {
      var sec = Math.floor(at / 1000);
      if (sec < 0 || sec > 4294967295) throw Error('CLOCK_OUT_OF_RANGE');
      var stamp = [sec >>> 24, (sec >>> 16) & 255, (sec >>> 8) & 255, sec & 255];
      stamp.push(grant.deviceChecksum ^ stamp[0] ^ stamp[1] ^ stamp[2] ^ stamp[3]);
      message = hexBytes(grant.authorInfo).concat(stamp);
      until = Math.min(at + 30000, grant.expiresAt * 1000);
      // Sample each presentation nonce from the watch's native CSPRNG.
      var bytes = random(32), limbs = [], hex = '';
      if (!bytes || bytes.length !== 32) throw Error('NO_NATIVE_ENTROPY');
      for (var i = 0; i < 32; i += 2) {
        var limb = bytes[i] * 256 + bytes[i + 1];
        hex += ('000' + limb.toString(16)).slice(-4);
        limbs[15 - i / 2] = limb;
      }
      if (hex === '0000000000000000000000000000000000000000000000000000000000000000' ||
          hex >= 'fffffffeffffffffffffffffffffffff7203df6b21c6052b53bbf40939d54123') return null;
      sign = prepared.signer.makeSignJob({privateKeyHex: key, publicKeyXHex: prepared.point.x,
        publicKeyYHex: prepared.point.y, message: message, kLimbs: limbs});
    }
    if (!sign.step()) return null;
    var signature = sign.result();
    if (!signature) { sign = null; return null; }
    if (at >= until) throw Error('OFFLINE_CODE_EXPIRED');
    return {payload: message.concat(hexBytes(signature)), until: until};
  }};
}
