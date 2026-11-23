var sdk;
import config from './wear-config.js';
import { WatchConnection } from './wear-connection.js';

export function WearLink(changed, options) {
  this.changed = changed; this.receiving = false; this.client = null; this.timer = null;
  this.queue = []; this.sending = false; this.generation = 0;
  var link = this;
  this.connection = new WatchConnection(function(frame, optional) { link.enqueue(frame, optional); }, changed, null, options);
}
WearLink.prototype.start = function() {
  if (this.client) return;
  var link = this, epoch = ++this.generation, attempts = 0;
  try { if (!sdk) sdk = require('./wearengine.js'); this.client = new sdk.P2pClient(); }
  catch (error) { console.error('TechPie transport startup: ' + String(error)); this.failed(); return; }
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
    try {
      console.info('TechPie receiver client: ' + typeof link.client);
      link.client.setPeerPkgName(config.phonePackage);
      link.client.setPeerFingerPrint(config.phoneFingerprint);
      link.client.registerReceiver({
      onSuccess: function() { if (epoch === link.generation) { link.receiving = true; link.connection.notifyReady(); } },
      onFailure: function() { if (epoch === link.generation) link.failed(); },
      onReceiveMessage: function(data) {
        if (epoch === link.generation && typeof data === 'string') link.connection.receive(data);
      }
      });
    } catch (error) {
      console.error('TechPie receiver registration: ' + String(error));
      link.failed('接收服务启动失败，请重新打开应用'); return;
    }
    if (epoch !== link.generation) return;
    link.timer = setInterval(function() {
      if (epoch === link.generation) link.connection.tick();
    }, 1000);
  }, 200);
};
WearLink.prototype.enqueue = function(frame, optional) {
  if (this.queue.length >= 64) { if (!optional) this.failed(); return; }
  this.queue.push({frame: frame, optional: optional}); this.flush();
};
WearLink.prototype.flush = function() {
  if (this.sending || !this.client || !this.queue.length) return;
  this.sending = true;
  var link = this, epoch = this.generation, done = false;
  var next = this.queue.shift();
  var builder = new sdk.Builder(); builder.setDescription(next.frame);
  var message = new sdk.Message(); message.builder = builder;
  function finish(ok) {
    if (done || epoch !== link.generation) return;
    done = true; clearTimeout(link.sendTimer); link.sendTimer = null;
    link.sending = false;
    // The phone may open after the watch. Keep listening if peer.ready is undeliverable.
    if (ok || next.optional) link.flush(); else link.failed();
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
WearLink.prototype.failed = function(message) {
  this.stop();
  this.connection.error = message || '暂未连接手机，使用本地数据';
  this.connection.publish();
};
WearLink.prototype.stop = function() {
  this.generation++;
  if (this.timer) clearInterval(this.timer);
  if (this.sendTimer) clearTimeout(this.sendTimer);
  this.timer = null; this.sendTimer = null; this.queue = []; this.sending = false;
  if (this.client) {
    try { this.client.unregisterReceiver({onSuccess: function() {}, onFailure: function() {}}); } catch (_) {}
  }
  this.receiving = false; this.client = null; this.connection.reset(false);
};
