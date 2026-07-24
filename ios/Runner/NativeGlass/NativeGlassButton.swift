import Flutter
import UIKit

final class NativeGlassButtonFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassButtonPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeGlassButtonPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_glass_button"

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let button = UIButton(type: .system)

  private var sfSymbol = "plus"
  private var label: String?
  private var subtitle: String?
  private var role = "standard"
  private var isEnabled = true
  private var isLoading = false
  private var showsIcon = true
  private var buttonAccessibilityLabel: String?

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

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func view() -> UIView {
    rootView
  }

  private func parseArguments(_ args: Any?) {
    guard let params = args as? [String: Any] else { return }
    if let rawSymbol = params["sfSymbol"] as? String, !rawSymbol.isEmpty {
      sfSymbol = rawSymbol
    }
    label = params["label"] as? String
    subtitle = params["subtitle"] as? String
    role = params["role"] as? String ?? "standard"
    isEnabled = params["enabled"] as? Bool ?? true
    isLoading = params["loading"] as? Bool ?? false
    buttonAccessibilityLabel = params["accessibilityLabel"] as? String
    showsIcon = (params["showsIcon"] as? Bool) ?? (label == nil)
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

    rootView.addSubview(button)

    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
  }

  private func symbolImage() -> UIImage? {
    guard showsIcon else { return nil }
    let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    return UIImage(systemName: sfSymbol, withConfiguration: configuration)?
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
    button.isEnabled = isEnabled && !isLoading
    button.accessibilityLabel = buttonAccessibilityLabel ?? label
  }

  @available(iOS 26.0, *)
  private func applyLiquidGlassAppearance(image: UIImage?) {
    var configuration: UIButton.Configuration
    switch role {
    case "prominent":
      configuration = .prominentGlass()
    case "plain":
      configuration = .plain()
    default:
      configuration = .glass()
    }
    configure(&configuration, image: image)
    if role == "destructive" {
      configuration.baseForegroundColor = .systemRed
    }
    button.configuration = configuration
  }

  @available(iOS 15.0, *)
  private func applyModernFallbackAppearance(image: UIImage?) {
    var configuration: UIButton.Configuration
    switch role {
    case "prominent":
      configuration = .filled()
    case "standard":
      configuration = .tinted()
    default:
      configuration = .plain()
    }
    configure(&configuration, image: image)
    if role == "destructive" {
      configuration.baseForegroundColor = .systemRed
    }
    button.configuration = configuration
  }

  private func applyLegacyFallbackAppearance(image: UIImage?) {
    button.setImage(image, for: .normal)
    button.setTitle(label, for: .normal)
    button.tintColor = role == "destructive" ? .systemRed : nil
  }

  @available(iOS 15.0, *)
  private func configure(_ configuration: inout UIButton.Configuration, image: UIImage?) {
    configuration.title = label
    configuration.subtitle = subtitle
    configuration.image = image
    configuration.imagePlacement = .leading
    configuration.imagePadding = label == nil ? 0 : 6
    configuration.showsActivityIndicator = isLoading
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 9,
      leading: label == nil ? 9 : 16,
      bottom: 9,
      trailing: label == nil ? 9 : 16
    )
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateConfiguration":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected a button configuration dictionary.",
            details: nil
          )
        )
        return
      }

      parseArguments(arguments)
      applyButtonAppearance()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc
  private func handleTap() {
    channel.invokeMethod("onTap", arguments: nil)
  }

}
