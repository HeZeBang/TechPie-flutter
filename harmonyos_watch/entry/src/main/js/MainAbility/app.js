import { WearLink } from './common/wear-link.js';
import { readJson, writeJson } from './common/watch-files.js';
import {startQr} from './common/qr-matrix.js';

var link, listener, leavePage, clock, state, loaded = false, loading = false, foreground = false, destroyed = false;
var offlineReady = false, credential = null, owner = null, vault, grantGeneration = 0, vaultStatus = 'INITIALIZING';
function publish(value) { state = value; if (listener) listener(value); }
function load() {
    readJson('watch-cache-v1.json', function(error, cache) {
      if (destroyed) return;
      if (cache && !link.connection.restore(cache) && cache.owner) error = 'INVALID_CACHE';
      owner = link.connection.cacheBinding;
      if (error) { link.connection.error = '本地数据暂不可读，连接手机重新同步'; link.connection.publish(); }
      loaded = true; if (foreground) link.start();
      try { vault = require('./common/grant-vault.js'); }
      catch (error) { vaultStatus = 'MODULE_UNAVAILABLE'; link.connection.publish(); return; }
      vault.initializeVault(function(error) {
        if (destroyed) return;
        offlineReady = !error; vaultStatus = error || 'READY';
        if (error) console.info('TechPie offline keystore: ' + error);
        function finish() { link.connection.publish(); if (offlineReady && link.receiving && link.connection.nonce && !link.connection.offeredOffline) link.connection.notifyReady(); }
        if (!offlineReady || !owner) { finish(); return; }
        var restoringOwner = owner, generation = grantGeneration;
        vault.loadCredential(owner, function(error, grant) {
          if (destroyed) return;
          if (restoringOwner !== owner || generation !== grantGeneration) { finish(); return; }
          if (error) { link.connection.error = '离线授权读取失败，请在手机重新同步'; }
          else credential = grant;
          finish();
        });
      });
    });
}
function pause() {
  foreground = false; listener = null; leavePage = null;
  if (clock) clearInterval(clock);
  clock = null;
  if (link && link.client) link.stop();
}
export default {
  data: {api: {
  watchObserve(callback, leave) { listener = callback; leavePage = leave; if (state) callback(state); },
  watchResume() {
    if (destroyed || foreground) return;
    foreground = true;
    if (!loading) { loading = true; load(); }
    else if (loaded) link.start();
    if (!clock) clock = setInterval(function() {
      if (foreground && !link.client) { link.connection.tick(); if (loaded) link.start(); }
    }, 5000);
  },
  watchPause() { pause(); },
  watchSync() { if (!foreground) return; if (link.connection.ready) link.connection.request('sync'); else link.start(); },
  watchCode() { if (link.connection.ready) link.connection.request('code'); },
  watchHideCode() { link.connection.hideCode(); },
  watchState() { return state; },
  watchNow() { return link.connection.phoneNow(); },
  watchCredential() { return owner && owner === link.connection.cacheBinding && credential && credential.expiresAt * 1000 > link.connection.phoneNow() ? credential : null; },
  watchRandom(length) { return vault.randomBytes(length); },
  watchMatrix(bytes) { return startQr(bytes); }
  }},
  onCreate() {
    link = new WearLink(publish, {onCache: function(cache, done) {
      function store() { writeJson('watch-cache-v1.json', cache, done); }
      if (owner !== cache.owner) {
        grantGeneration++; owner = cache.owner; credential = null;
        writeJson('offline-grant-v1.json', null, function(error) { if (error) done(error); else store(); });
      } else store();
    }, offlineEnabled: function() { return offlineReady; }, offlineStatus: function() { return vaultStatus; },
    onAuthorization: function(binding, grant, done) {
      grantGeneration++;
      vault.saveCredential(binding, grant, function(error) {
        if (!error && binding === owner) credential = grant;
        done(error);
      });
    }});

  },
  onDestroy() { destroyed = true; if (leavePage) leavePage(); pause(); }
};
