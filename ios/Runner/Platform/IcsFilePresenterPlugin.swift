import CoreLocation
import EventKit
import Flutter
import UIKit

final class IcsFilePresenterPlugin: NSObject, FlutterPlugin {
  private static let channelName = "techpie/calendar_importer"
  private let eventStore = EKEventStore()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = IcsFilePresenterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "importCalendarEvents":
      guard
        let arguments = call.arguments as? [String: Any],
        let rawEvents = arguments["events"] as? [[String: Any]],
        let calendarName = arguments["calendarName"] as? String,
        !calendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Missing events or calendarName for calendar import.",
            details: nil
          )
        )
        return
      }

      requestCalendarAccess { [weak self] accessResult in
        DispatchQueue.main.async {
          switch accessResult {
          case .success:
            guard let self else {
              result(
                FlutterError(
                  code: "plugin_deallocated",
                  message: "Calendar importer was released before completion.",
                  details: nil
                )
              )
              return
            }

            do {
              let calendar = try self.resolveCalendar(named: calendarName)
              let importedCount = try self.importEvents(rawEvents, into: calendar)
              result(importedCount)
            } catch {
              result(
                FlutterError(
                  code: "import_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          case .failure(let error):
            result(
              FlutterError(
                code: "calendar_access_denied",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestCalendarAccess(
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, error in
        if let error {
          completion(.failure(error))
          return
        }
        if granted {
          completion(.success(()))
        } else {
          completion(
            .failure(
              NSError(
                domain: "TechPieCalendarImporter",
                code: 1,
                userInfo: [
                  NSLocalizedDescriptionKey: "未获得日历访问权限。"
                ]
              )
            )
          )
        }
      }
      return
    }

    eventStore.requestAccess(to: .event) { granted, error in
      if let error {
        completion(.failure(error))
        return
      }
      if granted {
        completion(.success(()))
      } else {
        completion(
          .failure(
            NSError(
              domain: "TechPieCalendarImporter",
              code: 1,
              userInfo: [
                NSLocalizedDescriptionKey: "未获得日历访问权限。"
              ]
            )
          )
        )
      }
    }
  }

  private func resolveCalendar(named calendarName: String) throws -> EKCalendar {
    if let existing = eventStore.calendars(for: .event).first(where: {
      $0.title == calendarName && $0.allowsContentModifications
    }) {
      return existing
    }

    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.title = calendarName

    if let source = preferredSource() {
      calendar.source = source
    } else {
      throw NSError(
        domain: "TechPieCalendarImporter",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "无法创建目标日历，请先在系统日历中添加可写账号。"
        ]
      )
    }

    try eventStore.saveCalendar(calendar, commit: true)
    return calendar
  }

  private func preferredSource() -> EKSource? {
    if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
      return defaultSource
    }

    let sources = eventStore.sources
    return sources.first(where: { $0.sourceType == .calDAV }) ??
      sources.first(where: { $0.sourceType == .local }) ??
      sources.first
  }

  private func importEvents(
    _ rawEvents: [[String: Any]],
    into calendar: EKCalendar
  ) throws -> Int {
    var importedCount = 0

    for rawEvent in rawEvents {
      guard
        let title = rawEvent["title"] as? String,
        let startMillis = rawEvent["startMillis"] as? NSNumber,
        let endMillis = rawEvent["endMillis"] as? NSNumber
      else {
        continue
      }

      let event = EKEvent(eventStore: eventStore)
      event.calendar = calendar
      event.title = title
      event.startDate = Date(timeIntervalSince1970: startMillis.doubleValue / 1000)
      event.endDate = Date(timeIntervalSince1970: endMillis.doubleValue / 1000)
      event.location = rawEvent["location"] as? String

      let notes = rawEvent["notes"] as? String
      if let notes, !notes.isEmpty {
        event.notes = notes
      }

      if
        let locationTitle = rawEvent["structuredLocationTitle"] as? String,
        let latitude = rawEvent["structuredLocationLatitude"] as? NSNumber,
        let longitude = rawEvent["structuredLocationLongitude"] as? NSNumber
      {
        let structuredLocation = EKStructuredLocation(title: locationTitle)
        structuredLocation.geoLocation = CLLocation(
          latitude: latitude.doubleValue,
          longitude: longitude.doubleValue
        )
        event.structuredLocation = structuredLocation
      }

      try eventStore.save(event, span: .thisEvent, commit: false)
      importedCount += 1
    }

    if importedCount > 0 {
      try eventStore.commit()
    }

    return importedCount
  }
}
