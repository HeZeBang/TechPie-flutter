// Create a separate Lite project so benchmark fixtures stay out of the companion.
const fs = require('node:fs');
const path = require('node:path');

function prepare(destination) {
  const watch = path.resolve(__dirname, '..');
  const stage = path.join(destination, 'harmonyos_watch');
  const source = 'entry/src/main';
  const pages = path.join(stage, source, 'js/MainAbility/pages');
  fs.mkdirSync(destination); // An existing directory may contain a signed build.
  function copy(from, to) {
    fs.mkdirSync(path.dirname(to), {recursive: true});
    fs.cpSync(from, to, {recursive: true});
  }
  for (const name of [
    'build.ps1', 'build-profile.template.json5', 'hvigor', 'hvigorfile.ts',
    'oh-package.json5', 'entry/build-profile.json5', 'entry/hvigorfile.ts',
    'entry/oh-package.json5', source,
  ]) {
    copy(path.join(watch, name), path.join(stage, name));
  }
  for (const file of fs.readdirSync(path.join(watch, 'scripts'))) {
    if (file.endsWith('.cjs') && !file.endsWith('.test.cjs')) {
      copy(path.join(watch, 'scripts', file), path.join(stage, 'scripts', file));
    }
  }
  const workflow = '.github/workflows/android-release.yml';
  copy(path.resolve(watch, '..', workflow), path.join(destination, workflow));

  const companion = path.join(pages, 'companion');
  fs.renameSync(path.join(pages, 'index'), companion);
  for (const ext of ['js', 'css', 'hml']) {
    fs.renameSync(path.join(companion, 'index.' + ext), path.join(companion, 'companion.' + ext));
  }
  copy(path.join(__dirname, 'index'), path.join(pages, 'index'));
  copy(path.join(__dirname, 'index/LICENSE.techpie_wear'),
    path.join(stage, source, 'resources/rawfile/licenses/LICENSE.techpie_wear'));

  const file = path.join(stage, source, 'config.json');
  const config = JSON.parse(fs.readFileSync(file, 'utf8'));
  config.module.js[0].pages = ['pages/index/index', 'pages/companion/companion'];
  config.app.version = {code: 20, name: '0.4.13'};
  fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n');
}

if (process.argv.length !== 3) throw new Error('Usage: node prepare.cjs NEW_DIRECTORY');
prepare(path.resolve(process.argv[2]));
