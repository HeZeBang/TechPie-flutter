import Flutter
import UIKit

final class NativeGlassSelectFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassSelectPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeGlassSelectPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_glass_select"

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let backgroundView = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let button = UIButton(type: .system)

  private var placeholder = "Select"
  private var sfSymbol = "chevron.up.chevron.down"
  private var selectedValue: String?
  private var options: [NativeGlassSelectOption] = []

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

    if let rawPlaceholder = params["placeholder"] as? String, !rawPlaceholder.isEmpty {
      placeholder = rawPlaceholder
    }

    if let rawSymbol = params["sfSymbol"] as? String, !rawSymbol.isEmpty {
      sfSymbol = rawSymbol
    }

    if let rawSelectedValue = params["value"] as? String, !rawSelectedValue.isEmpty {
      selectedValue = rawSelectedValue
    } else {
      selectedValue = nil
    }

    if let rawOptions = params["options"] as? [[String: Any]] {
      options = rawOptions.compactMap(NativeGlassSelectOption.init)
    }
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear

    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.clipsToBounds = true
    backgroundView.layer.cornerRadius = 16
    backgroundView.layer.borderWidth = 1
    backgroundView.layer.borderColor = NativeGlassColors.controlBorder.cgColor
    backgroundView.layer.shadowColor = UIColor.black.cgColor
    backgroundView.layer.shadowOpacity = 0.06
    backgroundView.layer.shadowRadius = 8
    backgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)

    if #available(iOS 13.0, *) {
      backgroundView.layer.cornerCurve = .continuous
    }

    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = NativeGlassColors.floatingButtonForeground
    button.semanticContentAttribute = .forceRightToLeft
    button.contentHorizontalAlignment = .fill
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

  private var selectedLabel: String {
    if let selectedValue, let option = options.first(where: { $0.value == selectedValue }) {
      return option.label
    }

    return placeholder
  }

  private func applyButtonAppearance() {
    let image = symbolImage(named: sfSymbol)

    if #available(iOS 15.0, *) {
      var configuration = UIButton.Configuration.plain()
      configuration.image = image
      configuration.title = selectedLabel
      configuration.baseForegroundColor = NativeGlassColors.floatingButtonForeground
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 10,
        leading: 14,
        bottom: 10,
        trailing: 14
      )
      configuration.imagePadding = 8
      configuration.cornerStyle = .capsule
      button.configuration = configuration
    } else {
      button.setImage(image, for: .normal)
      button.setTitle(selectedLabel, for: .normal)
      button.tintColor = NativeGlassColors.floatingButtonForeground
      button.setTitleColor(NativeGlassColors.floatingButtonForeground, for: .normal)
      button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
      button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
    }
  }

  private func rebuildMenu() {
    button.removeTarget(self, action: #selector(handleLegacyTap), for: .touchUpInside)

    if #available(iOS 14.0, *) {
      button.menu = UIMenu(children: options.map(makeAction))
      button.showsMenuAsPrimaryAction = true
    } else {
      button.addTarget(self, action: #selector(handleLegacyTap), for: .touchUpInside)
    }
  }

  @available(iOS 14.0, *)
  private func makeAction(for option: NativeGlassSelectOption) -> UIAction {
    UIAction(
      title: option.label,
      state: option.value == selectedValue ? .on : .off
    ) { [weak self] _ in
      self?.setSelectedValue(option.value, notifyFlutter: true)
    }
  }

  private func symbolImage(named systemName: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: 14,
      weight: .semibold,
      scale: .medium
    )

    return UIImage(systemName: systemName, withConfiguration: configuration)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateSelection":
      guard
        let arguments = call.arguments as? [String: Any],
        let value = arguments["value"] as? String,
        !value.isEmpty
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected a non-empty value string.",
            details: nil
          )
        )
        return
      }

      setSelectedValue(value, notifyFlutter: false)
      result(nil)

    case "updateConfiguration":
      parseArguments(call.arguments)
      applyButtonAppearance()
      rebuildMenu()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setSelectedValue(_ value: String, notifyFlutter: Bool) {
    selectedValue = value
    applyButtonAppearance()
    rebuildMenu()

    if notifyFlutter {
      let feedback = UIImpactFeedbackGenerator(style: .light)
      feedback.impactOccurred(intensity: 0.55)
      channel.invokeMethod("onChanged", arguments: ["value": value])
    }
  }

  @objc
  private func handleLegacyTap() {
    guard !options.isEmpty, let controller = nearestViewController() else {
      return
    }

    let sheet = UIAlertController(title: placeholder, message: nil, preferredStyle: .actionSheet)

    for option in options {
      let title = option.value == selectedValue ? "✓ \(option.label)" : option.label
      sheet.addAction(
        UIAlertAction(title: title, style: .default) { [weak self] _ in
          self?.setSelectedValue(option.value, notifyFlutter: true)
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

private struct NativeGlassSelectOption {
  let value: String
  let label: String

  init(value: String, label: String) {
    self.value = value
    self.label = label
  }

  init?(_ dictionary: [String: Any]) {
    guard
      let value = dictionary["value"] as? String,
      let label = dictionary["label"] as? String,
      !value.isEmpty,
      !label.isEmpty
    else {
      return nil
    }

    self.init(value: value, label: label)
  }
}
