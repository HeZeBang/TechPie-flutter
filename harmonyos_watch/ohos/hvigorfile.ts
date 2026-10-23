import path from 'path'
import { execFileSync } from 'child_process';
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';

// Generate build-profile.json5 from the template + OHOS_* env vars before
// hvigor parses the profile. Synchronous so the file is on disk in time.
execFileSync(
    'node',
    [path.join(__dirname, 'scripts', 'generate-build-profile.mjs')],
    { stdio: 'inherit' },
);

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* Custom plugin to extend the functionality of Hvigor. */
}