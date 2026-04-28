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
    let factory = NativeGlassTabBarFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: nativeGlassTabBarViewType)
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

private final class NativeGlassTabBarPlatformView: NSObject, FlutterPlatformView {
  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "techpie/native_glass_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )

    if let params = arguments as? [String: Any] {
      let selectedIndex = params["selectedIndex"] as? Int ?? 0
      self.selectedIndex = selectedIndex
      if let rawItems = params["items"] as? [[String: Any]] {
        items = rawItems.compactMap(TabBarItem.init)
      }
    }

    if items.isEmpty {
      items = [
        TabBarItem(label: "Home", sfSymbol: "house", selectedSfSymbol: "house.fill"),
        TabBarItem(
          label: "Schedule",
          sfSymbol: "calendar",
          selectedSfSymbol: "calendar.circle.fill"
        ),
        TabBarItem(
          label: "Assignments",
          sfSymbol: "checkmark.circle",
          selectedSfSymbol: "checkmark.circle.fill"
        ),
        TabBarItem(label: "Settings", sfSymbol: "gearshape", selectedSfSymbol: "gearshape.fill")
      ]
    }

    super.init()
    buildViewHierarchy()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let effectView = UIVisualEffectView()
  private let stackView = UIStackView()
  private var items: [TabBarItem] = []
  private var buttons: [UIButton] = []
  private var selectedIndex = 0

  func view() -> UIView {
    rootView
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear

    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.clipsToBounds = true
    effectView.backgroundColor = .clear
    configureEffectAppearance()

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = 4

    rootView.addSubview(effectView)
    effectView.contentView.addSubview(stackView)

    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      effectView.topAnchor.constraint(equalTo: rootView.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 8),
      stackView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -8),
      stackView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 6),
      stackView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -6)
    ])

    rebuildButtons()
  }

  private func configureEffectAppearance() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      effectView.effect = glassEffect
      effectView.cornerConfiguration = .capsule()
    } else {
      effectView.effect = UIBlurEffect(style: .systemChromeMaterial)
      effectView.layer.cornerRadius = 28
      effectView.layer.cornerCurve = .continuous
    }
  }

  private func rebuildButtons() {
    buttons.forEach { button in
      stackView.removeArrangedSubview(button)
      button.removeFromSuperview()
    }
    buttons.removeAll(keepingCapacity: true)

    for (index, item) in items.enumerated() {
      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = index
      button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
      applyButtonAppearance(button, item: item, selected: index == selectedIndex)
      stackView.addArrangedSubview(button)
      buttons.append(button)
    }

    updateSelection(to: selectedIndex)
  }

  private func applyButtonAppearance(_ button: UIButton, item: TabBarItem, selected: Bool) {
    if #available(iOS 15.0, *) {
      button.configuration = buttonConfiguration(for: item, selected: selected)
      return
    }

    button.setTitle(item.label, for: .normal)
    button.setImage(
      UIImage(systemName: selected ? item.selectedSfSymbol : item.sfSymbol),
      for: .normal
    )
    button.tintColor = selected ? .label : .secondaryLabel
    button.setTitleColor(selected ? .label : .secondaryLabel, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 11, weight: selected ? .semibold : .medium)
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
  }

  @available(iOS 15.0, *)
  private func buttonConfiguration(for item: TabBarItem, selected: Bool) -> UIButton.Configuration {
    var configuration = UIButton.Configuration.plain()
    configuration.title = item.label
    configuration.image = UIImage(
      systemName: selected ? item.selectedSfSymbol : item.sfSymbol
    )
    configuration.imagePlacement = .top
    configuration.imagePadding = 4
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    configuration.baseForegroundColor = selected ? .label : .secondaryLabel

    let titleFont = UIFont.systemFont(ofSize: 11, weight: selected ? .semibold : .medium)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var container = $0
      container.font = titleFont
      return container
    }
    return configuration
  }

  private func updateSelection(to index: Int) {
    guard items.indices.contains(index) else { return }
    selectedIndex = index
    for (buttonIndex, button) in buttons.enumerated() {
      applyButtonAppearance(
        button,
        item: items[buttonIndex],
        selected: buttonIndex == selectedIndex
      )
      button.accessibilityTraits = buttonIndex == selectedIndex
        ? [.button, .selected]
        : [.button]
    }
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
            message: "Expected an index when updating the native tab bar selection.",
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

  @objc
  private func handleTap(_ sender: UIButton) {
    updateSelection(to: sender.tag)
    channel.invokeMethod("onSelect", arguments: ["index": sender.tag])
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

    self.init(label: label, sfSymbol: sfSymbol, selectedSfSymbol: selectedSfSymbol)
  }
}
