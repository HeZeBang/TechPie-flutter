import Flutter
import UIKit

final class NativeGlassDropdownMenuFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassDropdownMenuPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeGlassDropdownMenuPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_glass_dropdown_menu"

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let backgroundView = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let button = UIButton(type: .system)

  private var sfSymbol = "ellipsis"
  private var label: String?
  private var items: [NativeGlassDropdownMenuItem] = []

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

    parseArguments(args)
    buildViewHierarchy()
    applyButtonAppearance()
    rebuildMenu()

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
    guard let params = args as? [String: Any] else {
      return
    }

    if let rawSymbol = params["sfSymbol"] as? String, !rawSymbol.isEmpty {
      sfSymbol = rawSymbol
    }

    if let rawLabel = params["label"] as? String, !rawLabel.isEmpty {
      label = rawLabel
    } else {
      label = nil
    }

    if let rawItems = params["items"] as? [[String: Any]] {
      items = rawItems.compactMap(NativeGlassDropdownMenuItem.init)
    }
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear
    rootView.clipsToBounds = false

    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.clipsToBounds = true
    backgroundView.layer.cornerRadius = 18
    backgroundView.layer.borderWidth = 1
    backgroundView.layer.borderColor = NativeGlassColors.controlBorder.cgColor
    backgroundView.layer.shadowColor = UIColor.black.cgColor
    backgroundView.layer.shadowOpacity = 0.08
    backgroundView.layer.shadowRadius = 10
    backgroundView.layer.shadowOffset = CGSize(width: 0, height: 6)

    if #available(iOS 13.0, *) {
      backgroundView.layer.cornerCurve = .continuous
    }

    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = NativeGlassColors.floatingButtonForeground
    button.accessibilityTraits.insert(.button)

    rootView.addSubview(backgroundView)
    backgroundView.contentView.addSubview(button)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      button.leadingAnchor.constraint(equalTo: backgroundView.contentView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: backgroundView.contentView.trailingAnchor),
      button.topAnchor.constraint(equalTo: backgroundView.contentView.topAnchor),
      button.bottomAnchor.constraint(equalTo: backgroundView.contentView.bottomAnchor)
    ])
  }

  private func applyButtonAppearance() {
    let image = symbolImage(named: sfSymbol)

    if #available(iOS 15.0, *) {
      var configuration = UIButton.Configuration.plain()
      configuration.image = image
      configuration.title = label
      configuration.baseForegroundColor = NativeGlassColors.floatingButtonForeground
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 10,
        leading: 14,
        bottom: 10,
        trailing: 14
      )
      configuration.imagePadding = label == nil ? 0 : 8
      configuration.cornerStyle = .capsule
      button.configuration = configuration
    } else {
      button.setImage(image, for: .normal)
      button.setTitle(label, for: .normal)
      button.tintColor = NativeGlassColors.floatingButtonForeground
      button.setTitleColor(NativeGlassColors.floatingButtonForeground, for: .normal)
      button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
      button.titleEdgeInsets = label == nil
        ? .zero
        : UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
    }
  }

  private func rebuildMenu() {
    button.removeTarget(self, action: #selector(handleLegacyTap), for: .touchUpInside)

    if #available(iOS 14.0, *) {
      button.menu = UIMenu(children: items.compactMap(makeElement))
      button.showsMenuAsPrimaryAction = true
    } else {
      button.addTarget(self, action: #selector(handleLegacyTap), for: .touchUpInside)
    }
  }

  @available(iOS 14.0, *)
  private func makeElement(for item: NativeGlassDropdownMenuItem) -> UIMenuElement {
    if let children = item.children, !children.isEmpty {
      return UIMenu(
        title: item.title,
        options: [],
        children: children.compactMap(makeElement)
      )
    }

    return makeAction(for: item)
  }

  @available(iOS 14.0, *)
  private func makeAction(for item: NativeGlassDropdownMenuItem) -> UIAction {
    UIAction(
      title: item.title,
      attributes: item.destructive ? [.destructive] : [],
      state: item.checked ? .on : .off
    ) { [weak self] _ in
      self?.notifySelection(value: item.value)
    }
  }

  private func symbolImage(named systemName: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: 16,
      weight: .semibold,
      scale: .medium
    )

    return UIImage(systemName: systemName, withConfiguration: configuration)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateConfiguration":
      parseArguments(call.arguments)
      applyButtonAppearance()
      rebuildMenu()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func notifySelection(value: String) {
    let feedback = UIImpactFeedbackGenerator(style: .light)
    feedback.impactOccurred(intensity: 0.55)
    channel.invokeMethod("onSelect", arguments: ["value": value])
  }

  @objc
  private func handleLegacyTap() {
    guard !items.isEmpty, let controller = nearestViewController() else {
      return
    }

    let sheet = UIAlertController(title: label, message: nil, preferredStyle: .actionSheet)

    for item in items {
      let title = item.checked ? "✓ \(item.title)" : item.title
      let style: UIAlertAction.Style = item.destructive ? .destructive : .default
      sheet.addAction(
        UIAlertAction(title: title, style: style) { [weak self] _ in
          self?.notifySelection(value: item.value)
        }
      )
    }

    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

    if let popover = sheet.popoverPresentationController {
      popover.sourceView = rootView
      popover.sourceRect = rootView.bounds
    }

    controller.present(sheet, animated: true)
  }

  private func nearestViewController() -> UIViewController? {
    if let nextResponder = sequence(first: rootView.next, next: { $0?.next })
      .first(where: { $0 is UIViewController }) as? UIViewController {
      return nextResponder
    }

    let rootController = rootView.window?.rootViewController
    var topController = rootController

    while let presented = topController?.presentedViewController {
      topController = presented
    }

    return topController
  }
}

private struct NativeGlassDropdownMenuItem {
  let value: String
  let title: String
  let checked: Bool
  let destructive: Bool
  let children: [NativeGlassDropdownMenuItem]?

  init(
    value: String,
    title: String,
    checked: Bool,
    destructive: Bool,
    children: [NativeGlassDropdownMenuItem]?
  ) {
    self.value = value
    self.title = title
    self.checked = checked
    self.destructive = destructive
    self.children = children
  }

  init?(_ dictionary: [String: Any]) {
    guard
      let value = dictionary["value"] as? String,
      let title = dictionary["title"] as? String,
      !value.isEmpty,
      !title.isEmpty
    else {
      return nil
    }

    self.init(
      value: value,
      title: title,
      checked: dictionary["checked"] as? Bool ?? false,
      destructive: dictionary["destructive"] as? Bool ?? false,
      children: (dictionary["children"] as? [[String: Any]])?.compactMap(Self.init)
    )
  }
}
