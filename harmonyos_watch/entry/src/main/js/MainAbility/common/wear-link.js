import { P2pClient, Message, Builder } from './wearengine.js';
import config from './wear-config.js';
import { WatchConnection } from './wear-connection.js';

export function WearLink(changed) {
  this.changed = changed; this.client = null; this.timer = null;
  this.queue = []; this.sending = false; this.generation = 0;
  var link = this;
  this.connection = new WatchConnection(function(frame) { link.enqueue(frame); }, changed);
}
WearLink.prototype.start = function() {
  if (this.client) return;
  var link = this, epoch = ++this.generation, attempts = 0;
  try { this.client = new P2pClient(); } catch (_) { this.failed(); return; }
  // The official SDK obtains its native service version asynchronously.
  this.timer = setInterval(function() {
    if (epoch !== link.generation) return;
    attempts++;
    if (typeof link.client.version === 'undefined') {
      if (attempts >= 10) link.failed();
      return;
    }
    clearInterval(link.timer); link.timer = null;
    if (Number(link.client.version) < 401) { link.failed(); return; }
    link.client.setPeerPkgName(config.phonePackage);
    link.client.setPeerFingerPrint(config.phoneFingerprint);
    link.client.registerReceiver({
      onSuccess: function() {},
      onFailure: function() { if (epoch === link.generation) link.failed(); },
      onReceiveMessage: function(data) {
        if (epoch === link.generation && typeof data === 'string') link.connection.receive(data);
      }
    });
    link.timer = setInterval(function() {
      if (epoch === link.generation) link.connection.tick();
    }, 1000);
  }, 200);
};
WearLink.prototype.enqueue = function(frame) {
  if (this.queue.length >= 64) { this.failed(); return; }
  this.queue.push(frame); this.flush();
};
WearLink.prototype.flush = function() {
  if (this.sending || !this.client || !this.queue.length) return;
  this.sending = true;
  var link = this, epoch = this.generation, done = false;
  var builder = new Builder(); builder.setDescription(this.queue.shift());
  var message = new Message(); message.builder = builder;
  function finish(ok) {
    if (done || epoch !== link.generation) return;
    done = true; clearTimeout(link.sendTimer); link.sendTimer = null;
    link.sending = false;
    if (ok) link.flush(); else link.failed();
  }
  this.sendTimer = setTimeout(function() { finish(false); }, 8000);
  try {
    this.client.send(message, {
      onSuccess: function() {},
      onFailure: function() { finish(false); },
      onSendProgress: function() {},
      onSendResult: function(result) { finish(result && result.code === 207); }
    });
  } catch (_) { finish(false); }
};
WearLink.prototype.failed = function() {
  this.stop();
  this.changed({connected: false, name: '', studentId: '', error: '连接服务不可用，请重新打开应用'});
};
WearLink.prototype.stop = function() {
  this.generation++;
  if (this.timer) clearInterval(this.timer);
  if (this.sendTimer) clearTimeout(this.sendTimer);
  this.timer = null; this.sendTimer = null; this.queue = []; this.sending = false;
  if (this.client) {
    try { this.client.unregisterReceiver({onSuccess: function() {}, onFailure: function() {}}); } catch (_) {}
  }
  this.client = null; this.connection.reset();
};
