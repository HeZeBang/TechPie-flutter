import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let nativeGlassTabBarViewType = "techpie/native_glass_tab_bar"
  private let nativeGlassFloatingButtonViewType = "techpie/native_glass_floating_button"

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
    registrar.register(
      NativeGlassFloatingButtonFactory(messenger: registrar.messenger()),
      withId: nativeGlassFloatingButtonViewType
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
  private let tabBarIconPointSize: CGFloat = 20
  private let tabBarImageTopInset: CGFloat = -3
  private let tabBarTitleVerticalOffset: CGFloat = 3

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

  private var barBackgroundColor: UIColor {
    UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor.systemBackground.withAlphaComponent(0.84)
      }

      return UIColor.systemBackground.withAlphaComponent(0.88)
    }
  }

  private var selectedItemColor: UIColor {
    UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor(
          red: 0x0A / 255.0,
          green: 0x84 / 255.0,
          blue: 0xFF / 255.0,
          alpha: 1.0
        )
      }

      return UIColor(
        red: 0x00 / 255.0,
        green: 0x7A / 255.0,
        blue: 0xFF / 255.0,
        alpha: 1.0
      )
    }
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

  private var tabBarTitlePositionAdjustment: UIOffset {
    UIOffset(horizontal: 0, vertical: tabBarTitleVerticalOffset)
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
    scheduleInitialSelectionSync()

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
    appearance.backgroundColor = barBackgroundColor
    appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
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
    itemAppearance.normal.titlePositionAdjustment = tabBarTitlePositionAdjustment

    itemAppearance.selected.iconColor = selectedItemColor
    itemAppearance.selected.titleTextAttributes = selectedTitleAttributes
    itemAppearance.selected.titlePositionAdjustment = tabBarTitlePositionAdjustment

    itemAppearance.focused.iconColor = selectedItemColor
    itemAppearance.focused.titleTextAttributes = selectedTitleAttributes
    itemAppearance.focused.titlePositionAdjustment = tabBarTitlePositionAdjustment

    itemAppearance.disabled.iconColor = normalItemColor.withAlphaComponent(0.28)
    itemAppearance.disabled.titleTextAttributes = [
      .foregroundColor: normalItemColor.withAlphaComponent(0.28),
      .font: UIFont.systemFont(ofSize: 10.5, weight: .medium)
    ]
    itemAppearance.disabled.titlePositionAdjustment = tabBarTitlePositionAdjustment
  }

  private func applyItems() {
    let tabItems = items.enumerated().map { index, item in
      let image = configuredSymbolImage(named: item.sfSymbol, weight: .medium)
      let selectedImage = configuredSymbolImage(named: item.selectedSfSymbol, weight: .semibold)

      let tabItem = UITabBarItem(
        title: item.label,
        image: image,
        selectedImage: selectedImage
      )

      tabItem.tag = index
      applyLayoutAdjustments(to: tabItem)
      tabItem.setTitleTextAttributes(normalTitleAttributes, for: .normal)
      tabItem.setTitleTextAttributes(selectedTitleAttributes, for: .selected)

      return tabItem
    }

    tabBar.setItems(tabItems, animated: false)
    applySelectedItem()
    refreshTabBarColors()
  }

  private func updateSelection(to index: Int) {
    selectedIndex = clampedIndex(index)
    applySelectedItem()
    refreshTabBarColors()
  }

  private func applySelectedItem() {
    guard let tabItems = tabBar.items, tabItems.indices.contains(selectedIndex) else {
      return
    }

    tabBar.selectedItem = tabItems[selectedIndex]
  }

  private func refreshTabBarColors() {
    tabBar.tintColor = selectedItemColor
    tabBar.unselectedItemTintColor = normalItemColor

    if let tabItems = tabBar.items {
      for item in tabItems {
        applyLayoutAdjustments(to: item)
        item.setTitleTextAttributes(normalTitleAttributes, for: .normal)
        item.setTitleTextAttributes(selectedTitleAttributes, for: .selected)
      }
    }

    tabBar.setNeedsLayout()
    tabBar.layoutIfNeeded()
  }

  private func scheduleInitialSelectionSync() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.applySelectedItem()
      self.refreshTabBarColors()
    }
  }

  private func configuredSymbolImage(named systemName: String, weight: UIImage.SymbolWeight)
    -> UIImage?
  {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: tabBarIconPointSize,
      weight: weight,
      scale: .medium
    )

    return UIImage(systemName: systemName, withConfiguration: configuration)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func applyLayoutAdjustments(to item: UITabBarItem) {
    item.imageInsets = UIEdgeInsets(
      top: tabBarImageTopInset,
      left: 0,
      bottom: -tabBarImageTopInset,
      right: 0
    )
    item.titlePositionAdjustment = tabBarTitlePositionAdjustment
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

private final class NativeGlassFloatingButtonFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassFloatingButtonPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

private final class NativeGlassFloatingButtonPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let button = UIButton(type: .system)

  private var sfSymbol = "plus"

  private var buttonBaseColor: UIColor {
    UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor.systemBackground.withAlphaComponent(0.84)
      }

      return UIColor.systemBackground.withAlphaComponent(0.88)
    }
  }

  private var iconColor: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.96)
        : UIColor.black.withAlphaComponent(0.82)
    }
  }

  init(
    frame: CGRect,
    viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "techpie/native_glass_floating_button/\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    parseArguments(args)
    buildViewHierarchy()
    applyButtonAppearance()

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func view() -> UIView {
    rootView
  }

  private func parseArguments(_ args: Any?) {
    guard
      let params = args as? [String: Any],
      let rawSymbol = params["sfSymbol"] as? String,
      !rawSymbol.isEmpty
    else {
      return
    }

    sfSymbol = rawSymbol
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear
    rootView.clipsToBounds = false

    button.translatesAutoresizingMaskIntoConstraints = false
    button.adjustsImageWhenHighlighted = true
    button.tintAdjustmentMode = .normal
    button.clipsToBounds = false
    button.imageView?.contentMode = .center

    button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    button.addTarget(
      self,
      action: #selector(handlePressBegan),
      for: [.touchDown, .touchDragEnter]
    )
    button.addTarget(
      self,
      action: #selector(handlePressEnded),
      for: [.touchCancel, .touchDragExit, .touchUpInside, .touchUpOutside]
    )

    rootView.addSubview(button)

    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])
  }

  private func symbolImage() -> UIImage? {
    let symbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 22,
      weight: .semibold,
      scale: .medium
    )

    return UIImage(systemName: sfSymbol, withConfiguration: symbolConfiguration)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func applyButtonAppearance() {
    let image = symbolImage()

    if #available(iOS 26.0, *) {
      applyLiquidGlassAppearance(image: image)
    } else if #available(iOS 15.0, *) {
      applyModernFallbackAppearance(image: image)
    } else {
      applyLegacyFallbackAppearance(image: image)
    }
  }

  @available(iOS 26.0, *)
  private func applyLiquidGlassAppearance(image: UIImage?) {
    var configuration = UIButton.Configuration.prominentGlass()
    configuration.image = image
    configuration.cornerStyle = .capsule

    configuration.baseForegroundColor = iconColor

    configuration.baseBackgroundColor = buttonBaseColor

    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 18,
      leading: 18,
      bottom: 18,
      trailing: 18
    )

    button.configuration = configuration
    button.tintColor = iconColor
    button.backgroundColor = .clear

    button.layer.shadowOpacity = 0
    button.layer.borderWidth = 0

    button.setNeedsUpdateConfiguration()
  }

  @available(iOS 15.0, *)
  private func applyModernFallbackAppearance(image: UIImage?) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = image
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = iconColor
    configuration.baseBackgroundColor = buttonBaseColor
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 18,
      leading: 18,
      bottom: 18,
      trailing: 18
    )

    button.configuration = configuration
    button.tintColor = iconColor
    button.backgroundColor = buttonBaseColor

    button.layer.cornerRadius = 32
    button.layer.cornerCurve = .continuous
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.16
    button.layer.shadowRadius = 18
    button.layer.shadowOffset = CGSize(width: 0, height: 8)
    button.layer.borderWidth = 0

    button.setNeedsUpdateConfiguration()
  }

  private func applyLegacyFallbackAppearance(image: UIImage?) {
    button.setImage(image, for: .normal)

    button.tintColor = iconColor

    button.backgroundColor = buttonBaseColor

    button.contentEdgeInsets = UIEdgeInsets(
      top: 18,
      left: 18,
      bottom: 18,
      right: 18
    )

    button.layer.cornerRadius = 32
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.16
    button.layer.shadowRadius = 18
    button.layer.shadowOffset = CGSize(width: 0, height: 8)
    button.layer.borderWidth = 0

    if #available(iOS 13.0, *) {
      button.layer.cornerCurve = .continuous
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateSymbol":
      guard
        let arguments = call.arguments as? [String: Any],
        let symbol = arguments["sfSymbol"] as? String,
        !symbol.isEmpty
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected an sfSymbol string.",
            details: nil
          )
        )
        return
      }

      sfSymbol = symbol
      applyButtonAppearance()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc
  private func handleTap() {
    let feedback = UIImpactFeedbackGenerator(style: .light)
    feedback.impactOccurred(intensity: 0.65)

    channel.invokeMethod("onTap", arguments: nil)
  }

  @objc
  private func handlePressBegan() {
    let feedback = UIImpactFeedbackGenerator(style: .soft)
    feedback.impactOccurred(intensity: 0.35)

    if #available(iOS 26.0, *) {
      return
    }

    UIView.animate(
      withDuration: 0.14,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut]
    ) {
      self.button.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
      self.button.alpha = 0.88
    }
  }

  @objc
  private func handlePressEnded() {
    if #available(iOS 26.0, *) {
      return
    }

    UIView.animate(
      withDuration: 0.20,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut]
    ) {
      self.button.transform = .identity
      self.button.alpha = 1.0
    }
  }
}