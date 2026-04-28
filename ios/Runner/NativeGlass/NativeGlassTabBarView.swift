import Flutter
import UIKit

final class NativeGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

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

private final class NativeGlassTabBarRootView: UIView {
  let tabBar = UITabBar()

  override init(frame: CGRect) {
    super.init(frame: frame)

    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = false

    tabBar.frame = bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tabBar.backgroundColor = .clear
    tabBar.clipsToBounds = false

    addSubview(tabBar)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    tabBar.frame = bounds
  }
}

final class NativeGlassTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  static let viewType = "techpie/native_glass_tab_bar"

  private let rootView: NativeGlassTabBarRootView
  private let channel: FlutterMethodChannel

  private var tabBar: UITabBar {
    rootView.tabBar
  }

  private var items: [NativeGlassTabBarItem] = []
  private var selectedIndex = 0

  init(
    frame: CGRect,
    viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    rootView = NativeGlassTabBarRootView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(Self.viewType)/\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    parseArguments(args)
    configureTabBar()
    applyItems()

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    rootView
  }

  private func parseArguments(_ args: Any?) {
    if let params = args as? [String: Any] {
      selectedIndex = params["selectedIndex"] as? Int ?? 0

      if let rawItems = params["items"] as? [[String: Any]] {
        items = rawItems.compactMap(NativeGlassTabBarItem.init)
      }
    }

    if items.isEmpty {
      items = [
        NativeGlassTabBarItem(
          label: "Home",
          sfSymbol: "house",
          selectedSfSymbol: "house.fill"
        ),
        NativeGlassTabBarItem(
          label: "Schedule",
          sfSymbol: "calendar",
          selectedSfSymbol: "calendar.circle.fill"
        ),
        NativeGlassTabBarItem(
          label: "Assignments",
          sfSymbol: "checkmark.circle",
          selectedSfSymbol: "checkmark.circle.fill"
        ),
        NativeGlassTabBarItem(
          label: "Settings",
          sfSymbol: "gearshape",
          selectedSfSymbol: "gearshape.fill"
        )
      ]
    }

    selectedIndex = clampedIndex(selectedIndex)
  }

  private func configureTabBar() {
    tabBar.delegate = self
    
    tabBar.itemPositioning = .fill

    tabBar.tintColor = NativeGlassColors.selectedBlue
    tabBar.unselectedItemTintColor = NativeGlassColors.normalItem

    tabBar.backgroundColor = .clear
    tabBar.clipsToBounds = false
  }

  private func applyItems() {
    let tabItems = items.enumerated().map { index, item in
      let tabItem = UITabBarItem(
        title: item.label,
        image: symbolImage(named: item.sfSymbol),
        selectedImage: symbolImage(named: item.selectedSfSymbol)
      )

      tabItem.tag = index
      return tabItem
    }

    tabBar.setItems(tabItems, animated: false)
    applySelectedItem()
  }

  private func updateSelection(to index: Int) {
    selectedIndex = clampedIndex(index)
    applySelectedItem()
  }

  private func applySelectedItem() {
    guard
      let tabItems = tabBar.items,
      tabItems.indices.contains(selectedIndex)
    else {
      return
    }

    tabBar.selectedItem = tabItems[selectedIndex]
  }

  private func symbolImage(named systemName: String) -> UIImage? {
    UIImage(systemName: systemName)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func clampedIndex(_ index: Int) -> Int {
    guard !items.isEmpty else {
      return 0
    }

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
    channel.invokeMethod("onSelect", arguments: ["index": selectedIndex])
  }
}

private struct NativeGlassTabBarItem {
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