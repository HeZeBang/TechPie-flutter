import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  private var applicationDelegate: UIApplicationDelegate? {
    UIApplication.shared.delegate
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let sceneWindow = window ?? windowScene.windows.first,
      appDelegate?.configureFlutter(with: sceneWindow) == true
    else {
      return
    }
    window = sceneWindow

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

  func sceneDidBecomeActive(_ scene: UIScene) {
    applicationDelegate?.applicationDidBecomeActive?(UIApplication.shared)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    applicationDelegate?.applicationWillResignActive?(UIApplication.shared)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    applicationDelegate?.applicationDidEnterBackground?(UIApplication.shared)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    applicationDelegate?.applicationWillEnterForeground?(UIApplication.shared)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      if forward(context) {
        break
      }
    }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    _ = applicationDelegate?.application?(
      UIApplication.shared,
      continue: userActivity,
      restorationHandler: { _ in }
    )
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard let appDelegate else {
      completionHandler(false)
      return
    }
    appDelegate.application(
      UIApplication.shared,
      performActionFor: shortcutItem,
      completionHandler: completionHandler
    )
  }

  private func forward(_ context: UIOpenURLContext) -> Bool {
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
