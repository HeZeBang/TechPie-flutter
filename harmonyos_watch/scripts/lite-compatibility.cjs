// The device JerryScript profile disables RegExp; Node checks use a different runtime.
function assertLiteAst(ast, file) {
  const visited = new WeakSet();
  function visit(node) {
    if (!node || typeof node !== 'object' || visited.has(node)) return;
    visited.add(node);
    if (node.TYPE === 'RegExp' || node.TYPE === 'BigInt') {
      throw new Error('Unsupported Lite syntax ' + node.TYPE + ' in ' + file);
    }
    for (const key of Object.keys(node)) visit(node[key]);
  }
  visit(ast);
}
module.exports = {assertLiteAst};
