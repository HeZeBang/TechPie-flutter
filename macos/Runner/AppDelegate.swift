import Cocoa
import DeadlineWidgetSupport
import FlutterMacOS
import WidgetKit

@main
class AppDelegate: FlutterAppDelegate {
  let deadlineWidgetBridge = DeadlineWidgetBridge()
  let homeWidgetsBridge = HomeWidgetsBridge()
  let spotlightBridge = SpotlightBridge()
  private var ecardDeepLinkChannel: FlutterMethodChannel?
  private var pendingEcardRoute: String?

  func configureEcardDeepLink(messenger: FlutterBinaryMessenger) {
    guard ecardDeepLinkChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "techpie/ecard_deep_link",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "consumePendingRoute":
        result(self.pendingEcardRoute)
      case "acknowledgePendingRoute":
        self.pendingEcardRoute = nil
        result(nil)
      case "widgetAvailability":
        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadTimelines(ofKind: "EcardPayWidget")
          result("manual")
        } else {
          result("unsupported")
        }
      case "requestPinWidget":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    ecardDeepLinkChannel = channel
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var handled = false
    for url in urls {
      if deadlineWidgetBridge.capture(url)
        || homeWidgetsBridge.capture(url)
        || captureEcardPayURL(url, notifyFlutter: true)
      {
        handled = true
      }
    }
    if handled {
      application.activate(ignoringOtherApps: true)
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
  }

  private func captureEcardPayURL(_ url: URL, notifyFlutter: Bool) -> Bool {
    let scheme = TechPieWidgetURL.scheme()
    guard url.scheme?.lowercased() == scheme.lowercased(),
      url.host?.lowercased() == "ecard",
      url.path.lowercased() == "/pay"
    else { return false }
    pendingEcardRoute = "pay"
    if notifyFlutter {
      ecardDeepLinkChannel?.invokeMethod("openPayCode", arguments: nil)
    }
    return true
  }

  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    if spotlightBridge.handleUserActivity(userActivity) {
      application.activate(ignoringOtherApps: true)
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      return true
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
