import { WearLink } from './common/wear-link.js';
import { readJson, writeJson } from './common/watch-files.js';
import {encodeQr} from './common/qr-matrix.js';

var link, listener, clock, state, loaded = false, loading = false, foreground = false;
var offlineReady = false, credential = null, owner = null, vault;
function publish(value) { state = value; if (listener) listener(value); }
function load() {
    readJson('watch-cache-v1.json', function(error, cache) {
      if (cache && !link.connection.restore(cache) && cache.owner) error = 'INVALID_CACHE';
      owner = link.connection.cacheBinding;
      if (error) { link.connection.error = '本地数据暂不可读，连接手机重新同步'; link.connection.publish(); }
      loaded = true; if (foreground) link.start();
      try { vault = require('./common/grant-vault.js'); }
      catch (error) { console.info('TechPie offline module unavailable'); return; }
      vault.initializeVault(function(error) {
        offlineReady = !error;
        if (error) console.info('TechPie offline keystore: ' + error);
        function finish() { link.connection.publish(); if (link.receiving) link.connection.notifyReady(); }
        if (!offlineReady || !owner) { finish(); return; }
        vault.loadCredential(owner, function(error, grant) {
          if (error) { link.connection.error = '离线授权读取失败，请在手机重新同步'; }
          else credential = grant;
          finish();
        });
      });
    });
}
export default {
  data: {api: {
  watchObserve(callback) { listener = callback; if (state) callback(state); },
  watchResume() {
    foreground = true;
    if (!loading) { loading = true; load(); }
    else if (loaded) link.start();
    if (!clock) clock = setInterval(function() {
      if (!link.client) { link.connection.tick(); if (loaded) link.start(); }
    }, 5000);
  },
  watchPause() {
    foreground = false; listener = null;
    if (clock) clearInterval(clock); clock = null;
    link.stop();
  },
  watchSync() { if (link.connection.ready) link.connection.request('sync'); else link.start(); },
  watchCode() { if (link.connection.ready) link.connection.request('code'); },
  watchHideCode() { link.connection.hideCode(); },
  watchState() { return state; },
  watchNow() { return link.connection.phoneNow(); },
  watchCredential() { return owner && owner === link.connection.cacheBinding && credential && credential.expiresAt * 1000 > link.connection.phoneNow() ? credential : null; },
  watchRandom(length) { return vault.randomBytes(length); },
  watchMatrix(bytes) { return encodeQr(bytes); }
  }},
  onCreate() {
    link = new WearLink(publish, {onCache: function(cache, done) {
      function store() { writeJson('watch-cache-v1.json', cache, done); }
      if (owner !== cache.owner) {
        owner = cache.owner; credential = null;
        writeJson('offline-grant-v1.json', null, function(error) { if (error) done(error); else store(); });
      } else store();
    }, offlineEnabled: function() { return offlineReady; },
    onAuthorization: function(binding, grant, done) {
      vault.saveCredential(binding, grant, function(error) {
        if (!error && binding === owner) credential = grant;
        done(error);
      });
    }});

  },
  onDestroy() { if (clock) clearInterval(clock); if (link) link.stop(); }
};
