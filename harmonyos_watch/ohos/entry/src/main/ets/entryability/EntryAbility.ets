import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { CampusCardPlatformPlugin } from '../campuscard/CampusCardPlatformPlugin';
import { EcardBindPlugin } from '../ecardbind/EcardBindPlugin';
import { EcardShortcutPlugin } from '../ecardshortcut/EcardShortcutPlugin';
import SystemFeedbackPlugin from '../platform/SystemFeedbackPlugin';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';

export default class EntryAbility extends FlutterAbility {
  private ecardShortcuts: EcardShortcutPlugin | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CampusCardPlatformPlugin())
    flutterEngine.getPlugins()?.add(new EcardBindPlugin())
    flutterEngine.getPlugins()?.add(new SystemFeedbackPlugin())
    this.ecardShortcuts = new EcardShortcutPlugin()
    flutterEngine.getPlugins()?.add(this.ecardShortcuts)
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Cold start: stash the shortcut marker before the Dart entrypoint runs, so
    // EcardWidgetService.initialize() can consume it via consumePendingRoute.
    super.onCreate(want, launchParam)
    this.ecardShortcuts?.capture(want, false)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Warm start: the app is already running, so push the target to Dart.
    super.onNewWant(want, launchParam)
    this.ecardShortcuts?.capture(want, true)
  }
}
