import { legacyHapTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import path from 'node:path';

const { normalizeFile, readSdkRange } = require('../scripts/lite-profile.cjs');

hvigor.nodesEvaluated(() => {
  const node = hvigor.getNodeByName('entry');
  const task = node?.getTaskByName('default@LegacyGenerateLiteCode');
  if (!task) throw new Error('Lite BIN packaging task was not found.');
  task.beforeRun(() => {
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
