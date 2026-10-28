/**
 * The app's side of the eCard bind tunnel: the `techpie/ecard_bind` channel the
 * Dart service calls, matching the Android implementation in MainActivity.
 *
 * The tunnel itself lives in a VPN extension process
 * (EcardBindVpnAbility), which the system starts here and which reports back
 * through the shared state file. Starting is the interactive step: the first
 * start shows the system's VPN authorization dialog, so `start` waits for the
 * extension's verdict instead of guessing.
 *
 * While the tunnel is up so is a DATA_TRANSFER long task: the flow is read in
 * the mini program, which leaves this app in the background, and the VPN
 * extension process would otherwise be frozen mid-flow.
 */

import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import { AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos/index';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import UIAbility from '@ohos.app.ability.UIAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import Want from '@ohos.app.ability.Want';
import wantAgent from '@ohos.app.ability.wantAgent';
import { WantAgent } from '@ohos.app.ability.wantAgent';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { clearState, readState, writeState } from './EcardBindState';

const DOMAIN: number = 0x0000;
const TAG: string = 'EcardBind';
const CHANNEL: string = 'techpie/ecard_bind';
const EXTENSION_ABILITY: string = 'EcardBindVpnAbility';
const ENTRY_ABILITY: string = 'EntryAbility';

/** How long the system's authorization dialog is given to be answered. */
const START_TIMEOUT_MS: number = 20000;
const POLL_INTERVAL_MS: number = 120;

export class EcardBindPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private methods: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private bundleName: string = '';
  private longTask: boolean = false;

  getUniqueClassName(): string {
    return 'EcardBindPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.methods = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.methods.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.methods?.setMethodCallHandler(null);
    this.methods = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
    this.bundleName = this.ability.context.abilityInfo.bundleName;
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'start') {
      this.start(call)
        .then((status: string) => result.success(status))
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'start failed: %{public}s', JSON.stringify(error));
          result.success('inactive');
        });
    } else if (call.method === 'stop') {
      this.stop()
        .then(() => result.success(null))
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'stop failed: %{public}s', JSON.stringify(error));
          result.success(null);
        });
    } else if (call.method === 'status') {
      result.success(this.status());
    } else {
      result.notImplemented();
    }
  }

  private status(): string {
    const filesDir = this.ability?.context.filesDir;
    if (filesDir === undefined) {
      return 'inactive';
    }
    const state = readState(filesDir);
    if (state === null) {
      return 'inactive';
    }
    if (state.status === 'active') {
      return 'active';
    }
    if (state.status === 'denied') {
      return 'denied';
    }
    return 'inactive';
  }

  /**
   * Records the request, starts the extension, and waits for what it says.
   *
   * The result is the extension's, not this method's: only the process that
   * holds the interface knows whether there is one.
   */
  private async start(call: MethodCall): Promise<string> {
    const filesDir = this.ability?.context.filesDir;
    const host: string = (call.argument('host') ?? '').toString().trim().toLowerCase();
    const ip: string = (call.argument('ip') ?? '').toString().trim();
    if (filesDir === undefined || host.length === 0 || ip.length === 0) {
      hilog.error(DOMAIN, TAG, 'start ignored: incomplete parameters');
      return 'inactive';
    }
    hilog.info(DOMAIN, TAG, 'start host=%{public}s answer=%{public}s', host, ip);
    writeState(filesDir, 'requested', host, ip);

    const want: Want = {
      deviceId: '',
      bundleName: this.bundleName,
      abilityName: EXTENSION_ABILITY,
    };
    try {
      await vpnExtension.startVpnExtensionAbility(want);
    } catch (error) {
      const failure = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'startVpnExtensionAbility failed: %{public}s', JSON.stringify(error));
      // Not being able to start it at all is a refusal or a packaging mistake;
      // both are worth telling apart in the UI.
      const missing = failure.code === 16000001 || failure.code === 16000002 ||
        failure.code === 16000011;
      return missing ? 'inactive' : 'denied';
    }

    const deadline = Date.now() + START_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const state = readState(filesDir);
      if (state !== null && state.status !== 'requested') {
        if (state.status === 'active') {
          await this.startLongTask();
          return 'active';
        }
        return state.status === 'denied' ? 'denied' : 'inactive';
      }
      await sleep(POLL_INTERVAL_MS);
    }
    hilog.warn(DOMAIN, TAG, 'the extension did not report a tunnel in time');
    return 'inactive';
  }

  private async stop(): Promise<void> {
    const want: Want = {
      deviceId: '',
      bundleName: this.bundleName,
      abilityName: EXTENSION_ABILITY,
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'stopVpnExtensionAbility failed: %{public}s', JSON.stringify(error));
    }
    const filesDir = this.ability?.context.filesDir;
    if (filesDir !== undefined) {
      clearState(filesDir);
    }
    await this.stopLongTask();
  }

  private async startLongTask(): Promise<void> {
    if (this.longTask) {
      return;
    }
    const ability = this.ability;
    if (ability === null) {
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.bundleName,
            abilityName: ENTRY_ABILITY,
          },
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(ability.context, ['dataTransfer'], agent);
      this.longTask = true;
      hilog.info(DOMAIN, TAG, 'long task started for the bind flow');
    } catch (error) {
      // The tunnel is up either way; without the long task it only has to
      // survive while the app is in front.
      hilog.warn(DOMAIN, TAG, 'cannot start the long task: %{public}s', JSON.stringify(error));
    }
  }

  private async stopLongTask(): Promise<void> {
    if (!this.longTask) {
      return;
    }
    const ability = this.ability;
    this.longTask = false;
    if (ability === null) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ability.context);
      hilog.info(DOMAIN, TAG, 'long task stopped');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cannot stop the long task: %{public}s', JSON.stringify(error));
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
