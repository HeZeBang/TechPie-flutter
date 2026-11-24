const test = require('node:test');
const assert = require('node:assert/strict');
const {assertLiteAst} = require('./lite-compatibility.cjs');
test('device syntax check rejects RegExp and BigInt even inside a function body', () => {
  for (const kind of ['RegExp', 'BigInt']) {
    assert.throws(() => assertLiteAst({TYPE: 'Toplevel', body: [{TYPE: 'Function', body: [{TYPE: kind}]}]}, 'page.js'), /Unsupported Lite syntax/);
  }
  assert.doesNotThrow(() => assertLiteAst({TYPE: 'String', value: 'a literal mentioning /[a-z]/'}, 'page.js'));
});
