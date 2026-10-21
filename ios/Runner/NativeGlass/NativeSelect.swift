import Flutter
import UIKit

final class NativeSelectFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeSelectPlatformView(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }
}

final class NativeSelectPlatformView: NSObject, FlutterPlatformView {
  static let viewType = "techpie/native_select"

  private let rootView: UIView
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

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

    rootView.backgroundColor = .clear
    button.translatesAutoresizingMaskIntoConstraints = false
    button.showsMenuAsPrimaryAction = true
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    rootView.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    applyConfiguration(args)

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "updateConfiguration":
        self?.applyConfiguration(call.arguments)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { rootView }

  private func applyConfiguration(_ arguments: Any?) {
    let configuration = arguments as? [String: Any] ?? [:]
    let options = configuration["options"] as? [[String: Any]] ?? []
    let value = configuration["value"] as? String
    let selected = options.first { ($0["value"] as? String) == value }
    let title = selected?["label"] as? String ?? configuration["placeholder"] as? String ?? "Select"
    rootView.overrideUserInterfaceStyle = configuration["brightness"] as? String == "dark" ? .dark : .light

    var appearance: UIButton.Configuration
    if #available(iOS 26.0, *) {
      appearance = .glass()
    } else {
      appearance = .gray()
    }
    appearance.title = title
    appearance.baseForegroundColor = .label
    appearance.image = UIImage(systemName: "chevron.up.chevron.down")
    appearance.imagePlacement = .trailing
    appearance.imagePadding = 6
    appearance.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12)
    appearance.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10)
    appearance.titleLineBreakMode = .byTruncatingTail
    appearance.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
        for: UIFont.systemFont(ofSize: 15)
      )
      return attributes
    }
    button.configuration = appearance
    button.isEnabled = !options.isEmpty
    button.accessibilityLabel = configuration["accessibilityLabel"] as? String ?? "Select"
    button.accessibilityValue = title

    let actions = options.compactMap { option -> UIAction? in
      guard let optionValue = option["value"] as? String,
        let label = option["label"] as? String
      else { return nil }
      let image = (option["sfSymbol"] as? String).flatMap { UIImage(systemName: $0) }
      return UIAction(title: label, image: image, state: optionValue == value ? .on : .off) {
        [weak self] _ in
        self?.channel.invokeMethod("onChanged", arguments: ["value": optionValue])
      }
    }
    // UIKit owns the anchored menu's materials, checkmarks and dismissal.
    button.menu = UIMenu(options: .singleSelection, children: actions)
  }
}
