import Foundation
import WidgetKit
import DeadlineWidgetSupport
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class HomeWidgetsBridge {
  private var channel: FlutterMethodChannel?
  private var pendingSchedule = false
  private let queue = DispatchQueue(label: "club.geekpie.techpie.home-widgets")

  func configure(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(name: "techpie/home_widgets", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "consumePendingRoute":
        result(self.pendingSchedule ? "schedule" : nil)
      case "acknowledgePendingRoute":
        self.pendingSchedule = false
        result(nil)
      case "publishSchedule", "clearSchedule":
        self.handleSchedule(call: call, result: result)
      case "publishEcard", "clearEcard":
        self.handleEcard(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSchedule(call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async {
      do {
        guard let store = ScheduleSnapshotStore.configured() else {
          throw WidgetSnapshotError.invalidData
        }
        let changed: Bool
        if call.method == "clearSchedule" {
          changed = try store.clear()
        } else {
          guard let json = call.arguments as? String,
            let data = json.data(using: .utf8)
          else {
            throw WidgetSnapshotError.invalidData
          }
          changed = try store.write(data)
        }
        if changed, #available(iOS 14.0, macOS 11.0, *) {
          WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
          WidgetCenter.shared.reloadTimelines(ofKind: "TodayOverviewWidget")
        }
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "SCHEDULE_WIDGET_STORAGE_UNAVAILABLE",
              message: "Cannot update schedule widget data.",
              details: nil
            )
          )
        }
      }
    }
  }

  private func handleEcard(call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async {
      do {
        guard let store = EcardSnapshotStore.configured() else {
          throw WidgetSnapshotError.invalidData
        }
        let changed: Bool
        if call.method == "clearEcard" {
          changed = try store.clear()
        } else {
          guard let json = call.arguments as? String,
            let data = json.data(using: .utf8)
          else {
            throw WidgetSnapshotError.invalidData
          }
          let snapshot = try EcardWidgetSnapshot.decode(data)
          changed = try store.write(data)
          WidgetPreferenceStore.configured()?.syncEcardHideBalance(snapshot.hideBalance)
        }
        if changed, #available(iOS 14.0, macOS 11.0, *) {
          WidgetCenter.shared.reloadTimelines(ofKind: "EcardPayWidget")
        }
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ECARD_WIDGET_STORAGE_UNAVAILABLE",
              message: "Cannot update e-card widget data.",
              details: nil
            )
          )
        }
      }
    }
  }

  @discardableResult
  func capture(_ url: URL) -> Bool {
    let scheme = TechPieWidgetURL.scheme()
    guard url.scheme?.lowercased() == scheme.lowercased(),
      url.host?.lowercased() == "schedule",
      url.path.isEmpty || url.path == "/"
    else { return false }
    pendingSchedule = true
    channel?.invokeMethod("openSchedule", arguments: nil)
    return true
  }
}
