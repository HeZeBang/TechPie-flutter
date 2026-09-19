import AppIntents
import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var ecardDeepLinkChannel: FlutterMethodChannel?
  private var pendingEcardRoute: String?
  private var ecardFeedback: EcardFeedback?
  private var watchBridge: WatchConnectivityBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard
      let registrar = self.registrar(
        forPlugin: "TechPieNativeGlassRegistry"
      )
    else {
      assertionFailure("Failed to create registrar for TechPieNativeGlassRegistry")
      return false
    }

    NativeGlassRegistry.registerAll(with: registrar)
    ecardFeedback = EcardFeedback(registrar: registrar)
    watchBridge = WatchConnectivityBridge(registrar: registrar)

    let deepLinkChannel = FlutterMethodChannel(
      name: "techpie/ecard_deep_link",
      binaryMessenger: registrar.messenger()
    )
    deepLinkChannel.setMethodCallHandler { [weak self] call, result in
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
        if #available(iOS 14.0, *) {
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
    ecardDeepLinkChannel = deepLinkChannel

    if #available(iOS 16.0, *) {
      EcardAppShortcuts.updateAppShortcutParameters()
    }

    if let url = launchOptions?[.url] as? URL {
      _ = captureEcardPayURL(url, notifyFlutter: false)
    }

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
      handleEcardQuickAction(shortcut, notifyFlutter: false)
    {
      // Already queued for Flutter; prevent UIKit from delivering the action twice.
      return false
    }
    return launched
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if handleEcardQuickAction(shortcutItem, notifyFlutter: true) {
      completionHandler(true)
    } else {
      super.application(
        application, performActionFor: shortcutItem, completionHandler: completionHandler
      )
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if captureEcardPayURL(url, notifyFlutter: true) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func captureEcardPayURL(_ url: URL, notifyFlutter: Bool) -> Bool {
    guard
      url.scheme?.lowercased() == "techpie",
      url.host?.lowercased() == "ecard",
      url.path.lowercased() == "/pay"
    else {
      return false
    }
    openEcardPayCode(notifyFlutter: notifyFlutter)
    return true
  }

  private func handleEcardQuickAction(
    _ shortcutItem: UIApplicationShortcutItem, notifyFlutter: Bool
  ) -> Bool {
    guard shortcutItem.type == "techpie.ecard.pay" else { return false }
    openEcardPayCode(notifyFlutter: notifyFlutter)
    return true
  }

  func openEcardPayCode(notifyFlutter: Bool = true) {
    pendingEcardRoute = "pay"
    if notifyFlutter {
      ecardDeepLinkChannel?.invokeMethod("openPayCode", arguments: nil)
    }
  }
}
