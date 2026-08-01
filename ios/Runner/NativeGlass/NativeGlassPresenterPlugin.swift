import Flutter
import SwiftUI
import UIKit

final class NativeGlassPresenterPlugin: NSObject, FlutterPlugin {
  private static let channelName = "techpie/native_glass_presenter"
  private let channel: FlutterMethodChannel

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = NativeGlassPresenterPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showAlert":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected a dictionary of alert arguments.",
            details: nil
          )
        )
        return
      }

      showAlert(arguments: arguments, result: result)
    case "presentLoginSheet":
      let arguments = call.arguments as? [String: Any] ?? [:]
      presentLoginSheet(arguments: arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showAlert(arguments: [String: Any], result: @escaping FlutterResult) {
    guard
      let title = arguments["title"] as? String,
      let message = arguments["message"] as? String,
      let rawActions = arguments["actions"] as? [[String: Any]],
      let presenter = topViewController()
    else {
      result(
        FlutterError(
          code: "bad_args",
          message: "Missing title, message, actions, or presenter.",
          details: nil
        )
      )
      return
    }

    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    var preferredAction: UIAlertAction?
    var didComplete = false

    func complete(_ value: Any?) {
      guard !didComplete else { return }
      didComplete = true
      result(value)
    }

    for (index, actionData) in rawActions.enumerated() {
      guard let label = actionData["label"] as? String, !label.isEmpty else {
        continue
      }

      let isDestructive = actionData["isDestructive"] as? Bool ?? false
      let isDefault = actionData["isDefault"] as? Bool ?? false
      let style: UIAlertAction.Style = isDestructive ? .destructive : .default

      let action = UIAlertAction(title: label, style: style) { _ in
        complete(index)
      }

      if isDefault {
        preferredAction = action
      }

      alert.addAction(action)
    }

    if alert.actions.isEmpty {
      alert.addAction(
        UIAlertAction(title: "OK", style: .default) { _ in
          complete(nil)
        })
    }

    if let preferredAction {
      alert.preferredAction = preferredAction
    }

    presenter.present(alert, animated: true)
  }

  private func presentLoginSheet(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 26.0, *) else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Native login sheet requires iOS 26.",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "no_presenter",
          message: "Unable to find a presenter for login sheet.",
          details: nil
        )
      )
      return
    }

    let copy = NativeLoginSheetCopy(
      pageTitle: arguments["pageTitle"] as? String ?? "登录",
      brandName: arguments["brandName"] as? String ?? "TechPie",
      subtitle: arguments["subtitle"] as? String ?? "登录以访问校园服务"
    )

    var didComplete = false
    func complete() {
      guard !didComplete else { return }
      didComplete = true
      result(nil)
    }

    let controller = NativeLoginSheetHostingController(
      copy: copy,
      channel: channel,
      onDismiss: complete
    )
    controller.modalPresentationStyle = .pageSheet

    if let sheet = controller.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.selectedDetentIdentifier = .large
      sheet.prefersGrabberVisible = false
      sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    }

    presenter.present(controller, animated: true)
  }

  private func topViewController() -> UIViewController? {
    var topController = keyWindow()?.rootViewController

    while let presented = topController?.presentedViewController {
      topController = presented
    }

    return topController
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
  }
}

private struct NativeLoginSheetCopy {
  let pageTitle: String
  let brandName: String
  let subtitle: String
}

@available(iOS 26.0, *)
private final class NativeLoginSheetHostingController: UIHostingController<NativeLoginSheetView> {
  private let model: NativeLoginSheetModel
  private let onDismiss: () -> Void
  private var didNotifyDismiss = false

  init(
    copy: NativeLoginSheetCopy,
    channel: FlutterMethodChannel,
    onDismiss: @escaping () -> Void
  ) {
    let model = NativeLoginSheetModel(copy: copy, channel: channel)
    self.model = model
    self.onDismiss = onDismiss
    super.init(rootView: NativeLoginSheetView(model: model))
    model.dismiss = { [weak self] in
      self?.dismiss(animated: true)
    }
  }

  @MainActor
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    model.invalidate()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    isModalInPresentation = false
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    if isBeingDismissed || presentingViewController == nil {
      notifyDismiss()
    }
  }

  private func notifyDismiss() {
    guard !didNotifyDismiss else { return }
    didNotifyDismiss = true
    model.invalidate()
    onDismiss()
  }
}

@available(iOS 26.0, *)
private final class NativeLoginSheetModel: ObservableObject {
  private let copy: NativeLoginSheetCopy
  private let channel: FlutterMethodChannel
  var dismiss: (() -> Void)?

  @Published var feedback: String?
  @Published var isLoggingIn = false

  init(
    copy: NativeLoginSheetCopy,
    channel: FlutterMethodChannel
  ) {
    self.copy = copy
    self.channel = channel
  }

  func invalidate() {}

  var title: String {
    copy.brandName
  }

  var subtitle: String {
    copy.subtitle
  }

  var loginButtonTitle: String {
    copy.pageTitle
  }

  func geekpieLogin() {
    isLoggingIn = true
    channel.invokeMethod(
      "nativeLoginSheet.geekpieLogin",
      arguments: [:]
    ) { [weak self] response in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isLoggingIn = false
        self.handleResponse(response) {
          self.dismiss?()
        }
      }
    }
  }

  private func handleResponse(_ response: Any?, success: () -> Void) {
    guard let payload = response as? [String: Any] else {
      feedback = "操作失败，请稍后重试"
      return
    }

    if payload["ok"] as? Bool == true {
      feedback = nil
      success()
      return
    }

    feedback = payload["message"] as? String ?? "操作失败，请稍后重试"
  }
}

@available(iOS 26.0, *)
private struct NativeLoginSheetView: View {
  @ObservedObject var model: NativeLoginSheetModel

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(model.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Section {
          Button {
            model.geekpieLogin()
          } label: {
            HStack {
              Spacer()
              if model.isLoggingIn {
                ProgressView()
              }
              Text(model.loginButtonTitle)
              Spacer()
            }
          }
          .disabled(model.isLoggingIn)
        }

        if let feedback = model.feedback {
          Section {
            Text(feedback)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(model.title)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.dismiss?()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("关闭")
        }
      }
    }
  }
}
