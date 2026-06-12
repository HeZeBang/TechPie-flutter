import Flutter
import UIKit

final class NativeGlassConfirmationButtonFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeGlassConfirmationButtonPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeGlassConfirmationButtonPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_glass_confirmation_button"

  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let button = UIButton(type: .system)

  private var label: String?
  private var confirmTitle = "Are you sure?"
  private var confirmLabel = "Confirm"
  private var sfSymbol = "checkmark"
  private var destructive = false

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
    button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    rootView
  }

  private func parseArguments(_ args: Any?) {
    guard let params = args as? [String: Any] else { return }

    label = params["label"] as? String
    if let rawTitle = params["confirmTitle"] as? String, !rawTitle.isEmpty {
      confirmTitle = rawTitle
    }
    if let rawConfirmLabel = params["confirmLabel"] as? String, !rawConfirmLabel.isEmpty {
      confirmLabel = rawConfirmLabel
    }
    if let rawSymbol = params["sfSymbol"] as? String, !rawSymbol.isEmpty {
      sfSymbol = rawSymbol
    }
    destructive = params["destructive"] as? Bool ?? false
  }

  private func buildViewHierarchy() {
    rootView.backgroundColor = .clear
    rootView.clipsToBounds = false

    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityTraits.insert(.button)
    button.clipsToBounds = false
    if #available(iOS 26.0, *) {
      rootView.addSubview(button)

      NSLayoutConstraint.activate([
        button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        button.topAnchor.constraint(equalTo: rootView.topAnchor),
        button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      ])
      return
    }

    rootView.addSubview(button)

    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
  }

  private func applyButtonAppearance() {
    if #available(iOS 26.0, *) {
      applyLiquidGlassAppearance()
      return
    }

    let image = symbolImage(named: sfSymbol)

    if #available(iOS 15.0, *) {
      var configuration = UIButton.Configuration.plain()
      configuration.image = image
      configuration.title = label
      if destructive {
        configuration.baseForegroundColor = .systemRed
      }
      button.configuration = configuration
    } else {
      button.setImage(image, for: .normal)
      button.setTitle(label, for: .normal)
      if destructive {
        button.tintColor = .systemRed
        button.setTitleColor(.systemRed, for: .normal)
      }
    }
  }

  @available(iOS 26.0, *)
  private func applyLiquidGlassAppearance() {
    let image = symbolImage(named: sfSymbol)

    var configuration: UIButton.Configuration =
      label == nil || label?.isEmpty == true
      ? .clearGlass()
      : .glass()
    configuration.image = image
    configuration.title = label
    if destructive {
      configuration.baseForegroundColor = .systemRed
    }

    button.configuration = configuration
  }

  private func symbolImage(named systemName: String) -> UIImage? {
    return UIImage(systemName: systemName)?
      .withRenderingMode(.alwaysTemplate)
  }

  @objc
  private func handleTap() {
    guard let controller = nearestViewController() else {
      return
    }

    let actionSheet = UIAlertController(
      title: confirmTitle,
      message: nil,
      preferredStyle: .actionSheet
    )

    let confirmStyle: UIAlertAction.Style = destructive ? .destructive : .default
    actionSheet.addAction(
      UIAlertAction(title: confirmLabel, style: confirmStyle) { [weak self] _ in
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred(intensity: 0.55)
        self?.channel.invokeMethod("onConfirmed", arguments: nil)
      }
    )
    actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

    if let popover = actionSheet.popoverPresentationController {
      if #available(iOS 26.0, *) {
        popover.sourceItem = button
      } else {
        popover.sourceView = rootView
        popover.sourceRect = rootView.bounds
      }
    }

    controller.present(actionSheet, animated: true)
  }

  private func nearestViewController() -> UIViewController? {
    if let nextResponder = sequence(first: rootView.next, next: { $0?.next })
      .first(where: { $0 is UIViewController }) as? UIViewController
    {
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
