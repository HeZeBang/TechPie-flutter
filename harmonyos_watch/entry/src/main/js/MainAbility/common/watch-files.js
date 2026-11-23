
var pending = [], writing = false;
export function readJson(name, done) {
  var file = require('./watch-file-native.js').default;
  // readText is capped at 4096 bytes on Lite, including existing UTF-8 JSON files.
  file.readArrayBuffer({uri: 'internal://app/' + name,
    success: function(value) {
      var parsed;
      try {
        var bytes = value.buffer, encoded = '';
        for (var i = 0; i < bytes.length; i++) {
          var b = bytes[i];
          encoded += b < 128 && b !== 37 ? String.fromCharCode(b) : '%' + ('0' + b.toString(16)).slice(-2);
        }
        parsed = JSON.parse(decodeURIComponent(encoded));
      }
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
