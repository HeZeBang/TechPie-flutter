// Product protocol v1, with optional binary-preserving QR matrix display.
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
  this.ddl = []; this.ddlRevision = 0; this.ddlContent = null;
  this.ddlUntil = 0; this.accountUntil = 0; this.code = null;
  this.pending = {}; this.error = ''; this.truncated = false;
  this.updatedAt = 0; this.phoneTime = 0; this.phoneElapsed = 0; this.publish();
};
WatchConnection.prototype.phoneNow = function() {
  return this.phoneTime + this.phoneElapsed + Math.max(0, this.now() - this.lastTick);
};
WatchConnection.prototype.publish = function() {
  if (this.code && this.code.until <= this.phoneNow()) this.code = null;
  this.changed({connected: this.ready, name: this.account ? this.account.name : '',
    studentId: this.account ? this.account.studentId : '', ddl: this.ddl,
    ddlReady: this.ddlUntil > this.phoneNow(), truncated: this.truncated,
    updatedAt: this.updatedAt, code: this.code,
    codeSeconds: this.code ? Math.max(0, Math.ceil((this.code.until - this.phoneNow()) / 1000)) : 0,
    syncing: !!this.pending.sync, codeLoading: !!this.pending.code, error: this.error});
};
WatchConnection.prototype.tick = function() {
  var delta = Math.max(0, this.now() - this.lastTick);
  this.lastTick = this.now();
  if (this.assembly && this.now() - this.assembly.at >= 30000) this.assembly = null;
  if (!this.ready) return;
  this.remaining -= delta; this.silence += delta;
  this.phoneElapsed += delta;
  if (this.remaining <= 0 || this.silence >= 30000) { this.reset(); return; }
  if (this.code && this.code.until <= this.phoneNow()) this.code = null;
  if (this.accountUntil <= this.phoneNow()) this.account = null;
  if (this.ddlUntil <= this.phoneNow()) this.ddl = [];
  for (var key in this.pending) {
    if (this.now() - this.pending[key].at >= 30000) {
      delete this.pending[key]; this.error = '唔…手机怎么没有响应呢(⊙ω⊙?)';
    }
  }
  this.publish();
};
WatchConnection.prototype.write = function(response) {
  var bytes = utf8(JSON.stringify(response)), count = Math.ceil(bytes.length / 512), frames = [];
  for (var i = 0; i < count; i++) {
    frames.push(JSON.stringify({v: 1, mid: response.id, i: i, n: count,
      data: base64(bytes.slice(i * 512, (i + 1) * 512))}));
  }
  for (var j = 0; j < frames.length; j++) this.send(frames[j]);
  return frames;
};
WatchConnection.prototype.request = function(kind) {
  if (!this.ready) { this.error = '请先连接手机 TechPie'; this.publish(); return false; }
  if (this.pending[kind]) return false;
  var id = 'w' + (++this.counter);
  this.pending[kind] = {id: id, at: this.now()}; this.error = '';
  // Keep the previous valid code until replacement succeeds or it expires.
  this.publish();
  this.write({v: 1, id: id, replyTo: null, sessionId: this.session,
    bindingId: this.binding, type: kind === 'code' ? 'campusCode.request' : 'sync.request',
    sentAtMs: this.now(), body: kind === 'code' ? {purpose: 'campus', format: 'qrBytes'} : {resources: ['account', 'ddl']}});
  return true;
};
WatchConnection.prototype.hideCode = function() {
  this.code = null; delete this.pending.code; this.publish();
};
WatchConnection.prototype.reply = function(request, type, body, handshake) {
  var response = {v: 1, id: 'w' + (++this.counter), replyTo: request.id,
    sessionId: handshake ? null : request.sessionId,
    bindingId: handshake ? null : request.bindingId,
    type: type, sentAtMs: this.now(), body: body};
  var frames = this.write(response);
  this.replies.push({id: request.id, content: JSON.stringify(request), frames: frames});
  if (this.replies.length > 16) this.replies.shift();
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
  // The opening message's transit time can differ from a later snapshot's.
  // Advance to the trusted peer's send time, but never move the clock backwards.
  if (!handshake && integer(m.sentAtMs)) {
    var correction = Math.max(0, m.sentAtMs - this.phoneNow());
    this.phoneTime += correction; this.remaining -= correction;
  }
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
      watchInstanceId: 'techpie-lite', capabilities: ['account.display', 'ddl.display', 'campusCode.qrMatrix', 'connection.heartbeat'],
      maxQrPayloadBytes: 1024}, true);
  } else if (m.type === 'session.open') {
    if (b.nonce !== this.nonce || this.now() - this.helloAt > 5000 ||
        !token(b.sessionId) || !token(b.bindingId) || !integer(b.phoneTimeMs) ||
        !integer(b.leaseUntilMs) || b.leaseUntilMs <= b.phoneTimeMs) return;
    this.session = b.sessionId; this.binding = b.bindingId;
    this.phoneTime = b.phoneTimeMs; this.phoneElapsed = 0;
    this.remaining = Math.min(86400000, b.leaseUntilMs - b.phoneTimeMs);
    this.ready = true; this.silence = 0; this.lastTick = this.now();
    this.reply(m, 'session.opened', {sessionId: this.session}, true);
    this.publish();
  } else if (m.type === 'session.ping') {
    this.silence = 0;
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
  } else if (m.type === 'session.close' || m.type === 'session.clear') {
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
    this.reset();
  } else if (m.type === 'account.snapshot') {
    var d = b.data;
    if (!integer(b.revision) || b.revision < 1 || !integer(b.validUntilMs) ||
        b.validUntilMs <= this.phoneNow() || !d ||
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
    this.accountUntil = b.validUntilMs; this.publish();
    this.reply(m, 'result', {status: 'ok', code: 'OK', resource: 'account', revision: b.revision});
  } else if (m.type === 'ddl.snapshot') {
    if (!integer(b.revision) || b.revision < 1 || !integer(b.validUntilMs) ||
        b.validUntilMs <= this.phoneNow() || !Array.isArray(b.items) || b.items.length > 50) {
      this.reject(m, 'INVALID_PAYLOAD'); return;
    }
    var ids = {}, items = [];
    for (var k = 0; k < b.items.length; k++) {
      var item = b.items[k];
      if (!item || typeof item.id !== 'string' || !item.id.length || item.id.length > 128 || ids[item.id] ||
          typeof item.title !== 'string' || !item.title.trim() || characters(item.title) > 80 ||
          typeof item.courseName !== 'string' || characters(item.courseName) > 40 ||
          !integer(item.dueAtMs) || item.dueAtMs < 1 ||
          ['open', 'completed'].indexOf(item.status) < 0) {
        this.reject(m, 'INVALID_PAYLOAD'); return;
      }
      ids[item.id] = true; items.push(item);
    }
    var ddlContent = JSON.stringify(b.items);
    if (b.revision < this.ddlRevision || (b.revision === this.ddlRevision && this.ddlContent !== ddlContent)) {
      this.reject(m, 'STALE_REVISION'); return;
    }
    items.sort(function(a, c) { return a.dueAtMs - c.dueAtMs; });
    this.ddl = items; this.ddlContent = ddlContent; this.ddlRevision = b.revision;
    this.ddlUntil = b.validUntilMs; this.truncated = b.truncated === true;
    this.updatedAt = integer(b.generatedAtMs) ? b.generatedAtMs : this.phoneNow();
    delete this.pending.sync; this.error = ''; this.silence = 0; this.publish();
    this.reply(m, 'result', {status: 'ok', code: 'OK', resource: 'ddl', revision: b.revision});
  } else if (m.type === 'campusCode.snapshot') {
    var pending = this.pending.code;
    if (!pending || pending.id !== m.replyTo || !token(b.codeId) || b.purpose !== 'campus' || b.format !== 'qrBytes' ||
        b.matrixEncoding !== 'base64-msb' || !integer(b.matrixSize) ||
        b.matrixSize < 21 || b.matrixSize > 121 || (b.matrixSize - 17) % 4 !== 0 ||
        !integer(b.validFromMs) || b.validFromMs > this.phoneNow() ||
        !integer(b.validUntilMs) || b.validUntilMs <= this.phoneNow() ||
        b.validUntilMs - this.phoneNow() > 120000) {
      this.reject(m, 'INVALID_PAYLOAD'); return;
    }
    var matrix;
    try { matrix = unbase64(b.matrix); } catch (_) { this.reject(m, 'INVALID_PAYLOAD'); return; }
    if (matrix.length !== Math.ceil(b.matrixSize * b.matrixSize / 8)) {
      this.reject(m, 'INVALID_PAYLOAD'); return;
    }
    this.code = {id: b.codeId, size: b.matrixSize, bytes: matrix, requestAt: pending.at,
      until: Math.min(b.validUntilMs, this.phoneNow() + this.remaining)};
    delete this.pending.code; this.error = ''; this.silence = 0; this.publish();
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
  } else if (m.type === 'result') {
    for (var kind in this.pending) {
      if (this.pending[kind].id === m.replyTo && b.status === 'error') {
        delete this.pending[kind]; this.error = failureText(b.code); this.publish();
      }
    }
  } else {
    this.reply(m, 'result', {status: 'error', code: 'UNSUPPORTED_OPERATION', retryable: false});
  }
};
WatchConnection.prototype.reject = function(m, code) {
  this.reply(m, 'result', {status: 'error', code: code, retryable: false});
};
function failureText(code) {
  if (code === 'ACCOUNT_NOT_READY') return '你还没在手机端绑定校园卡哦~';
  if (code === 'RATE_LIMITED') return '唔诶~!你点的太快了┭┮﹏┭┮';
  if (code === 'PAYLOAD_TOO_LARGE') return '你の校园码太大了……我展示不了呢，问问开发者吧';
  if (code === 'CODE_EXPIRED') return '校园码过期了呢，重新获取吧！';
  return '更新失败了呢，检查一下手机后重试吧！';
}
