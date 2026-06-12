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

    rootView.addSubview(button)

    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
  }

  private func symbolImage() -> UIImage? {
    return UIImage(systemName: sfSymbol)?
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

    button.configuration = configuration
  }

  @available(iOS 15.0, *)
  private func applyModernFallbackAppearance(image: UIImage?) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = image

    button.configuration = configuration
  }

  private func applyLegacyFallbackAppearance(image: UIImage?) {
    button.setImage(image, for: .normal)
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

}
