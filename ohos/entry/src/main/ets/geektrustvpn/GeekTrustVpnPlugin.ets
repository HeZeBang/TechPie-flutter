/**
 * The app's side of the system tunnel: the `techpie/geektrust_vpn` channel the
 * Dart service calls. The tunnel itself lives in a VPN extension process
 * (GeekTrustVpnAbility), which the system starts here and which reports back
 * through the shared state file.
 *
 * Starting is the interactive step — the first start shows the system's VPN
 * authorization dialog — so `start` waits for the extension's verdict instead of
 * guessing.
 */

import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import { AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos/index';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import UIAbility from '@ohos.app.ability.UIAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import Want from '@ohos.app.ability.Want';
import { WantAgent } from '@ohos.app.ability.wantAgent';
import wantAgent from '@ohos.app.ability.wantAgent';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { clearState, readState, writeRequest } from './GeekTrustVpnState';

const DOMAIN: number = 0x0000;
const TAG: string = 'GeekTrustVpn';
const CHANNEL: string = 'techpie/geektrust_vpn';
const EXTENSION_ABILITY: string = 'GeekTrustVpnAbility';

/** Comma-separated list → entries. Plain strings on the channel: ArkTS refuses
 * `any`, and `JSON.parse` is typed as one. */
function splitList(text: string): string[] {
  const entries: string[] = [];
  for (const piece of text.split(',')) {
    const trimmed = piece.trim();
    if (trimmed.length > 0) {
      entries.push(trimmed);
    }
  }
  return entries;
}

/**
 * How long the extension is given to raise the interface *and* bring the engine
 * up. The engine dials the gateway in the background, which a mobile network can
 * stretch past ten seconds, and the extension only reports `active` after it —
 * so this is a generously patient number on purpose.
 */
const START_TIMEOUT_MS: number = 60000;
const POLL_INTERVAL_MS: number = 120;

export class GeekTrustVpnPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private methods: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private bundleName: string = '';
  private continuousTask: boolean = false;

  getUniqueClassName(): string {
    return 'GeekTrustVpnPlugin';
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
          const failure = error as BusinessError;
          const reason = `${failure.code ?? ''} ${failure.message ?? ''}`.trim() ||
            String(error);
          hilog.error(DOMAIN, TAG, 'start failed: %{public}s', reason);
          result.success('failed: ' + reason);
        });
    } else if (call.method === 'stop') {
      this.stop()
        .then(() => result.success(null))
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'stop failed: %{public}s', JSON.stringify(error));
          result.success(null);
        });
    } else if (call.method === 'startContinuousTask') {
      this.startContinuousTask()
        .then(() => result.success(true))
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'startContinuousTask failed: %{public}s',
            JSON.stringify(error));
          result.success(false);
        });
    } else if (call.method === 'stopContinuousTask') {
      this.stopContinuousTask()
        .then(() => result.success(true))
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'stopContinuousTask failed: %{public}s',
            JSON.stringify(error));
          result.success(false);
        });
    } else if (call.method === 'status') {
      const filesDir = this.ability?.context.filesDir;
      if (filesDir === undefined) {
        result.success('');
        return;
      }
      const state = readState(filesDir);
      result.success(state === null ? '' : JSON.stringify(state));
    } else {
      result.notImplemented();
    }
  }

  private async start(call: MethodCall): Promise<string> {
    const filesDir = this.ability?.context.filesDir;
    if (filesDir === undefined) {
      return 'failed: no files directory';
    }
    const session: string = (call.argument('session') ?? '').toString();
    const policy: string = (call.argument('policy') ?? '').toString();
    const routesText: string = (call.argument('routes') ?? '').toString();
    const dnsText: string = (call.argument('dns') ?? '').toString();
    if (session.length === 0 || policy.length === 0) {
      return 'failed: session and policy are required';
    }
    writeRequest(filesDir, session, policy, splitList(routesText), splitList(dnsText));

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
      const missing = failure.code === 16000001 || failure.code === 16000002 ||
        failure.code === 16000011;
      return missing ? 'failed: the VPN extension is missing from this build' :
        'failed: ' + JSON.stringify(error);
    }

    // The verdict arrives through the state file, not from the start call.
    const deadline = Date.now() + START_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const state = readState(filesDir);
      if (state !== null && state.status === 'active') {
        return 'active';
      }
      if (state !== null && state.status === 'failed') {
        return 'failed: ' + (state.error.length === 0 ? 'unknown' : state.error);
      }
      await new Promise<void>((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    return 'failed: the extension did not report a live tunnel within ' +
      `${START_TIMEOUT_MS}ms`;
  }

  /**
   * Asks the system for a `dataTransfer` long-running task. This is the OHOS
   * counterpart of what the Android side gets from a foreground service: without
   * it the app's process — the one that drives the tunnel — is frozen once it
   * leaves the foreground, and the tunnel goes with it. The pack already declares
   * `backgroundModes: ["dataTransfer"]` and KEEP_BACKGROUND_RUNNING, which is
   * what makes the request grantable; the system renders its own notification.
   */
  private async startContinuousTask(): Promise<void> {
    const ability = this.ability;
    if (ability === null) {
      throw new Error('no ability to ask from');
    }
    if (this.continuousTask) {
      return;
    }
    const want: Want = {
      bundleName: this.bundleName,
      abilityName: 'EntryAbility',
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    // The string-array overload (since API 12). The object form serialises to
    // null on the ArkTS side, and the call then fails with 9800005.
    const notification: backgroundTaskManager.ContinuousTaskNotification =
      await backgroundTaskManager.startBackgroundRunning(ability.context, ['dataTransfer'], agent);
    this.continuousTask = true;
    hilog.info(DOMAIN, TAG, 'continuous task started id=%{public}d',
      notification.notificationId);
  }

  private async stopContinuousTask(): Promise<void> {
    const ability = this.ability;
    if (ability === null || !this.continuousTask) {
      return;
    }
    await backgroundTaskManager.stopBackgroundRunning(ability.context);
    this.continuousTask = false;
    hilog.info(DOMAIN, TAG, 'continuous task stopped');
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
  }
}
