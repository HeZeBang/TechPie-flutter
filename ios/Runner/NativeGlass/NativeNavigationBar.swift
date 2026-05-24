import Flutter
import UIKit

final class NativeNavigationBarFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeNavigationBarPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeNavigationBarPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_navigation_bar"

  private let rootView: UIView
  private let navigationBar = UINavigationBar()
  private let navigationItem = UINavigationItem()
  private let channel: FlutterMethodChannel

  private var configuration = NativeNavigationBarConfiguration()
  private var didInstallNavigationItem = false
  private var leadingGroupsByKey: [String: UIBarButtonItemGroup] = [:]
  private var trailingGroupsByKey: [String: UIBarButtonItemGroup] = [:]
  private var barButtonItemsByID: [String: UIBarButtonItem] = [:]
  private var itemIdByTag: [Int: String] = [:]
  private var nextTag = 1

  init(
    frame: CGRect,
    viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(Self.viewType)/\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    configuration = NativeNavigationBarConfiguration(arguments: args)
    buildViewHierarchy()
    applyConfiguration(animated: false)

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

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear
    rootView.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 0,
      leading: 20,
      bottom: 0,
      trailing: 20
    )
    navigationBar.translatesAutoresizingMaskIntoConstraints = false
    navigationBar.preservesSuperviewLayoutMargins = true
    rootView.addSubview(navigationBar)

    NSLayoutConstraint.activate([
      navigationBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      navigationBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      navigationBar.topAnchor.constraint(equalTo: rootView.topAnchor),
      navigationBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateConfiguration":
      configuration = NativeNavigationBarConfiguration(arguments: call.arguments)
      applyConfiguration(animated: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyConfiguration(animated: Bool) {
    nextTag = 1
    itemIdByTag.removeAll()

    navigationBar.prefersLargeTitles = configuration.largeTitleMode

    navigationItem.title = configuration.title
    navigationItem.largeTitleDisplayMode = configuration.largeTitleMode ? .always : .never
#if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      navigationItem.subtitle = configuration.largeTitleMode ? nil : configuration.subtitle
      navigationItem.largeSubtitle = configuration.largeTitleMode ? configuration.subtitle : nil
    }
#endif

    if #available(iOS 16.0, *) {
      let leadingItems = configuration.leadingItems.map(makeBarButtonItem)
      let trailingItems = configuration.trailingItems.map(makeBarButtonItem)
      navigationItem.leadingItemGroups = makeGroups(
        from: configuration.leadingItems,
        barButtonItems: leadingItems,
        existingGroups: &leadingGroupsByKey
      )
      navigationItem.trailingItemGroups = makeGroups(
        from: configuration.trailingItems,
        barButtonItems: trailingItems,
        existingGroups: &trailingGroupsByKey
      )
    } else {
      let leadingConfigurations = configuration.leadingItems.filter { !$0.hidden }
      let trailingConfigurations = configuration.trailingItems.filter { !$0.hidden }
      let leadingItems = leadingConfigurations.map(makeBarButtonItem)
      let trailingItems = trailingConfigurations.map(makeBarButtonItem)
      navigationItem.setLeftBarButtonItems(leadingItems, animated: animated)
      navigationItem.setRightBarButtonItems(trailingItems, animated: animated)
    }

    if !didInstallNavigationItem {
      didInstallNavigationItem = true
      navigationBar.setItems([navigationItem], animated: false)
    }
  }

  @available(iOS 16.0, *)
  private func makeGroups(
    from items: [NativeNavigationBarItem],
    barButtonItems: [UIBarButtonItem],
    existingGroups: inout [String: UIBarButtonItemGroup]
  ) -> [UIBarButtonItemGroup] {
    var keyedItems: [(key: String, items: [UIBarButtonItem])] = []
    var currentKey: String?
    var currentItems: [UIBarButtonItem] = []

    func flush() {
      guard !currentItems.isEmpty else { return }
      keyedItems.append((currentKey ?? "", currentItems))
      currentItems.removeAll()
    }

    for index in items.indices {
      let key = items[index].placementGroup ?? items[index].id
      if currentKey != key {
        flush()
        currentKey = key
      }
      currentItems.append(barButtonItems[index])
    }

    flush()

    let activeKeys = Set(keyedItems.map(\.key))
    existingGroups = existingGroups.filter { activeKeys.contains($0.key) }

    return keyedItems.map { keyedItem in
      if let group = existingGroups[keyedItem.key] {
        group.barButtonItems = keyedItem.items
        group.isHidden = keyedItem.items.allSatisfy(\.isHidden)
        return group
      }

      let group = UIBarButtonItemGroup(
        barButtonItems: keyedItem.items,
        representativeItem: nil
      )
      group.isHidden = keyedItem.items.allSatisfy(\.isHidden)
      existingGroups[keyedItem.key] = group
      return group
    }
  }

  private func makeBarButtonItem(_ item: NativeNavigationBarItem) -> UIBarButtonItem {
    if #available(iOS 14.0, *) {
      let barButtonItem = barButtonItemsByID[item.id] ?? UIBarButtonItem()
      let action: UIAction?
      if item.menuItems.isEmpty {
        action = UIAction(
          title: item.title ?? "",
          image: symbolImage(named: item.sfSymbol),
          attributes: item.role == "destructive" ? [.destructive] : []
        ) { [weak self] _ in
          self?.sendItemPressed(item.id)
        }
      } else {
        action = nil
      }

      barButtonItemsByID[item.id] = barButtonItem
      barButtonItem.title = item.title
      barButtonItem.image = symbolImage(named: item.sfSymbol)
      barButtonItem.primaryAction = action
      barButtonItem.menu = makeMenu(for: item)
      barButtonItem.isEnabled = item.enabled
      barButtonItem.style = item.role == "done" ? .done : .plain
      barButtonItem.accessibilityLabel = item.accessibilityLabel
      if #available(iOS 16.0, *) {
        barButtonItem.isHidden = item.hidden
      }
#if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        barButtonItem.identifier = item.id
      }
#endif
      return barButtonItem
    }

    let barButtonItem: UIBarButtonItem
    if let cachedItem = barButtonItemsByID[item.id] {
      barButtonItem = cachedItem
      barButtonItem.title = item.title
      barButtonItem.image = symbolImage(named: item.sfSymbol)
      barButtonItem.style = item.role == "done" ? .done : .plain
      barButtonItem.target = self
      barButtonItem.action = #selector(handleLegacyItem(_:))
    } else if let title = item.title, !title.isEmpty {
      barButtonItem = UIBarButtonItem(
        title: title,
        style: item.role == "done" ? .done : .plain,
        target: self,
        action: #selector(handleLegacyItem(_:))
      )
    } else if let image = symbolImage(named: item.sfSymbol) {
      barButtonItem = UIBarButtonItem(
        image: image,
        style: item.role == "done" ? .done : .plain,
        target: self,
        action: #selector(handleLegacyItem(_:))
      )
    } else {
      barButtonItem = UIBarButtonItem(
        title: item.accessibilityLabel ?? item.id,
        style: item.role == "done" ? .done : .plain,
        target: self,
        action: #selector(handleLegacyItem(_:))
      )
    }

    barButtonItemsByID[item.id] = barButtonItem
    let tag = nextTag
    nextTag += 1
    itemIdByTag[tag] = item.id
    barButtonItem.tag = tag
    barButtonItem.isEnabled = item.enabled
    barButtonItem.accessibilityLabel = item.accessibilityLabel
    return barButtonItem
  }

  @available(iOS 14.0, *)
  private func makeMenu(for item: NativeNavigationBarItem) -> UIMenu? {
    guard !item.menuItems.isEmpty else { return nil }
    return UIMenu(children: item.menuItems.map { makeMenuElement($0, itemID: item.id) })
  }

  @available(iOS 14.0, *)
  private func makeMenuElement(
    _ menuItem: NativeNavigationBarMenuItem,
    itemID: String
  ) -> UIMenuElement {
    if !menuItem.children.isEmpty {
      return UIMenu(
        title: menuItem.title,
        image: symbolImage(named: menuItem.sfSymbol),
        children: menuItem.children.map { makeMenuElement($0, itemID: itemID) }
      )
    }

    return UIAction(
      title: menuItem.title,
      image: symbolImage(named: menuItem.sfSymbol),
      attributes: menuItem.destructive ? [.destructive] : [],
      state: menuItem.checked ? .on : .off
    ) { [weak self] _ in
      self?.sendMenuSelected(itemID, value: menuItem.value)
    }
  }

  private func symbolImage(named systemName: String?) -> UIImage? {
    guard let systemName, !systemName.isEmpty else { return nil }
    return UIImage(systemName: systemName)
  }

  private func sendItemPressed(_ id: String) {
    channel.invokeMethod("onItemPressed", arguments: ["id": id])
  }

  private func sendMenuSelected(_ id: String, value: String) {
    channel.invokeMethod(
      "onMenuSelected",
      arguments: ["id": id, "value": value]
    )
  }

  @objc
  private func handleLegacyItem(_ sender: UIBarButtonItem) {
    guard let id = itemIdByTag[sender.tag] else { return }
    sendItemPressed(id)
  }
}

private struct NativeNavigationBarConfiguration {
  var title = ""
  var subtitle: String?
  var leadingItems: [NativeNavigationBarItem] = []
  var trailingItems: [NativeNavigationBarItem] = []
  var selectionMode = false
  var largeTitleMode = false

  init() {}

  init(arguments: Any?) {
    guard let params = arguments as? [String: Any] else { return }
    title = params["title"] as? String ?? ""
    subtitle = params["subtitle"] as? String
    selectionMode = params["selectionMode"] as? Bool ?? false
    largeTitleMode = params["largeTitleMode"] as? Bool ?? false

    leadingItems = (params["leadingItems"] as? [[String: Any]] ?? [])
      .map(NativeNavigationBarItem.init)
    trailingItems = (params["trailingItems"] as? [[String: Any]] ?? [])
      .map(NativeNavigationBarItem.init)
  }
}

private struct NativeNavigationBarItem {
  let id: String
  let title: String?
  let sfSymbol: String?
  let role: String
  let enabled: Bool
  let hidden: Bool
  let accessibilityLabel: String?
  let placementGroup: String?
  let menuItems: [NativeNavigationBarMenuItem]

  init(_ params: [String: Any]) {
    id = params["id"] as? String ?? ""
    title = params["title"] as? String
    sfSymbol = params["sfSymbol"] as? String
    role = params["role"] as? String ?? "normal"
    enabled = params["enabled"] as? Bool ?? true
    hidden = params["hidden"] as? Bool ?? false
    accessibilityLabel = params["accessibilityLabel"] as? String
    placementGroup = params["placementGroup"] as? String
    menuItems = (params["menuItems"] as? [[String: Any]] ?? [])
      .map(NativeNavigationBarMenuItem.init)
  }
}

private struct NativeNavigationBarMenuItem {
  let value: String
  let title: String
  let sfSymbol: String?
  let checked: Bool
  let destructive: Bool
  let children: [NativeNavigationBarMenuItem]

  init(_ params: [String: Any]) {
    value = params["value"] as? String ?? ""
    title = params["title"] as? String ?? value
    sfSymbol = params["sfSymbol"] as? String
    checked = params["checked"] as? Bool ?? false
    destructive = params["destructive"] as? Bool ?? false
    children = (params["children"] as? [[String: Any]] ?? [])
      .map(NativeNavigationBarMenuItem.init)
  }
}
