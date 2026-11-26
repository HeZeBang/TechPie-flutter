import AppIntents
import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var ecardDeepLinkChannel: FlutterMethodChannel?
  private var platformChannel: FlutterMethodChannel?
  private var pendingEcardRoute: String?
  private var ecardFeedback: EcardFeedback?
  private var ecardBindTunnel: EcardBindTunnelPlugin?
  private var watchBridge: WatchConnectivityBridge?
  private var flutterConfigured = false
  private let deadlineWidgetBridge = DeadlineWidgetBridge()
  private let deadlineReminderBridge = DeadlineReminderBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      _ = captureEcardPayURL(url, notifyFlutter: false)
      _ = deadlineWidgetBridge.capture(url)
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

  func configureFlutter(with window: UIWindow?) -> Bool {
    if flutterConfigured {
      return true
    }

    guard let window,
      let flutterViewController = window.rootViewController as? FlutterViewController
    else {
      assertionFailure("Failed to find the scene's FlutterViewController")
      return false
    }

    self.window = window
    window.tintColor = UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor(red: 0xE0 / 255.0, green: 0x31 / 255.0, blue: 0x40 / 255.0, alpha: 1.0)
        : UIColor(red: 0xA3 / 255.0, green: 0x0B / 255.0, blue: 0x19 / 255.0, alpha: 1.0)
    }
    GeneratedPluginRegistrant.register(with: flutterViewController)

    guard
      let registrar = flutterViewController.registrar(
        forPlugin: "TechPiePlatformPlugins"
      )
    else {
      assertionFailure("Failed to create registrar for TechPiePlatformPlugins")
      return false
    }

    IcsFilePresenterPlugin.register(with: registrar)
    ecardFeedback = EcardFeedback(registrar: registrar)
    ecardBindTunnel = EcardBindTunnelPlugin(messenger: registrar.messenger())
    watchBridge = WatchConnectivityBridge(registrar: registrar)
    deadlineWidgetBridge.configure(messenger: registrar.messenger())
    deadlineReminderBridge.configure(messenger: registrar.messenger())

    let platformChannel = FlutterMethodChannel(
      name: "techpie/platform", binaryMessenger: registrar.messenger()
    )
    platformChannel.setMethodCallHandler { [weak flutterViewController] call, result in
      switch call.method {
      case "getUserAgentInfo":
        result([
          "device": UIDevice.current.model,
          "system": UIDevice.current.systemName,
          "systemVersion": UIDevice.current.systemVersion,
          "scale": window.screen.scale,
        ])
      case "shareFile":
        guard let args = call.arguments as? [String: Any],
          let scope = args["scope"] as? String,
          let filename = args["filename"] as? String,
          scope.range(of: #"^[a-z0-9_-]{1,32}$"#, options: .regularExpression) != nil,
          !filename.isEmpty,
          filename != ".",
          filename != "..",
          !filename.contains("/"),
          !filename.contains("\\"),
          !filename.contains(".."),
          let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
          result(FlutterError(code: "invalid_file", message: "Invalid campus file arguments.", details: nil))
          return
        }
        let root = cache.appendingPathComponent("campus_files")
          .appendingPathComponent(scope)
          .resolvingSymlinksInPath()
        let file = root.appendingPathComponent(filename).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
          FileManager.default.fileExists(atPath: file.path)
        else {
          result(FlutterError(code: "missing_file", message: "Campus file is unavailable.", details: nil))
          return
        }
        guard let rootViewController = flutterViewController else {
          result(FlutterError(code: "unavailable", message: "Presenter unavailable.", details: nil))
          return
        }
        var presenter: UIViewController = rootViewController
        while let next = presenter.presentedViewController {
          presenter = next
        }
        if presenter.isBeingDismissed || presenter.isBeingPresented {
          result(FlutterError(code: "busy", message: "Another presentation is in progress.", details: nil))
          return
        }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = presenter.view
        let bounds = presenter.view.bounds
        share.popoverPresentationController?.sourceRect = CGRect(
          x: bounds.midX, y: bounds.midY, width: 1, height: 1
        )
        presenter.present(share, animated: true) { result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.platformChannel = platformChannel

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

    flutterConfigured = true
    return true
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
    if deadlineWidgetBridge.capture(url) || captureEcardPayURL(url, notifyFlutter: true) {
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
