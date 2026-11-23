
var pending = [], writing = false;
export function readJson(name, done) {
  var file = require('./watch-file-native.js').default;
  file.readText({uri: 'internal://app/' + name, length: 98304,
    success: function(value) {
      var parsed;
      try { parsed = JSON.parse(value.text); }
      catch (error) { done('INVALID_CACHE'); return; }
      done(null, parsed);
    },
    fail: function(data, code) { done(code === 301 ? null : 'CACHE_READ_FAILED', null); }
  });
}
export function writeJson(name, value, done) {
  pending.push({name: name, text: JSON.stringify(value), done: done});
  flush();
}
function flush() {
  if (writing || !pending.length) return;
  writing = true;
  var next = pending.shift(), destination = 'internal://app/' + next.name;
  function finish(error) {
    writing = false; next.done(error); flush();
  }
  var file = require('./watch-file-native.js').default;
  file.writeText({uri: destination + '.tmp', text: next.text, append: false,
    success: function() {
      file.move({srcUri: destination + '.tmp', dstUri: destination,
        success: function() { finish(null); },
        fail: function() { finish('CACHE_REPLACE_FAILED'); }
      });
    },
    fail: function() { finish('CACHE_WRITE_FAILED'); }
  });
}
