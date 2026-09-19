
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { CampusCardPlatformPlugin } from '../campuscard/CampusCardPlatformPlugin';
import SystemFeedbackPlugin from '../platform/SystemFeedbackPlugin';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CampusCardPlatformPlugin())
    flutterEngine.getPlugins()?.add(new SystemFeedbackPlugin())
  }
}
