import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    appDelegate?.window = window

    for context in connectionOptions.urlContexts {
      if forward(context) {
        break
      }
    }

    if let shortcutItem = connectionOptions.shortcutItem {
      appDelegate?.application(
        UIApplication.shared,
        performActionFor: shortcutItem,
        completionHandler: { _ in }
      )
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      if forward(context) {
        return
      }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard shortcutItem.type == "techpie.ecard.pay", let appDelegate else {
      super.windowScene(windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
      return
    }
    appDelegate.application(
      UIApplication.shared,
      performActionFor: shortcutItem,
      completionHandler: completionHandler
    )
  }

  private func forward(_ context: UIOpenURLContext) -> Bool {
    guard context.url.scheme?.lowercased() == "techpie",
      context.url.host?.lowercased() == "ecard",
      context.url.path.lowercased() == "/pay"
    else {
      return false
    }
    var options: [UIApplication.OpenURLOptionsKey: Any] = [
      .openInPlace: context.options.openInPlace
    ]
    if let sourceApplication = context.options.sourceApplication {
      options[.sourceApplication] = sourceApplication
    }
    if let annotation = context.options.annotation {
      options[.annotation] = annotation
    }
    return appDelegate?.application(
      UIApplication.shared,
      open: context.url,
      options: options
    ) ?? false
  }
}
