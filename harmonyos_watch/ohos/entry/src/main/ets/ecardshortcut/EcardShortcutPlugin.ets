import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Want from '@ohos.app.ability.Want';

const CHANNEL = 'techpie/ecard_deep_link';
// The static shortcut marks itself in the launch Want's parameters; the value is
// the only thing this plugin trusts, never the shortcut's icon or label.
const TARGET_KEY = 'techpie_ecard_target';
const TARGET_PAY = 'pay';

/**
 * Routes a long-press shortcut (or any Want carrying the pay-code marker) to the
 * payment page, mirroring Android's EcardWidgetBridge on the same channel.
 *
 * This is the OHOS 快捷方式 (App Shortcut) counterpart — the equivalent of the
 * home-screen widget here is a 服务卡片 (Form), not this. Cold start: the
 * EntryAbility captures the Want before the Dart entrypoint runs and stashes
 * `pendingRoute`; Flutter's EcardWidgetService consumes it during initialize().
 * Warm start: onNewWant invokes `openPayCode` directly.
 */
export class EcardShortcutPlugin implements FlutterPlugin, MethodCallHandler {
  private methods: MethodChannel | null = null;
  private pendingRoute: string | null = null;

  getUniqueClassName(): string {
    return 'EcardShortcutPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.methods = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.methods.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.methods?.setMethodCallHandler(null);
    this.methods = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'consumePendingRoute') {
      result.success(this.pendingRoute);
    } else if (call.method === 'acknowledgePendingRoute') {
      this.pendingRoute = null;
      result.success(null);
    } else if (call.method === 'widgetAvailability') {
      // OHOS has no home-screen widget pinning on this channel; the shortcut is
      // the pay-code entry here. Unsupported hides the "add widget" affordance.
      result.success('unsupported');
    } else if (call.method === 'requestPinWidget') {
      result.success(false);
    } else {
      result.notImplemented();
    }
  }

  capture(want: Want, notifyFlutter: boolean): void {
    if (this.readTarget(want) !== TARGET_PAY) {
      return;
    }
    this.pendingRoute = TARGET_PAY;
    if (notifyFlutter) {
      this.methods?.invokeMethod('openPayCode', null);
    }
  }

  private readTarget(want: Want): string {
    const params = want.parameters;
    if (params == null) {
      return '';
    }
    const value: Object | undefined = params[TARGET_KEY];
    return typeof value === 'string' ? value as string : '';
  }
}
