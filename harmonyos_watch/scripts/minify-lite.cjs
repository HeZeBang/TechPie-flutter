// Compress compiled Lite pages before BIN generation and signing.
const fs = require('node:fs');
const path = require('node:path');
const { minify } = require(process.argv[3]);

async function visit(directory) {
  for (const name of fs.readdirSync(directory)) {
    const file = path.join(directory, name);
    if (fs.statSync(file).isDirectory()) {
      await visit(file);
    } else if (name.endsWith('.js')) {
      const original = fs.readFileSync(file, 'utf8');
      const result = await minify(original, {
        ecma: 5,
        compress: false,
        mangle: true,
        format: { comments: false, ascii_only: true },
      });
      if (!result.code) throw new Error('Empty minified page: ' + file);
      const size = Buffer.byteLength(result.code);
      if (size > 48 * 1024) throw new Error('Lite JS page exceeds 48 KB: ' + file);
      fs.writeFileSync(file, result.code, 'utf8');
      console.log('[techpie-lite] ' + name + ': ' + Buffer.byteLength(original) + ' -> ' + size + ' bytes');
    } else if (name.endsWith('.map')) {
      // Maps are debug tools, not runtime assets; exclude them before packaging.
      fs.unlinkSync(file);
    }
  }
}
visit(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
