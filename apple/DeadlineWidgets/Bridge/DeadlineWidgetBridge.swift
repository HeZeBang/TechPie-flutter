import Foundation
import WidgetKit
import DeadlineWidgetSupport
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class DeadlineWidgetBridge {
  private var channel: FlutterMethodChannel?
  private var pending = false
  private let queue = DispatchQueue(label: "club.geekpie.techpie.deadline-widgets")

  func configure(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(name: "techpie/deadline_widgets", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "consumePendingRoute": result(self.pending)
      case "acknowledgePendingRoute": self.pending = false; result(nil)
      case "publish", "clear":
        self.queue.async {
          do {
            guard let store = DeadlineSnapshotStore.configured() else { throw DeadlineSnapshot.SnapshotError.invalidData }
            let changed: Bool
            if call.method == "clear" { changed = try store.clear() }
            else {
              guard let json = call.arguments as? String, let data = json.data(using: .utf8) else { throw DeadlineSnapshot.SnapshotError.invalidData }
              changed = try store.write(data)
            }
            if changed, #available(macOS 11.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: "DeadlineWidget") }
            DispatchQueue.main.async { result(nil) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "DEADLINE_WIDGET_STORAGE_UNAVAILABLE", message: "Cannot update deadline widget data.", details: nil)) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult func capture(_ url: URL) -> Bool {
    let scheme = Bundle.main.object(forInfoDictionaryKey: "TechPieWidgetURLScheme") as? String ?? "techpie"
    guard url.scheme?.lowercased() == scheme.lowercased(), url.host?.lowercased() == "deadlines",
      url.path.isEmpty || url.path == "/" else { return false }
    pending = true
    channel?.invokeMethod("openDeadlines", arguments: nil)
    return true
  }
}
