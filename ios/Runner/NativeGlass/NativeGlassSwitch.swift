import Flutter
import UIKit

final class NativeGlassSwitchFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassSwitchPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeGlassSwitchPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_glass_switch"

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let toggle = UISwitch(frame: .zero)

  private var isOn = false
  private var isEnabled = true

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
    applyState(animated: false)

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

    isOn = params["value"] as? Bool ?? isOn
    isEnabled = params["enabled"] as? Bool ?? isEnabled
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear

    toggle.translatesAutoresizingMaskIntoConstraints = false
    toggle.onTintColor = NativeGlassColors.selectedBlue
    toggle.addTarget(self, action: #selector(handleValueChanged), for: .valueChanged)

    rootView.addSubview(toggle)

    NSLayoutConstraint.activate([
      toggle.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
      toggle.centerYAnchor.constraint(equalTo: rootView.centerYAnchor)
    ])
  }

  private func applyState(animated: Bool) {
    toggle.setOn(isOn, animated: animated)
    toggle.isEnabled = isEnabled
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateValue":
      guard
        let arguments = call.arguments as? [String: Any],
        let value = arguments["value"] as? Bool
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected a boolean value.",
            details: nil
          )
        )
        return
      }

      isOn = value
      applyState(animated: true)
      result(nil)

    case "updateEnabled":
      guard
        let arguments = call.arguments as? [String: Any],
        let enabled = arguments["enabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected an enabled boolean.",
            details: nil
          )
        )
        return
      }

      isEnabled = enabled
      applyState(animated: false)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc
  private func handleValueChanged() {
    isOn = toggle.isOn

    let feedback = UIImpactFeedbackGenerator(style: .light)
    feedback.impactOccurred(intensity: 0.5)

    channel.invokeMethod("onChanged", arguments: ["value": isOn])
  }
}
