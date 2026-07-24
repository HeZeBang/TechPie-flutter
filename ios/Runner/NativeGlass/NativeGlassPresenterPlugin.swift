import Flutter
import QuartzCore
import SwiftUI
import UIKit

final class NativeGlassPresenterPlugin: NSObject, FlutterPlugin, UIGestureRecognizerDelegate {
  private enum PageTransitionMetrics {
    static let duration: TimeInterval = 0.35
    static let minimumSettleDuration: TimeInterval = 0.12
    static let parallax: CGFloat = 0.30
    static let shadowOpacity: Float = 0.16
    static let shadowRadius: CGFloat = 10
  }

  private static let channelName = "techpie/native_glass_presenter"
  private static let pageTransitionChannelName = "techpie/native_page_transition"
  private let channel: FlutterMethodChannel
  private let pageTransitionChannel: FlutterMethodChannel
  private var pageTransitionSource: UIImageView?
  private weak var pageTransitionRootView: UIView?
  private weak var pageTransitionWindow: UIWindow?
  private var pageTransitionDirection = "push"
  private var pageTransitionAnimating = false
  private var pageBackSnapshots: [UIImage] = []
  private weak var interactivePopGestureWindow: UIWindow?
  private var interactivePopGesture: UIPanGestureRecognizer?
  private var interactivePopSource: UIImageView?
  private var interactivePopDestination: UIImageView?
  private var interactivePopFrame = CGRect.zero
  private var interactivePopProgress: CGFloat = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let pageTransitionChannel = FlutterMethodChannel(
      name: pageTransitionChannelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = NativeGlassPresenterPlugin(
      channel: channel,
      pageTransitionChannel: pageTransitionChannel
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(
    channel: FlutterMethodChannel,
    pageTransitionChannel: FlutterMethodChannel
  ) {
    self.channel = channel
    self.pageTransitionChannel = pageTransitionChannel
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
    case "beginPageTransition":
      let arguments = call.arguments as? [String: Any] ?? [:]
      beginPageTransition(arguments: arguments, result: result)
    case "finishPageTransition":
      finishPageTransition(result: result)
    case "cancelPageTransition":
      cancelPageTransition()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginPageTransition(
    arguments: [String: Any],
    result: FlutterResult
  ) {
    guard !pageTransitionAnimating, interactivePopSource == nil else {
      result(
        FlutterError(
          code: "transition_in_progress",
          message: "A page transition is already in progress.",
          details: nil
        )
      )
      return
    }

    cancelPageTransition()

    guard
      let window = keyWindow(),
      let rootView = window.rootViewController?.view,
      let direction = arguments["direction"] as? String,
      let source = makePageSnapshot(of: rootView)
    else {
      result(
        FlutterError(
          code: "no_root_view",
          message: "Unable to find the root view for the page transition.",
          details: nil
        )
      )
      return
    }

    source.frame = rootView.convert(rootView.bounds, to: window)
    source.clipsToBounds = true
    source.isUserInteractionEnabled = true
    window.addSubview(source)

    pageTransitionSource = source
    pageTransitionRootView = rootView
    pageTransitionWindow = window
    pageTransitionDirection = direction
    result(nil)
  }

  private func finishPageTransition(result: FlutterResult) {
    guard
      let source = pageTransitionSource,
      let rootView = pageTransitionRootView,
      let window = pageTransitionWindow,
      let destination = makePageSnapshot(of: rootView)
    else {
      cancelPageTransition()
      result(nil)
      return
    }

    let frame = rootView.convert(rootView.bounds, to: window)
    let width = frame.width
    let isPop = pageTransitionDirection == "pop"
    let direction = horizontalDirection(in: rootView)

    destination.frame = frame
    destination.clipsToBounds = true
    destination.isUserInteractionEnabled = true

    if isPop {
      destination.frame.origin.x = frame.minX
        - width * PageTransitionMetrics.parallax * direction
      applyNavigationShadow(to: source, direction: direction)
      window.insertSubview(destination, belowSubview: source)
    } else {
      destination.frame.origin.x = frame.minX + width * direction
      applyNavigationShadow(to: destination, direction: direction)
      window.insertSubview(destination, aboveSubview: source)
    }

    if isPop {
      if !pageBackSnapshots.isEmpty {
        pageBackSnapshots.removeLast()
      }
    } else if let sourceImage = source.image {
      pageBackSnapshots.append(sourceImage)
      installInteractivePopGesture(in: window)
    }

    pageTransitionSource = nil
    pageTransitionRootView = nil
    pageTransitionWindow = nil
    pageTransitionAnimating = true

    let animator = UIViewPropertyAnimator(
      duration: PageTransitionMetrics.duration,
      curve: .easeInOut
    ) {
      source.frame.origin.x = isPop
        ? frame.minX + width * direction
        : frame.minX - width * PageTransitionMetrics.parallax * direction
      destination.frame = frame
    }
    animator.addCompletion { [weak self] _ in
      source.removeFromSuperview()
      destination.removeFromSuperview()
      self?.pageTransitionAnimating = false
    }
    animator.startAnimation()

    result(nil)
  }

  private func cancelPageTransition() {
    pageTransitionSource?.removeFromSuperview()
    pageTransitionSource = nil
    pageTransitionRootView = nil
    pageTransitionWindow = nil
  }

  private func makePageSnapshot(of view: UIView) -> UIImageView? {
    guard !view.bounds.isEmpty else { return nil }

    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
    let image = renderer.image { context in
      if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) {
        view.layer.render(in: context.cgContext)
      }
    }

    let imageView = UIImageView(image: image)
    imageView.contentMode = .scaleToFill
    return imageView
  }

  private func horizontalDirection(in view: UIView) -> CGFloat {
    view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
  }

  private func applyNavigationShadow(to view: UIView, direction: CGFloat) {
    view.layer.shadowColor = UIColor.black.cgColor
    view.layer.shadowOpacity = PageTransitionMetrics.shadowOpacity
    view.layer.shadowRadius = PageTransitionMetrics.shadowRadius
    view.layer.shadowOffset = CGSize(width: -3 * direction, height: 0)
  }

  private func installInteractivePopGesture(in window: UIWindow) {
    if interactivePopGestureWindow === window, interactivePopGesture != nil {
      return
    }

    if let gesture = interactivePopGesture {
      interactivePopGestureWindow?.removeGestureRecognizer(gesture)
    }

    let gesture = UIScreenEdgePanGestureRecognizer(
      target: self,
      action: #selector(handleInteractivePopGesture(_:))
    )
    gesture.edges = window.effectiveUserInterfaceLayoutDirection == .rightToLeft
      ? .right
      : .left
    gesture.delegate = self
    gesture.cancelsTouchesInView = true
    window.addGestureRecognizer(gesture)
    interactivePopGesture = gesture
    interactivePopGestureWindow = window
  }

  @objc private func handleInteractivePopGesture(
    _ gesture: UIPanGestureRecognizer
  ) {
    switch gesture.state {
    case .began:
      beginInteractivePop(gesture)
    case .changed:
      guard interactivePopSource != nil else { return }
      let width = max(interactivePopFrame.width, 1)
      let direction = horizontalDirection(in: gesture.view!)
      let progress = min(
        max(gesture.translation(in: gesture.view).x * direction / width, 0),
        1
      )
      updateInteractivePop(progress: progress)
    case .ended:
      guard interactivePopSource != nil else { return }
      let direction = horizontalDirection(in: gesture.view!)
      let velocity = gesture.velocity(in: gesture.view).x * direction
      settleInteractivePop(completes: interactivePopProgress > 0.5 || velocity > 700)
    case .cancelled, .failed:
      guard interactivePopSource != nil else { return }
      settleInteractivePop(completes: false)
    default:
      break
    }
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard
      let gesture = gestureRecognizer as? UIPanGestureRecognizer,
      gesture === interactivePopGesture,
      !pageTransitionAnimating,
      pageTransitionSource == nil,
      interactivePopSource == nil,
      !pageBackSnapshots.isEmpty
    else { return false }

    let direction = horizontalDirection(in: gesture.view!)
    let velocity = gesture.velocity(in: gesture.view)
    return velocity.x * direction > 0 && abs(velocity.x) > abs(velocity.y)
  }

  private func beginInteractivePop(_ gesture: UIPanGestureRecognizer) {
    guard
      !pageTransitionAnimating,
      pageTransitionSource == nil,
      interactivePopSource == nil,
      let previousImage = pageBackSnapshots.last,
      let window = gesture.view as? UIWindow ?? keyWindow(),
      let rootView = window.rootViewController?.view,
      let source = makePageSnapshot(of: rootView)
    else {
      gesture.isEnabled = false
      gesture.isEnabled = true
      return
    }

    let frame = rootView.convert(rootView.bounds, to: window)
    let direction = horizontalDirection(in: rootView)
    let destination = UIImageView(image: previousImage)
    destination.contentMode = .scaleToFill
    destination.clipsToBounds = true
    destination.isUserInteractionEnabled = true
    source.clipsToBounds = true
    source.isUserInteractionEnabled = true

    destination.frame = frame
    source.frame = frame
    applyNavigationShadow(to: source, direction: direction)

    window.addSubview(destination)
    window.addSubview(source)

    interactivePopSource = source
    interactivePopDestination = destination
    interactivePopFrame = frame
    updateInteractivePop(progress: 0)
  }

  private func updateInteractivePop(progress: CGFloat) {
    guard
      let source = interactivePopSource,
      let destination = interactivePopDestination
    else { return }

    let normalizedProgress = min(max(progress, 0), 1)
    let width = interactivePopFrame.width
    let direction = horizontalDirection(in: source)
    source.frame.origin.x = interactivePopFrame.minX
      + width * normalizedProgress * direction
    destination.frame.origin.x = interactivePopFrame.minX
      - width * PageTransitionMetrics.parallax * direction
      + width * PageTransitionMetrics.parallax * normalizedProgress * direction
    interactivePopProgress = normalizedProgress
  }

  private func settleInteractivePop(completes: Bool) {
    pageTransitionAnimating = true
    let remainingProgress = completes
      ? 1 - interactivePopProgress
      : interactivePopProgress
    let duration = max(
      PageTransitionMetrics.minimumSettleDuration,
      PageTransitionMetrics.duration * Double(remainingProgress)
    )

    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState]
    ) { [weak self] in
      self?.updateInteractivePop(progress: completes ? 1 : 0)
    } completion: { [weak self] _ in
      guard let self else { return }
      if completes {
        self.requestFlutterInteractivePop()
      } else {
        self.cleanupInteractivePop()
      }
    }
  }

  private func requestFlutterInteractivePop() {
    pageTransitionChannel.invokeMethod(
      "interactivePop",
      arguments: nil
    ) { [weak self] response in
      guard let self else { return }
      let didPop = (response as? NSNumber)?.boolValue ?? false

      if didPop {
        if !self.pageBackSnapshots.isEmpty {
          self.pageBackSnapshots.removeLast()
        }
        self.cleanupInteractivePop()
      } else {
        self.settleInteractivePop(completes: false)
      }
    }
  }

  private func cleanupInteractivePop() {
    interactivePopSource?.removeFromSuperview()
    interactivePopDestination?.removeFromSuperview()
    interactivePopSource = nil
    interactivePopDestination = nil
    interactivePopFrame = .zero
    interactivePopProgress = 0
    pageTransitionAnimating = false
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
