import { legacyHapTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const { normalizeFile, readSdkRange } = require('../scripts/lite-profile.cjs');

hvigor.nodesEvaluated(() => {
  const node = hvigor.getNodeByName('entry');
  const task = node?.getTaskByName('default@LegacyGenerateLiteCode');
  if (!task) throw new Error('Lite BIN packaging task was not found.');
  task.beforeRun(() => {
    // Debug is the SDK's Lite BIN packaging path. Minify before that task
    // rather than switching to release, which creates a different HAP layout.
    const sdkHome = process.env.DEVECO_SDK_HOME;
    if (!sdkHome) throw new Error('DEVECO_SDK_HOME is required for Lite minification.');
    execFileSync(process.execPath, [
      path.join(__dirname, '../scripts/validate-signing-config.cjs'),
      '--compiled-dir',
      path.join(__dirname, 'build/default/intermediates/loader_out_lite/default/js'),
    ], { stdio: 'inherit' });
    execFileSync(process.execPath, [
      path.join(__dirname, '../scripts/minify-lite.cjs'),
      path.join(__dirname, 'build/default/intermediates/loader_out_lite/default/js'),
      path.join(sdkHome, 'default/openharmony/js/build-tools/ace-loader/node_modules/terser'),
    ], { stdio: 'inherit' });
    const [compatible, target] = readSdkRange(path.join(__dirname, '../build-profile.json5'));
    normalizeFile(
      path.join(__dirname, 'build/default/intermediates/res/default/config.json'),
      compatible,
      target
    );
  });
});

export default {
  system: legacyHapTasks,
  plugins: []
};
