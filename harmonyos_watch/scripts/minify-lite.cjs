// Compress compiled Lite pages before BIN generation and signing.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { assertLiteAst } = require('./lite-compatibility.cjs');
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
        // ACE Lite evaluates the bundle as an expression to obtain its ViewModel.
        compress: {passes: 2, expression: true},
        mangle: true,
        format: { comments: false, ascii_only: true, ast: true },
      });
      assertLiteAst(result.ast, file);
      if (!result.code) throw new Error('Empty minified page: ' + file);
      if (name === 'app.js' || file.includes(path.sep + 'pages' + path.sep)) {
        function ViewModel() {}
        const entry = vm.runInNewContext(result.code, { ViewModel, requireNative: () => ({}) }, {filename: file, timeout: 2000});
        if (!(entry instanceof ViewModel)) throw new Error('Lite entry must return its ViewModel: ' + file);
      }
      const size = Buffer.byteLength(result.code);
      if (size > 48000) throw new Error('Lite JS page exceeds 48,000 bytes: ' + file);
      fs.writeFileSync(file, result.code, 'utf8');
      console.log('[techpie-lite] ' + name + ': ' + Buffer.byteLength(original) + ' -> ' + size + ' bytes');
    } else if (name.endsWith('.map')) {
      // Maps are debug tools, not runtime assets; exclude them before packaging.
      fs.unlinkSync(file);
    }
  }
}
// $t reads packaged string resources on Lite, independently of file storage.
const source = path.join(__dirname, '../entry/src/main/js/MainAbility/common');
const points = require(path.join(source, 'sm2-points.json'));
const sm2 = Object.fromEntries(points.map((row, index) => ['p' + index, row]));
const locales = path.join(process.argv[2], 'i18n');
fs.mkdirSync(locales, {recursive: true});
for (const locale of ['zh-CN', 'en-US']) {
  const file = path.join(locales, locale + '.json');
  const resources = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  fs.writeFileSync(file, JSON.stringify({...resources, sm2}));
}
for (const name of ['LICENSE.techpie_wear', 'vendor/LICENSE.qrcode.txt']) {
  const target = path.join(process.argv[2], 'common', name);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  fs.copyFileSync(path.join(source, name), target);
}

visit(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
