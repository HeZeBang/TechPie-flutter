import Cocoa
import FlutterMacOS

/// Registers TechPie's pure AppKit native controls and modal/menu bridge on macOS
/// (macOS 12 through macOS 26+), avoiding cross-platform Material controls and
/// Flutter-drawn switches/segments/menus.
final class MacosNativeControlsPlugin: NSObject, FlutterPlugin {
  private static var activeUiBridges: [ObjectIdentifier: _MacosNativeUiBridge] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger

    let uiBridge = _MacosNativeUiBridge(messenger: messenger)
    activeUiBridges[ObjectIdentifier(uiBridge)] = uiBridge

    registrar.register(
      _MacosSwitchFactory(messenger: messenger),
      withId: "TechPieMacSwitch"
    )
    registrar.register(
      _MacosSegmentedControlFactory(messenger: messenger),
      withId: "TechPieMacSegmentedControl"
    )
    registrar.register(
      _MacosPopUpButtonFactory(messenger: messenger),
      withId: "TechPieMacPopUpButton"
    )
    registrar.register(
      _MacosSliderFactory(messenger: messenger),
      withId: "TechPieMacSlider"
    )
    registrar.register(
      _MacosCheckboxFactory(messenger: messenger),
      withId: "TechPieMacCheckbox"
    )
  }
}

// MARK: - Modal Alert & Context Menu MethodChannel Bridge

private final class _MacosNativeUiBridge: NSObject {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "techpie/macos_native_ui",
      binaryMessenger: messenger
    )
    super.init()
    self.channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showAlert":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing alert args", details: nil))
        return
      }
      showAlert(args: args, result: result)
    case "showContextMenu":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing menu args", details: nil))
        return
      }
      showContextMenu(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showAlert(args: [String: Any], result: @escaping FlutterResult) {
    let title = (args["title"] as? String) ?? ""
    let message = (args["message"] as? String) ?? ""
    let rawActions = (args["actions"] as? [[String: Any]]) ?? []

    struct IndexedAction {
      let index: Int
      let label: String
      let isDefault: Bool
      let isCancel: Bool
      let isDestructive: Bool
      let priority: Int
    }

    var indexed: [IndexedAction] = []
    for (idx, item) in rawActions.enumerated() {
      let label = ((item["label"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if label.isEmpty { continue }
      let isDefault = (item["isDefault"] as? NSNumber)?.boolValue ?? false
      let isCancel = (item["isCancel"] as? NSNumber)?.boolValue ?? false
      let isDestructive = (item["isDestructive"] as? NSNumber)?.boolValue ?? false
      // NSAlert places the first button added on the trailing (rightmost) edge.
      // Order: primary/default first (0), non-cancel secondary/destructive (1), cancel last (2).
      let priority = isDefault ? 0 : (isCancel ? 2 : 1)
      indexed.append(
        IndexedAction(
          index: idx,
          label: label,
          isDefault: isDefault,
          isCancel: isCancel,
          isDestructive: isDestructive,
          priority: priority
        )
      )
    }

    if indexed.isEmpty {
      indexed.append(
        IndexedAction(
          index: 0,
          label: "确定",
          isDefault: true,
          isCancel: false,
          isDestructive: false,
          priority: 0
        )
      )
    }

    indexed.sort { a, b in
      if a.priority != b.priority { return a.priority < b.priority }
      return a.index < b.index
    }

    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = title
      alert.informativeText = message
      let hasDestructive = indexed.contains { $0.isDestructive }
      alert.alertStyle = hasDestructive ? .warning : .informational

      var assignedCancel = false
      for entry in indexed {
        let button = alert.addButton(withTitle: entry.label)
        if entry.isDefault {
          button.keyEquivalent = "\r"
        } else if entry.isCancel && !assignedCancel {
          button.keyEquivalent = "\u{1b}"
          assignedCancel = true
        } else {
          button.keyEquivalent = ""
        }
        if #available(macOS 11.0, *), entry.isDestructive {
          button.hasDestructiveAction = true
        }
      }

      let finish: (NSApplication.ModalResponse) -> Void = { response in
        let buttonOffset = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if buttonOffset >= 0 && buttonOffset < indexed.count {
          result(["index": indexed[buttonOffset].index])
        } else {
          result(nil)
        }
      }

      if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
        alert.beginSheetModal(for: window, completionHandler: finish)
      } else {
        finish(alert.runModal())
      }
    }
  }

  private func showContextMenu(args: [String: Any], result: @escaping FlutterResult) {
    let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
    let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
    let items = (args["items"] as? [[String: Any]]) ?? []
    let isDark = (args["isDark"] as? NSNumber)?.boolValue ?? false

    DispatchQueue.main.async {
      guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
            let contentView = window.contentView else {
        result(nil)
        return
      }

      let target = _ContextMenuTarget()
      let menu = NSMenu()
      menu.autoenablesItems = false
      menu.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

      for (idx, raw) in items.enumerated() {
        let isDivider = (raw["isDivider"] as? NSNumber)?.boolValue ?? false
        if isDivider {
          menu.addItem(.separator())
          continue
        }
        let label = (raw["label"] as? String) ?? ""
        let enabled = (raw["enabled"] as? NSNumber)?.boolValue ?? true
        let checked = (raw["checked"] as? NSNumber)?.boolValue ?? false
        let destructive = (raw["destructive"] as? NSNumber)?.boolValue ?? false
        let sfSymbol = raw["sfSymbol"] as? String

        let item = NSMenuItem(
          title: label,
          action: #selector(_ContextMenuTarget.onSelect(_:)),
          keyEquivalent: ""
        )
        item.target = target
        item.tag = idx
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        if destructive {
          item.attributedTitle = NSAttributedString(
            string: label,
            attributes: [.foregroundColor: NSColor.systemRed]
          )
        }
        if let symbol = sfSymbol, !symbol.isEmpty {
          let tint: NSColor? = destructive ? .systemRed : nil
          item.image = _MacosShared.sfSymbolImage(named: symbol, size: 14, color: tint)
        }
        menu.addItem(item)
      }

      // Convert Flutter global coordinates (top-left origin in window content points) to contentView.
      let windowHeight = contentView.bounds.height
      let flippedY = contentView.isFlipped ? y : (windowHeight - y)
      let point = NSPoint(x: x, y: flippedY)

      menu.popUp(positioning: nil, at: point, in: contentView)
      DispatchQueue.main.async {
        result(target.selectedIndex)
      }
    }
  }
}

private final class _ContextMenuTarget: NSObject {
  var selectedIndex: Int?

  @objc func onSelect(_ sender: NSMenuItem) {
    selectedIndex = sender.tag
  }
}

// MARK: - Shared AppKit Helpers

private enum _MacosShared {
  static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
  }

  static func sfSymbolImage(named name: String, size: CGFloat? = nil, color: NSColor? = nil) -> NSImage? {
    guard !name.isEmpty, var image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
      return nil
    }
    if #available(macOS 12.0, *), let size = size, size > 0 {
      let sizeCfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
      image = image.withSymbolConfiguration(sizeCfg) ?? image
    }
    if #available(macOS 12.0, *), let color = color {
      let colorCfg = NSImage.SymbolConfiguration(hierarchicalColor: color)
      image = image.withSymbolConfiguration(colorCfg) ?? image
    }
    return image
  }
}

private class _TechPieAppKitContainerView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyAppearance(isDark: Bool) {
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
  }

  // Forward scroll wheel gestures back to Flutter so scrollable lists containing
  // AppKitView controls never stall when the pointer rests on a switch or picker.
  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }
}

// MARK: - TechPieMacSwitch (NSSwitch)

private final class _MacosSwitchFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    _MacosSwitchView(viewId: viewId, args: args, messenger: messenger)
  }
}

private final class _MacosSwitchView: _TechPieAppKitContainerView {
  private let channel: FlutterMethodChannel
  private let toggle: NSSwitch
  private var isUpdatingProgrammatically = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "TechPieMacSwitch_\(viewId)",
      binaryMessenger: messenger
    )
    self.toggle = NSSwitch()
    super.init(frame: .zero)

    var value = false
    var enabled = true
    var isDark = false
    var semanticLabel: String?

    if let dict = args as? [String: Any] {
      value = (dict["value"] as? NSNumber)?.boolValue ?? false
      enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
      isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
      semanticLabel = dict["semanticLabel"] as? String
    }

    applyAppearance(isDark: isDark)

    toggle.controlSize = .small
    toggle.state = value ? .on : .off
    toggle.isEnabled = enabled
    if let label = semanticLabel, !label.isEmpty {
      toggle.setAccessibilityLabel(label)
    }
    toggle.target = self
    toggle.action = #selector(onToggled(_:))
    toggle.translatesAutoresizingMaskIntoConstraints = false

    addSubview(toggle)
    NSLayoutConstraint.activate([
      toggle.centerXAnchor.constraint(equalTo: centerXAnchor),
      toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  @objc private func onToggled(_ sender: NSSwitch) {
    guard !isUpdatingProgrammatically else { return }
    channel.invokeMethod("valueChanged", arguments: ["value": sender.state == .on])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIntrinsicSize":
      let size = toggle.intrinsicContentSize
      result(["width": Double(size.width), "height": Double(size.height)])
    case "setValue":
      if let dict = call.arguments as? [String: Any],
         let val = (dict["value"] as? NSNumber)?.boolValue {
        isUpdatingProgrammatically = true
        toggle.state = val ? .on : .off
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing value", details: nil))
      }
    case "setEnabled":
      if let dict = call.arguments as? [String: Any],
         let enabled = (dict["enabled"] as? NSNumber)?.boolValue {
        toggle.isEnabled = enabled
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      toggle.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setBrightness":
      if let dict = call.arguments as? [String: Any],
         let isDark = (dict["isDark"] as? NSNumber)?.boolValue {
        applyAppearance(isDark: isDark)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      control.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setInteractive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - TechPieMacSegmentedControl (NSSegmentedControl)

private final class _MacosSegmentedControlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    _MacosSegmentedControlView(viewId: viewId, args: args, messenger: messenger)
  }
}

private final class _MacosSegmentedControlView: _TechPieAppKitContainerView {
  private let channel: FlutterMethodChannel
  private let control: NSSegmentedControl
  private var isUpdatingProgrammatically = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "TechPieMacSegmentedControl_\(viewId)",
      binaryMessenger: messenger
    )
    self.control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    super.init(frame: .zero)

    var labels: [String] = []
    var selectedIndex = 0
    var enabled = true
    var isDark = false
    var shrinkWrap = false

    if let dict = args as? [String: Any] {
      labels = (dict["labels"] as? [String]) ?? []
      selectedIndex = (dict["selectedIndex"] as? NSNumber)?.intValue ?? 0
      enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
      isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
      shrinkWrap = (dict["shrinkWrap"] as? NSNumber)?.boolValue ?? false
    }

    applyAppearance(isDark: isDark)
    control.segmentStyle = .automatic
    control.segmentDistribution = shrinkWrap ? .fit : .fillEqually
    configureLabels(labels, selectedIndex: selectedIndex)
    control.isEnabled = enabled
    control.target = self
    control.action = #selector(onChanged(_:))
    control.translatesAutoresizingMaskIntoConstraints = false

    addSubview(control)
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: leadingAnchor),
      control.trailingAnchor.constraint(equalTo: trailingAnchor),
      control.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func configureLabels(_ labels: [String], selectedIndex: Int) {
    isUpdatingProgrammatically = true
    control.segmentCount = labels.count
    for (idx, title) in labels.enumerated() {
      control.setLabel(title, forSegment: idx)
    }
    if selectedIndex >= 0 && selectedIndex < labels.count {
      control.selectedSegment = selectedIndex
    } else {
      control.selectedSegment = -1
    }
    isUpdatingProgrammatically = false
  }

  @objc private func onChanged(_ sender: NSSegmentedControl) {
    guard !isUpdatingProgrammatically else { return }
    let idx = sender.selectedSegment
    if idx >= 0 {
      channel.invokeMethod("valueChanged", arguments: ["index": idx])
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIntrinsicSize":
      let size = control.intrinsicContentSize
      result(["width": Double(size.width), "height": Double(size.height)])
    case "setLabels":
      if let dict = call.arguments as? [String: Any],
         let labels = dict["labels"] as? [String] {
        let selectedIndex = (dict["selectedIndex"] as? NSNumber)?.intValue ?? control.selectedSegment
        configureLabels(labels, selectedIndex: selectedIndex)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing labels", details: nil))
      }
    case "setSelectedIndex":
      if let dict = call.arguments as? [String: Any],
         let idx = (dict["index"] as? NSNumber)?.intValue {
        isUpdatingProgrammatically = true
        if idx >= 0 && idx < control.segmentCount {
          control.selectedSegment = idx
        } else {
          control.selectedSegment = -1
        }
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing index", details: nil))
      }
    case "setEnabled":
      if let dict = call.arguments as? [String: Any],
         let enabled = (dict["enabled"] as? NSNumber)?.boolValue {
        control.isEnabled = enabled
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil))
      }
    case "setBrightness":
      if let dict = call.arguments as? [String: Any],
         let isDark = (dict["isDark"] as? NSNumber)?.boolValue {
        applyAppearance(isDark: isDark)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      control.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setInteractive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - TechPieMacPopUpButton (NSPopUpButton)

private final class _MacosPopUpButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    _MacosPopUpButtonView(viewId: viewId, args: args, messenger: messenger)
  }
}

private final class _MacosPopUpButtonView: _TechPieAppKitContainerView {
  private let channel: FlutterMethodChannel
  private let button: NSPopUpButton
  private let pullsDown: Bool
  private var placeholder: String?
  private var buttonTitle: String?
  private var buttonIconName: String?
  private var isUpdatingProgrammatically = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let dict = args as? [String: Any]
    let pullsDown = (dict?["pullsDown"] as? NSNumber)?.boolValue ?? false
    self.pullsDown = pullsDown
    self.channel = FlutterMethodChannel(
      name: "TechPieMacPopUpButton_\(viewId)",
      binaryMessenger: messenger
    )
    self.button = NSPopUpButton(frame: .zero, pullsDown: pullsDown)
    super.init(frame: .zero)

    let enabled = (dict?["enabled"] as? NSNumber)?.boolValue ?? true
    let isDark = (dict?["isDark"] as? NSNumber)?.boolValue ?? false
    let borderless = (dict?["borderless"] as? NSNumber)?.boolValue ?? false
    let selectedIndex = (dict?["selectedIndex"] as? NSNumber)?.intValue ?? -1
    let items = (dict?["items"] as? [[String: Any]]) ?? []
    let semanticLabel = dict?["semanticLabel"] as? String
    self.placeholder = dict?["placeholder"] as? String
    self.buttonTitle = dict?["buttonTitle"] as? String
    self.buttonIconName = dict?["buttonIconName"] as? String

    applyAppearance(isDark: isDark)

    button.autoenablesItems = false
    button.menu?.autoenablesItems = false
    button.isEnabled = enabled
    if borderless {
      button.isBordered = false
    } else if pullsDown {
      button.bezelStyle = .texturedRounded
    }
    if let label = semanticLabel, !label.isEmpty {
      button.setAccessibilityLabel(label)
    }

    rebuildItems(items, selectedIndex: selectedIndex)

    button.target = self
    button.action = #selector(onSelectionChanged(_:))
    button.translatesAutoresizingMaskIntoConstraints = false

    addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func rebuildItems(_ items: [[String: Any]], selectedIndex: Int) {
    isUpdatingProgrammatically = true
    button.removeAllItems()

    guard let menu = button.menu else {
      isUpdatingProgrammatically = false
      return
    }
    menu.autoenablesItems = false

    if pullsDown {
      // NSPopUpButton in pullsDown mode uses index 0 as the button header item.
      let headerTitle = (buttonIconName != nil && (buttonTitle?.isEmpty ?? true)) ? "" : (buttonTitle ?? "")
      let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
      if let iconName = buttonIconName, !iconName.isEmpty {
        header.image = _MacosShared.sfSymbolImage(named: iconName, size: 15)
        if headerTitle.isEmpty {
          button.imagePosition = .imageOnly
          if let cell = button.cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
          }
        }
      }
      menu.addItem(header)
    } else if selectedIndex < 0 {
      let emptyTitle = (placeholder?.isEmpty == false) ? placeholder! : " "
      let placeholderItem = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
      placeholderItem.tag = -1
      placeholderItem.isEnabled = false
      menu.addItem(placeholderItem)
    }

    for (idx, raw) in items.enumerated() {
      let isDivider = (raw["isDivider"] as? NSNumber)?.boolValue ?? false
      if isDivider {
        menu.addItem(.separator())
        continue
      }
      let label = (raw["label"] as? String) ?? ""
      let itemEnabled = (raw["enabled"] as? NSNumber)?.boolValue ?? true
      let checked = (raw["checked"] as? NSNumber)?.boolValue ?? false
      let destructive = (raw["isDestructive"] as? NSNumber)?.boolValue ?? false
      let sfSymbol = raw["sfSymbol"] as? String

      let menuItem = NSMenuItem(
        title: label,
        action: pullsDown ? #selector(onPullDownMenuItem(_:)) : nil,
        keyEquivalent: ""
      )
      if pullsDown {
        menuItem.target = self
      }
      menuItem.tag = idx
      menuItem.isEnabled = itemEnabled
      menuItem.state = checked ? .on : .off
      if destructive {
        menuItem.attributedTitle = NSAttributedString(
          string: label,
          attributes: [.foregroundColor: NSColor.systemRed]
        )
      }
      if let symbol = sfSymbol, !symbol.isEmpty {
        menuItem.image = _MacosShared.sfSymbolImage(
          named: symbol,
          size: 14,
          color: destructive ? .systemRed : nil
        )
      }
      menu.addItem(menuItem)
    }

    if !pullsDown {
      if selectedIndex >= 0, button.indexOfItem(withTag: selectedIndex) >= 0 {
        button.selectItem(withTag: selectedIndex)
      } else if button.indexOfItem(withTag: -1) >= 0 {
        button.selectItem(withTag: -1)
      }
    }

    isUpdatingProgrammatically = false
  }

  @objc private func onPullDownMenuItem(_ sender: NSMenuItem) {
    guard !isUpdatingProgrammatically, sender.tag >= 0 else { return }
    channel.invokeMethod("itemSelected", arguments: ["index": sender.tag])
  }

  @objc private func onSelectionChanged(_ sender: NSPopUpButton) {
    guard !isUpdatingProgrammatically, !pullsDown else { return }
    guard let selected = sender.selectedItem, selected.tag >= 0 else { return }
    channel.invokeMethod("itemSelected", arguments: ["index": selected.tag])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIntrinsicSize":
      let size = button.intrinsicContentSize
      result(["width": Double(size.width), "height": Double(size.height)])
    case "setItems":
      if let dict = call.arguments as? [String: Any] {
        let items = (dict["items"] as? [[String: Any]]) ?? []
        let selectedIndex = (dict["selectedIndex"] as? NSNumber)?.intValue ?? -1
        if let ph = dict["placeholder"] as? String {
          placeholder = ph
        }
        if let t = dict["buttonTitle"] as? String {
          buttonTitle = t
        }
        rebuildItems(items, selectedIndex: selectedIndex)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
      }
    case "setSelectedIndex":
      if let dict = call.arguments as? [String: Any],
         let idx = (dict["index"] as? NSNumber)?.intValue,
         !pullsDown {
        isUpdatingProgrammatically = true
        if idx >= 0 && button.indexOfItem(withTag: idx) >= 0 {
          button.selectItem(withTag: idx)
        }
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(nil)
      }
    case "setEnabled":
      if let dict = call.arguments as? [String: Any],
         let enabled = (dict["enabled"] as? NSNumber)?.boolValue {
        button.isEnabled = enabled
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      button.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setBrightness":
      if let dict = call.arguments as? [String: Any],
         let isDark = (dict["isDark"] as? NSNumber)?.boolValue {
        applyAppearance(isDark: isDark)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      control.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setInteractive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - TechPieMacSlider (NSSlider)

private final class _MacosSliderFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    _MacosSliderView(viewId: viewId, args: args, messenger: messenger)
  }
}

private final class _MacosSliderView: _TechPieAppKitContainerView {
  private let channel: FlutterMethodChannel
  private let slider: NSSlider
  private var stepValue: Double?
  private var isUpdatingProgrammatically = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "TechPieMacSlider_\(viewId)",
      binaryMessenger: messenger
    )
    self.slider = NSSlider()
    super.init(frame: .zero)

    var minVal = 0.0
    var maxVal = 1.0
    var value = 0.0
    var enabled = true
    var isDark = false
    var step: Double?
    var semanticLabel: String?

    if let dict = args as? [String: Any] {
      minVal = (dict["min"] as? NSNumber)?.doubleValue ?? 0.0
      maxVal = (dict["max"] as? NSNumber)?.doubleValue ?? 1.0
      value = (dict["value"] as? NSNumber)?.doubleValue ?? minVal
      enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
      isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
      step = (dict["step"] as? NSNumber)?.doubleValue
      semanticLabel = dict["semanticLabel"] as? String
    }

    applyAppearance(isDark: isDark)
    slider.isContinuous = true
    slider.minValue = minVal
    slider.maxValue = max(minVal, maxVal)
    slider.doubleValue = min(max(value, minVal), max(minVal, maxVal))
    slider.isEnabled = enabled
    configureStep(step)
    if let label = semanticLabel, !label.isEmpty {
      slider.setAccessibilityLabel(label)
    }

    slider.target = self
    slider.action = #selector(onSliderChanged(_:))
    slider.translatesAutoresizingMaskIntoConstraints = false

    addSubview(slider)
    NSLayoutConstraint.activate([
      slider.leadingAnchor.constraint(equalTo: leadingAnchor),
      slider.trailingAnchor.constraint(equalTo: trailingAnchor),
      slider.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func configureStep(_ step: Double?) {
    guard let step = step, step > 0, slider.maxValue > slider.minValue else {
      self.stepValue = nil
      slider.numberOfTickMarks = 0
      slider.allowsTickMarkValuesOnly = false
      return
    }
    self.stepValue = step
    let count = Int(round((slider.maxValue - slider.minValue) / step)) + 1
    if count >= 2 && count <= 25 {
      slider.numberOfTickMarks = count
      slider.allowsTickMarkValuesOnly = true
    } else {
      slider.numberOfTickMarks = 0
      slider.allowsTickMarkValuesOnly = false
    }
  }

  @objc private func onSliderChanged(_ sender: NSSlider) {
    guard !isUpdatingProgrammatically else { return }
    var val = sender.doubleValue
    if let step = stepValue, step > 0 {
      let steps = round((val - slider.minValue) / step)
      val = min(max(slider.minValue + steps * step, slider.minValue), slider.maxValue)
    }
    channel.invokeMethod("valueChanged", arguments: ["value": val])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setValue":
      if let dict = call.arguments as? [String: Any],
         let val = (dict["value"] as? NSNumber)?.doubleValue {
        isUpdatingProgrammatically = true
        slider.doubleValue = min(max(val, slider.minValue), slider.maxValue)
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing value", details: nil))
      }
    case "setRange":
      if let dict = call.arguments as? [String: Any],
         let minVal = (dict["min"] as? NSNumber)?.doubleValue,
         let maxVal = (dict["max"] as? NSNumber)?.doubleValue {
        isUpdatingProgrammatically = true
        slider.minValue = minVal
        slider.maxValue = max(minVal, maxVal)
        slider.doubleValue = min(max(slider.doubleValue, minVal), max(minVal, maxVal))
        configureStep(stepValue)
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing range", details: nil))
      }
    case "setStep":
      let step = (call.arguments as? [String: Any])?["step"] as? NSNumber
      configureStep(step?.doubleValue)
      result(nil)
    case "setEnabled":
      if let dict = call.arguments as? [String: Any],
         let enabled = (dict["enabled"] as? NSNumber)?.boolValue {
        slider.isEnabled = enabled
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      slider.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setBrightness":
      if let dict = call.arguments as? [String: Any],
         let isDark = (dict["isDark"] as? NSNumber)?.boolValue {
        applyAppearance(isDark: isDark)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      control.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setInteractive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - TechPieMacCheckbox (NSButton CheckBox)

private final class _MacosCheckboxFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    _MacosCheckboxView(viewId: viewId, args: args, messenger: messenger)
  }
}

private final class _MacosCheckboxView: _TechPieAppKitContainerView {
  private let channel: FlutterMethodChannel
  private let checkbox: NSButton
  private var isUpdatingProgrammatically = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "TechPieMacCheckbox_\(viewId)",
      binaryMessenger: messenger
    )
    self.checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    super.init(frame: .zero)

    var value = false
    var enabled = true
    var isDark = false
    var semanticLabel: String?

    if let dict = args as? [String: Any] {
      value = (dict["value"] as? NSNumber)?.boolValue ?? false
      enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
      isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
      semanticLabel = dict["semanticLabel"] as? String
    }

    applyAppearance(isDark: isDark)
    checkbox.allowsMixedState = false
    checkbox.controlSize = .regular
    checkbox.state = value ? .on : .off
    checkbox.isEnabled = enabled
    if let label = semanticLabel, !label.isEmpty {
      checkbox.setAccessibilityLabel(label)
    }
    checkbox.target = self
    checkbox.action = #selector(onToggled(_:))
    checkbox.translatesAutoresizingMaskIntoConstraints = false

    addSubview(checkbox)
    NSLayoutConstraint.activate([
      checkbox.centerXAnchor.constraint(equalTo: centerXAnchor),
      checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  @objc private func onToggled(_ sender: NSButton) {
    guard !isUpdatingProgrammatically else { return }
    channel.invokeMethod("valueChanged", arguments: ["value": sender.state == .on])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIntrinsicSize":
      let size = checkbox.intrinsicContentSize
      result(["width": Double(size.width), "height": Double(size.height)])
    case "setValue":
      if let dict = call.arguments as? [String: Any],
         let val = (dict["value"] as? NSNumber)?.boolValue {
        isUpdatingProgrammatically = true
        checkbox.state = val ? .on : .off
        isUpdatingProgrammatically = false
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing value", details: nil))
      }
    case "setEnabled":
      if let dict = call.arguments as? [String: Any],
         let enabled = (dict["enabled"] as? NSNumber)?.boolValue {
        checkbox.isEnabled = enabled
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      checkbox.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setBrightness":
      if let dict = call.arguments as? [String: Any],
         let isDark = (dict["isDark"] as? NSNumber)?.boolValue {
        applyAppearance(isDark: isDark)
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
      }
    case "setSemanticLabel":
      let label = (call.arguments as? [String: Any])?["label"] as? String
      control.setAccessibilityLabel((label?.isEmpty ?? true) ? nil : label)
      result(nil)
    case "setInteractive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
