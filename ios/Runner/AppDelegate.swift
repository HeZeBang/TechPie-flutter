import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let nativeGlassTabBarViewType = "techpie/native_glass_tab_bar"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "TechPieNativeGlassTabBar"
    ) else {
      assertionFailure("Failed to create registrar for TechPieNativeGlassTabBar")
      return
    }

    registrar.register(
      NativeGlassTabBarFactory(messenger: registrar.messenger()),
      withId: nativeGlassTabBarViewType
    )
  }
}

private final class NativeGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  private let messenger: FlutterBinaryMessenger

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeGlassTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

private final class NativeGlassTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let tabBar = UITabBar()

  private var items: [TabBarItem] = []
  private var selectedIndex = 0

  private var normalItemColor: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.58)
        : UIColor.black.withAlphaComponent(0.46)
    }
  }

  private var selectedItemColor: UIColor {
    UIColor(red: 0x00 / 255.0, green: 0x88 / 255.0, blue: 0xCC / 255.0, alpha: 1.0)
  }

  private var normalTitleAttributes: [NSAttributedString.Key: Any] {
    [
      .foregroundColor: normalItemColor,
      .font: UIFont.systemFont(ofSize: 10.5, weight: .medium)
    ]
  }

  private var selectedTitleAttributes: [NSAttributedString.Key: Any] {
    [
      .foregroundColor: selectedItemColor,
      .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold)
    ]
  }

  init(
    frame: CGRect,
    viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "techpie/native_glass_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    parseArguments(args)
    buildViewHierarchy()
    applyItems()

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func view() -> UIView {
    rootView
  }

  private func parseArguments(_ args: Any?) {
    if let params = args as? [String: Any] {
      selectedIndex = params["selectedIndex"] as? Int ?? 0

      if let rawItems = params["items"] as? [[String: Any]] {
        items = rawItems.compactMap(TabBarItem.init)
      }
    }

    if items.isEmpty {
      items = [
        TabBarItem(label: "Home", sfSymbol: "house", selectedSfSymbol: "house.fill"),
        TabBarItem(label: "Schedule", sfSymbol: "calendar", selectedSfSymbol: "calendar.circle.fill"),
        TabBarItem(label: "Assignments", sfSymbol: "checkmark.circle", selectedSfSymbol: "checkmark.circle.fill"),
        TabBarItem(label: "Settings", sfSymbol: "gearshape", selectedSfSymbol: "gearshape.fill")
      ]
    }

    selectedIndex = clampedIndex(selectedIndex)
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear
    rootView.clipsToBounds = false

    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.backgroundColor = .clear
    tabBar.clipsToBounds = false

    configureTabBarAppearance()

    rootView.addSubview(tabBar)

    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: rootView.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])
  }

  private func configureTabBarAppearance() {
    let appearance = UITabBarAppearance()

    appearance.configureWithTransparentBackground()
    appearance.backgroundColor = .clear
    appearance.shadowColor = .clear
    appearance.shadowImage = nil
    appearance.backgroundImage = nil

    configureItemAppearance(appearance.stackedLayoutAppearance)
    configureItemAppearance(appearance.inlineLayoutAppearance)
    configureItemAppearance(appearance.compactInlineLayoutAppearance)

    tabBar.standardAppearance = appearance

    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }

    tabBar.tintColor = selectedItemColor
    tabBar.unselectedItemTintColor = normalItemColor
  }

  private func configureItemAppearance(_ itemAppearance: UITabBarItemAppearance) {
    itemAppearance.normal.iconColor = normalItemColor
    itemAppearance.normal.titleTextAttributes = normalTitleAttributes

    itemAppearance.selected.iconColor = selectedItemColor
    itemAppearance.selected.titleTextAttributes = selectedTitleAttributes

    itemAppearance.focused.iconColor = selectedItemColor
    itemAppearance.focused.titleTextAttributes = selectedTitleAttributes

    itemAppearance.disabled.iconColor = normalItemColor.withAlphaComponent(0.28)
    itemAppearance.disabled.titleTextAttributes = [
      .foregroundColor: normalItemColor.withAlphaComponent(0.28),
      .font: UIFont.systemFont(ofSize: 10.5, weight: .medium)
    ]
  }

  private func applyItems() {
    let tabItems = items.enumerated().map { index, item in
      let image = UIImage(systemName: item.sfSymbol)?
        .withRenderingMode(.alwaysTemplate)

      let selectedImage = UIImage(systemName: item.selectedSfSymbol)?
        .withRenderingMode(.alwaysTemplate)

      let tabItem = UITabBarItem(
        title: item.label,
        image: image,
        selectedImage: selectedImage
      )

      tabItem.tag = index
      tabItem.setTitleTextAttributes(normalTitleAttributes, for: .normal)
      tabItem.setTitleTextAttributes(selectedTitleAttributes, for: .selected)

      return tabItem
    }

    tabBar.setItems(tabItems, animated: false)

    if tabItems.indices.contains(selectedIndex) {
      tabBar.selectedItem = tabItems[selectedIndex]
    }

    refreshTabBarColors()
  }

  private func updateSelection(to index: Int) {
    selectedIndex = clampedIndex(index)

    guard let tabItems = tabBar.items, tabItems.indices.contains(selectedIndex) else {
      return
    }

    tabBar.selectedItem = tabItems[selectedIndex]
    refreshTabBarColors()
  }

  private func refreshTabBarColors() {
    tabBar.tintColor = selectedItemColor
    tabBar.unselectedItemTintColor = normalItemColor

    if let tabItems = tabBar.items {
      for item in tabItems {
        item.setTitleTextAttributes(normalTitleAttributes, for: .normal)
        item.setTitleTextAttributes(selectedTitleAttributes, for: .selected)
      }
    }

    tabBar.setNeedsLayout()
    tabBar.layoutIfNeeded()
  }

  private func clampedIndex(_ index: Int) -> Int {
    guard !items.isEmpty else { return 0 }
    return min(max(index, 0), items.count - 1)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateSelectedIndex":
      guard
        let arguments = call.arguments as? [String: Any],
        let index = arguments["index"] as? Int
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected an index.",
            details: nil
          )
        )
        return
      }

      updateSelection(to: index)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    let index = item.tag
    selectedIndex = clampedIndex(index)
    refreshTabBarColors()
    channel.invokeMethod("onSelect", arguments: ["index": selectedIndex])
  }
}

private struct TabBarItem {
  let label: String
  let sfSymbol: String
  let selectedSfSymbol: String

  init(label: String, sfSymbol: String, selectedSfSymbol: String) {
    self.label = label
    self.sfSymbol = sfSymbol
    self.selectedSfSymbol = selectedSfSymbol
  }

  init?(_ dictionary: [String: Any]) {
    guard
      let label = dictionary["label"] as? String,
      let sfSymbol = dictionary["sfSymbol"] as? String,
      let selectedSfSymbol = dictionary["selectedSfSymbol"] as? String
    else {
      return nil
    }

    self.init(
      label: label,
      sfSymbol: sfSymbol,
      selectedSfSymbol: selectedSfSymbol
    )
  }
}