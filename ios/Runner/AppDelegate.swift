import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var platformChannel: FlutterMethodChannel?
  private var appFeedback: AppFeedback?
  private var flutterConfigured = false
  private let deadlineWidgetBridge = DeadlineWidgetBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      _ = deadlineWidgetBridge.capture(url)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    appFeedback = AppFeedback(registrar: registrar)
    deadlineWidgetBridge.configure(messenger: registrar.messenger())

    let platformChannel = FlutterMethodChannel(
      name: "techpie/platform", binaryMessenger: registrar.messenger()
    )
    platformChannel.setMethodCallHandler { call, result in
      guard call.method == "getUserAgentInfo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "device": UIDevice.current.model,
        "system": UIDevice.current.systemName,
        "systemVersion": UIDevice.current.systemVersion,
        "scale": window.screen.scale,
      ])
    }
    self.platformChannel = platformChannel

    flutterConfigured = true
    return true
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if deadlineWidgetBridge.capture(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
