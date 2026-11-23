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
function hexString(value) {
  if (typeof value !== 'string' || !value.length || value.length % 2) return false;
  var allowed = '0123456789abcdef';
  for (var i = 0; i < value.length; i++) if (allowed.indexOf(value.charAt(i).toLowerCase()) < 0) return false;
  return true;
}
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

export function WatchConnection(send, changed, now, options) {
  this.send = send;
  this.changed = changed;
  this.now = now || function() { return Date.now(); };
  this.counter = 0;
  this.onCache = options && options.onCache;
  this.onAuthorization = options && options.onAuthorization;
  this.offlineEnabled = options && options.offlineEnabled;
  this.offlineStatus = options && options.offlineStatus;
  this.reset();
  if (options && options.cache) this.restore(options.cache);
}
// Transport shutdown preserves the owner's last synchronized data.
WatchConnection.prototype.reset = function(clearCache) {
  var current = this.lastTick ? this.phoneNow() : this.now();
  this.session = null; this.binding = null; this.nonce = null;
  this.assembly = null; this.replies = []; this.ready = false;
  this.remaining = 0; this.silence = 0;
  this.pending = {}; this.error = ''; this.code = null; this.alert = null;
  this.phoneTime = current; this.phoneElapsed = 0; this.lastTick = this.now();
  this.reminderCursor = current; this.resources = ['account', 'ddl'];
  if (clearCache !== false) {
    this.cacheBinding = null; this.account = null;
    this.revision = 0; this.accountContent = null; this.accountUntil = 0;
    this.ddl = []; this.ddlRevision = 0; this.ddlContent = null; this.ddlUntil = 0;
    this.schedule = []; this.scheduleRevision = 0; this.scheduleContent = null; this.scheduleUntil = 0;
    this.scheduleTruncated = false; this.truncated = false;
    this.remindersEnabled = false; this.updatedAt = 0;
  }
  this.publish();
};
WatchConnection.prototype.exportCache = function() {
  return {version: 1, owner: this.cacheBinding, account: this.account,
    ddl: this.ddl, schedule: this.schedule, revision: this.revision,
    ddlRevision: this.ddlRevision, scheduleRevision: this.scheduleRevision,
    remindersEnabled: this.remindersEnabled, updatedAt: this.updatedAt,
    truncated: this.truncated, scheduleTruncated: this.scheduleTruncated,
    clockOffset: this.phoneNow() - this.now()};
};
WatchConnection.prototype.restore = function(cache) {
  if (!cache || cache.version !== 1 || !token(cache.owner) ||
      !Array.isArray(cache.ddl) || cache.ddl.length > 50 ||
      !Array.isArray(cache.schedule) || cache.schedule.length > 50 ||
      !integer(cache.revision) || !integer(cache.ddlRevision) || !integer(cache.scheduleRevision) ||
      !integer(cache.updatedAt) || typeof cache.clockOffset !== 'number' || !isFinite(cache.clockOffset)) return false;
  var account = cache.account;
  if (account && (typeof account.name !== 'string' || typeof account.studentId !== 'string' ||
      characters(account.name) > 64 || characters(account.studentId) > 64)) return false;
  if (!cache.ddl.every(function(item) {
    return item && typeof item.id === 'string' && typeof item.title === 'string' &&
      typeof item.courseName === 'string' && characters(item.title) <= 80 &&
      characters(item.courseName) <= 40 && integer(item.dueAtMs) &&
      ['open', 'completed'].indexOf(item.status) >= 0 && Array.isArray(item.remindAtMs || []);
  }) || !cache.schedule.every(function(item) {
    return item && typeof item.name === 'string' && typeof item.location === 'string' &&
      characters(item.name) <= 80 && characters(item.location) <= 40 &&
      integer(item.startAtMs) && integer(item.endAtMs) && item.endAtMs > item.startAtMs;
  })) return false;
  this.cacheBinding = cache.owner; this.account = account;
  this.revision = cache.revision; this.accountContent = account ? JSON.stringify(account) : null;
  this.ddl = cache.ddl; this.ddlRevision = cache.ddlRevision;
  this.remindersEnabled = cache.remindersEnabled === true;
  this.ddlContent = JSON.stringify({items: this.ddl, remindersEnabled: this.remindersEnabled});
  this.schedule = cache.schedule; this.scheduleRevision = cache.scheduleRevision;
  this.scheduleContent = JSON.stringify(this.schedule);
  this.updatedAt = cache.updatedAt; this.truncated = cache.truncated === true;
  this.scheduleTruncated = cache.scheduleTruncated === true;
  this.phoneTime = this.now() + cache.clockOffset; this.phoneElapsed = 0; this.lastTick = this.now();
  this.reminderCursor = this.phoneNow(); this.publish(); return true;
};
WatchConnection.prototype.commit = function(request, resource, revision) {
  var link = this, session = this.session;
  var finish = function(error) {
    if (session !== link.session) return;
    if (error) { link.error = '本地保存失败，请重新同步'; link.reject(request, 'STORAGE_FAILED'); link.publish(); }
    else link.reply(request, 'result', {status: 'ok', code: 'OK', resource: resource, revision: revision});
  };
  if (this.onCache) this.onCache(this.exportCache(), finish); else finish();
};
WatchConnection.prototype.phoneNow = function() {
  return this.phoneTime + this.phoneElapsed + Math.max(0, this.now() - this.lastTick);
};
WatchConnection.prototype.publish = function() {
  if (this.code && this.code.until <= this.phoneNow()) this.code = null;
  this.changed({connected: this.ready, name: this.account ? this.account.name : '',
    studentId: this.account ? this.account.studentId : '', ddl: this.ddl,
    ddlReady: this.ddlRevision > 0, truncated: this.truncated,
    updatedAt: this.updatedAt, cacheBinding: this.cacheBinding, code: this.code,
    schedule: this.schedule, scheduleReady: this.scheduleRevision > 0,
    scheduleTruncated: this.scheduleTruncated, alert: this.alert, remindersEnabled: this.remindersEnabled,
    codeSeconds: this.code ? Math.max(0, Math.ceil((this.code.until - this.phoneNow()) / 1000)) : 0,
    syncing: !!this.pending.sync, codeLoading: !!this.pending.code, error: this.error});
};
WatchConnection.prototype.tick = function() {
  var delta = Math.max(0, this.now() - this.lastTick);
  this.lastTick = this.now();
  if (this.assembly && this.now() - this.assembly.at >= 30000) this.assembly = null;
  this.phoneElapsed += delta;
  if (this.ready) {
    this.remaining -= delta; this.silence += delta;
    if (this.remaining <= 0 || this.silence >= 30000) this.reset(false);
  }
  if (this.code && this.code.until <= this.phoneNow()) this.code = null;
  if (this.remindersEnabled) {
    var current = this.phoneNow(), due = [];
    for (var i = 0; i < this.ddl.length; i++) {
      var item = this.ddl[i];
      if (item.status !== 'open' || item.dueAtMs <= current) continue;
      var times = item.remindAtMs || [];
      for (var j = 0; j < times.length; j++) {
        if (times[j] > this.reminderCursor && times[j] <= current && current - times[j] < 60000) { due.push(item); break; }
      }
    }
    this.reminderCursor = current;
    if (due.length) this.alert = {id: 'r' + current, title: due[0].title, count: due.length};
  }
  for (var key in this.pending) {
    if (this.now() - this.pending[key].at >= 30000) {
      delete this.pending[key]; this.error = '手机未响应，请检查连接后重试';
    }
  }
  this.publish();
};
WatchConnection.prototype.write = function(response, optional) {
  var bytes = utf8(JSON.stringify(response)), count = Math.ceil(bytes.length / 512), frames = [];
  for (var i = 0; i < count; i++) {
    frames.push(JSON.stringify({v: 1, mid: response.id, i: i, n: count,
      data: base64(bytes.slice(i * 512, (i + 1) * 512))}));
  }
  for (var j = 0; j < frames.length; j++) this.send(frames[j], optional);
  return frames;
};
WatchConnection.prototype.notifyReady = function() {
  this.write({v: 1, id: 'w' + (++this.counter), replyTo: null,
    sessionId: null, bindingId: null, type: 'peer.ready', sentAtMs: this.now(), body: {}}, true);
};
WatchConnection.prototype.request = function(kind) {
  if (!this.ready) { this.error = '请先连接手机 TechPie'; this.publish(); return false; }
  if (this.pending[kind]) return false;
  var id = 'w' + (++this.counter);
  this.pending[kind] = {id: id, at: this.now(), remaining: this.resources.slice()}; this.error = '';
  // Keep the previous valid code until replacement succeeds or it expires.
  this.publish();
  this.write({v: 1, id: id, replyTo: null, sessionId: this.session,
    bindingId: this.binding, type: kind === 'code' ? 'campusCode.request' : 'sync.request',
    sentAtMs: this.now(), body: kind === 'code' ? {purpose: 'campus', format: 'qrBytes'} : {resources: this.resources}});
  return true;
};
WatchConnection.prototype.applied = function(resource) {
  var pending = this.pending.sync;
  if (!pending) return;
  pending.remaining = pending.remaining.filter(function(value) { return value !== resource; });
  if (!pending.remaining.length) delete this.pending.sync;
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
    this.silence = 0;
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
    this.reset(false); this.nonce = b.nonce; this.helloAt = this.now();
    if (Array.isArray(b.capabilities) && b.capabilities.indexOf('schedule.display') >= 0) this.resources.push('schedule');
    this.offeredOffline = this.offlineEnabled && this.offlineEnabled();
    this.reply(m, 'session.welcome', {nonce: b.nonce, version: 1,
      watchInstanceId: 'techpie-lite', capabilities: ['account.display', 'ddl.display', 'schedule.display', 'reminder.watchLocal', 'campusCode.qrMatrix', 'connection.heartbeat'].concat(this.offeredOffline ? ['campusCode.offlineSm2'] : []),
      offlineStatus: this.offlineStatus && this.offlineStatus(), maxQrPayloadBytes: 1024}, true);
  } else if (m.type === 'session.open') {
    if (b.nonce !== this.nonce || this.now() - this.helloAt > 30000 ||
        !token(b.sessionId) || !token(b.bindingId) || !integer(b.phoneTimeMs) ||
        !integer(b.leaseUntilMs) || b.leaseUntilMs <= b.phoneTimeMs) return;
    if (this.cacheBinding && this.cacheBinding !== b.bindingId) this.reset(true);
    this.session = b.sessionId; this.binding = b.bindingId; this.cacheBinding = b.bindingId;
    this.phoneTime = b.phoneTimeMs; this.phoneElapsed = 0;
    this.remaining = Math.min(86400000, b.leaseUntilMs - b.phoneTimeMs);
    this.ready = true; this.silence = 0; this.lastTick = this.now();
    var opened = this, openingSession = this.session;
    var finishOpen = function(error) {
      if (opened.session !== openingSession) return;
      if (error) { opened.reject(m, 'STORAGE_FAILED'); opened.reset(false); return; }
      opened.reply(m, 'session.opened', {sessionId: opened.session}, true); opened.publish();
    };
    if (this.onCache) this.onCache(this.exportCache(), finishOpen); else finishOpen();
  } else if (m.type === 'session.ping') {
    this.silence = 0;
    this.reply(m, 'result', {status: 'ok', code: 'OK'});
  } else if (m.type === 'session.close') {
    this.reply(m, 'result', {status: 'ok', code: 'OK'}); this.reset(false);
  } else if (m.type === 'session.clear') {
    this.reset(true);
    var link = this;
    var cleared = function(error) { link.reply(m, 'result', {status: error ? 'error' : 'ok', code: error ? 'STORAGE_FAILED' : 'OK'}); };
    if (this.onCache) this.onCache(this.exportCache(), cleared); else cleared();
  } else if (m.type === 'campusCode.authorization') {
    if (!this.onAuthorization || !this.offlineEnabled || !this.offlineEnabled()) { this.reject(m, 'UNSUPPORTED_OPERATION'); return; }
    var grant = b.credential;
    if (grant !== null && (!grant || typeof grant.cardID !== 'string' || !grant.cardID.length || grant.cardID.length > 128 ||
        !hexString(grant.privateKey) || grant.privateKey.length !== 64 ||
        !hexString(grant.publicKey) || grant.publicKey.length !== 66 || ['02', '03'].indexOf(grant.publicKey.substr(0, 2)) < 0 ||
        !hexString(grant.authorInfo) || grant.authorInfo.length > 1024 ||
        !integer(grant.deviceChecksum) || grant.deviceChecksum < 0 || grant.deviceChecksum > 255 ||
        typeof grant.expiresAt !== 'number' || !isFinite(grant.expiresAt) || grant.expiresAt * 1000 <= this.phoneNow() ||
        grant.totalUses != null)) { this.reject(m, 'INVALID_PAYLOAD'); return; }
    var authorizing = this, authorizationSession = this.session;
    this.onAuthorization(this.binding, grant, function(error) {
      if (authorizing.session !== authorizationSession) return;
      if (error) authorizing.reject(m, error);
      else authorizing.reply(m, 'result', {status: 'ok', code: 'OK'});
      authorizing.publish();
    });
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
    this.accountUntil = b.validUntilMs; this.applied('account');
    this.updatedAt = integer(b.generatedAtMs) ? b.generatedAtMs : this.phoneNow(); this.publish();
    this.commit(m, 'account', b.revision);
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
          ['open', 'completed'].indexOf(item.status) < 0 ||
          (item.remindAtMs !== undefined && (!Array.isArray(item.remindAtMs) || item.remindAtMs.length > 3 ||
            item.remindAtMs.some(function(t) { return !integer(t) || t < 1 || t > item.dueAtMs; })))) {
        this.reject(m, 'INVALID_PAYLOAD'); return;
      }
      ids[item.id] = true; items.push(item);
    }
    var ddlContent = JSON.stringify({items: b.items, remindersEnabled: b.remindersEnabled === true});
    if (b.revision < this.ddlRevision || (b.revision === this.ddlRevision && this.ddlContent !== ddlContent)) {
      this.reject(m, 'STALE_REVISION'); return;
    }
    items.sort(function(a, c) { return a.dueAtMs - c.dueAtMs; });
    this.ddl = items; this.ddlContent = ddlContent; this.ddlRevision = b.revision;
    this.ddlUntil = b.validUntilMs; this.truncated = b.truncated === true;
    if (!this.remindersEnabled && b.remindersEnabled === true) this.reminderCursor = this.phoneNow();
    this.remindersEnabled = b.remindersEnabled === true;
    if (!this.remindersEnabled || (this.alert && !items.some(function(item) {
      return item.status === 'open' && item.title === this.alert.title;
    }, this))) this.alert = null;
    this.updatedAt = integer(b.generatedAtMs) ? b.generatedAtMs : this.phoneNow();
    this.applied('ddl'); this.error = ''; this.silence = 0; this.publish();
    this.commit(m, 'ddl', b.revision);
  } else if (m.type === 'schedule.snapshot') {
    if (!integer(b.revision) || b.revision < 1 || !integer(b.validUntilMs) ||
        b.validUntilMs <= this.phoneNow() || !Array.isArray(b.items) || b.items.length > 50) {
      this.reject(m, 'INVALID_PAYLOAD'); return;
    }
    var valid = b.items.every(function(item) {
      return item && typeof item.name === 'string' && item.name.trim() && characters(item.name) <= 80 &&
        typeof item.location === 'string' && characters(item.location) <= 40 &&
        integer(item.startAtMs) && item.startAtMs > 0 && integer(item.endAtMs) && item.endAtMs > item.startAtMs;
    });
    if (!valid) { this.reject(m, 'INVALID_PAYLOAD'); return; }
    var content = JSON.stringify(b.items);
    if (b.revision < this.scheduleRevision || (b.revision === this.scheduleRevision && content !== this.scheduleContent)) {
      this.reject(m, 'STALE_REVISION'); return;
    }
    this.schedule = b.items.slice().sort(function(a, c) { return a.startAtMs - c.startAtMs; });
    this.scheduleRevision = b.revision; this.scheduleContent = content;
    this.scheduleUntil = b.validUntilMs; this.scheduleTruncated = b.truncated === true;
    this.silence = 0; this.applied('schedule'); this.error = ''; this.publish();
    this.updatedAt = integer(b.generatedAtMs) ? b.generatedAtMs : this.phoneNow();
    this.commit(m, 'schedule', b.revision);
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
  if (code === 'ACCOUNT_NOT_READY') return '请在手机中完成账号绑定后重试';
  if (code === 'RATE_LIMITED') return '请求过于频繁，请稍后重试';
  if (code === 'PAYLOAD_TOO_LARGE') return '校园码数据过大，请使用手机校园码';
  if (code === 'CODE_EXPIRED') return '校园码已过期，请刷新';
  return '更新失败，请检查手机连接后重试';
}
