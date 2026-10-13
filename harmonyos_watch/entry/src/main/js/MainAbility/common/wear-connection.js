// Product protocol v1. No business capability is advertised until implemented.
// Byte framing works on Lite JS without browser-only TextEncoder/btoa globals.
var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function utf8(text) {
  var encoded = encodeURIComponent(text), bytes = [];
  for (var i = 0; i < encoded.length; i++) {
    if (encoded.charAt(i) === '%') {
      bytes.push(parseInt(encoded.substr(i + 1, 2), 16)); i += 2;
    } else { bytes.push(encoded.charCodeAt(i)); }
  }
  return bytes;
}
function text(bytes) {
  var encoded = '';
  for (var i = 0; i < bytes.length; i++) {
    encoded += '%' + ('0' + bytes[i].toString(16)).slice(-2);
  }
  return decodeURIComponent(encoded);
}
function base64(bytes) {
  var result = '';
  for (var i = 0; i < bytes.length; i += 3) {
    var a = bytes[i], b = bytes[i + 1] || 0, c = bytes[i + 2] || 0;
    result += alphabet.charAt(a >> 2) + alphabet.charAt(((a & 3) << 4) | (b >> 4)) +
      (i + 1 < bytes.length ? alphabet.charAt(((b & 15) << 2) | (c >> 6)) : '=') +
      (i + 2 < bytes.length ? alphabet.charAt(c & 63) : '=');
  }
  return result;
}
function unbase64(value) {
  if (typeof value !== 'string' || value.length % 4 !== 0) {
    throw new Error('INVALID_PAYLOAD');
  }
  var padding = 0;
  for (var k = 0; k < value.length; k++) {
    if (value.charAt(k) === '=') {
      padding++;
      if (k < value.length - 2 || padding > 2) throw new Error('INVALID_PAYLOAD');
    } else if (padding || alphabet.indexOf(value.charAt(k)) < 0) {
      throw new Error('INVALID_PAYLOAD');
    }
  }
  var bytes = [];
  for (var i = 0; i < value.length; i += 4) {
    var a = alphabet.indexOf(value.charAt(i)), b = alphabet.indexOf(value.charAt(i + 1));
    var c = alphabet.indexOf(value.charAt(i + 2)), d = alphabet.indexOf(value.charAt(i + 3));
    bytes.push((a << 2) | (b >> 4));
    if (c >= 0) bytes.push(((b & 15) << 4) | (c >> 2));
    if (d >= 0) bytes.push(((c & 3) << 6) | d);
  }
  if (base64(bytes) !== value) throw new Error('INVALID_PAYLOAD');
  return bytes;
}
function integer(value) { return typeof value === 'number' && isFinite(value) && Math.floor(value) === value; }
function token(value) {
  if (typeof value !== 'string' || !value.length || value.length > 32) return false;
  var allowed = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  for (var i = 0; i < value.length; i++) {
    if (allowed.indexOf(value.charAt(i)) < 0) return false;
  }
  return true;
}
function characters(value) {
  var count = 0;
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
      var next = value.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) i++;
    }
    count++;
  }
  return count;
}

export function WatchConnection(send, changed, now) {
  this.send = send;
  this.changed = changed;
  this.now = now || function() { return Date.now(); };
  this.counter = 0;
  this.reset();
}
WatchConnection.prototype.reset = function() {
  this.session = null; this.binding = null; this.nonce = null;
  this.assembly = null; this.replies = []; this.account = null;
  this.revision = 0; this.accountContent = null; this.ready = false;
  this.remaining = 0; this.silence = 0; this.lastTick = this.now();
  this.changed({ connected: false, name: '', studentId: '' });
};
WatchConnection.prototype.tick = function() {
  var delta = Math.max(1000, this.now() - this.lastTick);
  this.lastTick = this.now();
  if (this.assembly && this.now() - this.assembly.at >= 30000) this.assembly = null;
  if (!this.ready) return;
  this.remaining -= delta; this.silence += delta;
  this.phoneElapsed += delta;
  if (this.remaining <= 0 || this.silence >= 30000) this.reset();
};
WatchConnection.prototype.reply = function(request, type, body, handshake) {
  var response = {v: 1, id: 'w' + (++this.counter), replyTo: request.id,
    sessionId: handshake ? null : request.sessionId,
    bindingId: handshake ? null : request.bindingId,
    type: type, sentAtMs: this.now(), body: body};
  var bytes = utf8(JSON.stringify(response)), count = Math.ceil(bytes.length / 512), frames = [];
  for (var i = 0; i < count; i++) {
    frames.push(JSON.stringify({v: 1, mid: response.id, i: i, n: count,
      data: base64(bytes.slice(i * 512, (i + 1) * 512))}));
  }
  this.replies.push({id: request.id, content: JSON.stringify(request), frames: frames});
  if (this.replies.length > 16) this.replies.shift();
  for (var j = 0; j < frames.length; j++) this.send(frames[j]);
};
WatchConnection.prototype.receive = function(raw) {
  try {
    if (typeof raw !== 'string' || utf8(raw).length > 1024) throw new Error('INVALID_PAYLOAD');
    var f = JSON.parse(raw);
    if (f.v !== 1 || !token(f.mid) || !integer(f.i) || !integer(f.n) ||
        f.n < 1 || f.n > 64 || f.i < 0 || f.i >= f.n) throw new Error('INVALID_PAYLOAD');
    var part = unbase64(f.data);
    if (!part.length || part.length > 512 || (f.i < f.n - 1 && part.length !== 512)) throw new Error('INVALID_PAYLOAD');
    if (this.assembly && this.now() - this.assembly.at >= 30000) this.assembly = null;
    if (this.assembly && this.assembly.id !== f.mid) return;
    var a = this.assembly || {id: f.mid, n: f.n, parts: {}, at: this.now()};
    if (a.n !== f.n || (a.parts[f.i] && base64(a.parts[f.i]) !== f.data)) throw new Error('INVALID_PAYLOAD');
    a.parts[f.i] = part; a.at = this.now(); this.assembly = a;
    var bytes = [];
    for (var i = 0; i < a.n; i++) {
      if (!a.parts[i]) return;
      bytes = bytes.concat(a.parts[i]);
    }
    this.assembly = null;
    var message = JSON.parse(text(bytes));
    if (message.v !== 1 || message.id !== f.mid || typeof message.type !== 'string' ||
        !message.body || typeof message.body !== 'object' || !integer(message.sentAtMs)) throw new Error('INVALID_PAYLOAD');
    this.handle(message);
  } catch (_) { this.assembly = null; }
};
WatchConnection.prototype.handle = function(m) {
  var b = m.body, handshake = m.type === 'session.hello' || m.type === 'session.open';
  if (handshake && (m.sessionId != null || m.bindingId != null)) return;
  if (!handshake && (!this.ready || m.sessionId !== this.session || m.bindingId !== this.binding)) return;
  for (var i = 0; i < this.replies.length; i++) {
    var cached = this.replies[i];
    if (cached.id === m.id) {
      if (cached.content === JSON.stringify(m)) {
        for (var j = 0; j < cached.frames.length; j++) this.send(cached.frames[j]);
      }
      return;
    }
  }
  if (m.type === 'session.hello') {
    if (!token(b.nonce) || !Array.isArray(b.versions) || b.versions.indexOf(1) < 0) return;
    this.reset(); this.nonce = b.nonce; this.helloAt = this.now();
    this.reply(m, 'session.welcome', {nonce: b.nonce, version: 1,
      watchInstanceId: 'techpie-lite', capabilities: ['account.display', 'connection.heartbeat'],
      maxQrPayloadBytes: 0}, true);
  } else if (m.type === 'session.open') {
    if (b.nonce !== this.nonce || this.now() - this.helloAt > 5000 ||
        !token(b.sessionId) || !token(b.bindingId) || !integer(b.phoneTimeMs) ||
        !integer(b.leaseUntilMs) || b.leaseUntilMs <= b.phoneTimeMs) return;
    this.session = b.sessionId; this.binding = b.bindingId;
    this.phoneTime = b.phoneTimeMs; this.phoneElapsed = 0;
    this.remaining = Math.min(86400000, b.leaseUntilMs - b.phoneTimeMs);
    this.ready = true; this.silence = 0; this.lastTick = this.now();
    this.reply(m, 'session.opened', {sessionId: this.session}, true);
    this.changed({connected: true, name: '', studentId: ''});
  } else if (m.type === 'session.ping') {
    this.silence = 0;
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
  } else if (m.type === 'session.close' || m.type === 'session.clear') {
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
    this.reset();
  } else if (m.type === 'account.snapshot') {
    var d = b.data;
    if (!integer(b.revision) || b.revision < 1 || !integer(b.validUntilMs) ||
        b.validUntilMs <= this.phoneTime + this.phoneElapsed || !d ||
        typeof d.name !== 'string' || typeof d.studentId !== 'string' ||
        !d.name.trim() || !d.studentId.trim() || characters(d.name) > 64 || characters(d.studentId) > 64) {
      this.reply(m, 'result', {status: 'error', code: 'INVALID_PAYLOAD', retryable: false}); return;
    }
    var content = JSON.stringify(d);
    if (b.revision < this.revision || (b.revision === this.revision && this.accountContent !== content)) {
      this.reply(m, 'result', {status: 'error', code: 'STALE_REVISION', retryable: false}); return;
    }
    this.revision = b.revision; this.accountContent = content;
    this.account = {name: d.name, studentId: d.studentId}; this.silence = 0;
    this.changed({connected: true, name: d.name, studentId: d.studentId});
    this.reply(m, 'result', {status: 'ok', code: 'OK', resource: 'account', revision: b.revision});
  } else {
    this.reply(m, 'result', {status: 'error', code: 'UNSUPPORTED_OPERATION', retryable: false});
  }
};
