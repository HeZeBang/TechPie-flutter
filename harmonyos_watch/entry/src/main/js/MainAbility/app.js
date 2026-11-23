import { WearLink } from './common/wear-link.js';
import { readJson, writeJson, removeLegacyGrants } from './common/watch-files.js';

var link, listener, leavePage, clock, state, loaded = false, loading = false, foreground = false, destroyed = false;
function publish(value) { state = value; if (listener) listener(value); }
function load() {
    removeLegacyGrants();
    readJson('watch-cache-v1.json', function(error, cache) {
      if (destroyed) return;
      if (cache && !link.connection.restore(cache) && cache.owner) error = 'INVALID_CACHE';
      if (error) { link.connection.error = '本地数据暂不可读，连接手机重新同步'; link.connection.publish(); }
      loaded = true; if (foreground) link.start();
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
  watchNow() { return link.connection.phoneNow(); }
  }},
  onCreate() {
    link = new WearLink(publish, {onCache: function(cache, done) {
      writeJson('watch-cache-v1.json', cache, done);
    }});
  },
  onDestroy() { destroyed = true; if (leavePage) leavePage(); pause(); }
};
