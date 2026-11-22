import EventKit
import Foundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class DeadlineReminderBridge {
  private enum Change: String {
    case complete
    case reopen
    case remove
  }

  private struct Details {
    let title: String
    let notes: String?
    let location: String?
    let due: Date

    init?(_ entry: [String: Any]) {
      guard let title = entry["title"] as? String, let due = entry["due"] as? NSNumber else {
        return nil
      }
      self.title = title
      let notes = entry["notes"] as? String ?? ""
      self.notes = notes.isEmpty ? nil : notes
      let location = entry["location"] as? String ?? ""
      self.location = location.isEmpty ? nil : location
      self.due = Date(timeIntervalSince1970: due.doubleValue / 1000)
    }
  }

  private lazy var store = EKEventStore()
  private var channel: FlutterMethodChannel?
  private var changeObserver: NSObjectProtocol?
  private var adding = false
  private let scheme = Bundle.main.object(forInfoDictionaryKey: "TechPieWidgetURLScheme")
    as? String ?? "techpie"

  deinit {
    if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
  }

  func configure(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "techpie/deadline_reminders", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "add":
        guard let entries = call.arguments as? [[String: Any]] else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.add(entries, result: result)
      case "completed":
        guard let keys = call.arguments as? [String] else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.completed(keys: Set(keys), result: result)
      case "change":
        guard let entries = call.arguments as? [String: String],
          entries.values.allSatisfy({ Change(rawValue: $0) != nil })
        else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.applyChanges(entries.compactMapValues(Change.init(rawValue:)), result: result)
      case "edit":
        guard let entries = call.arguments as? [String: [String: Any]] else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        let details = entries.compactMapValues(Details.init)
        guard details.count == entries.count else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.edit(details, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    changeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: nil, queue: .main
    ) { [weak self] _ in
      self?.channel?.invokeMethod("remindersChanged", arguments: nil)
    }
  }

  private var hasAccess: Bool {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if #available(iOS 17.0, macOS 14.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func requestAccess(_ completion: @escaping (Bool) -> Void) {
    if hasAccess {
      completion(true)
    } else if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
      let handler: EKEventStoreRequestAccessCompletionHandler = { granted, _ in
        DispatchQueue.main.async { completion(granted) }
      }
      if #available(iOS 17.0, macOS 14.0, *) {
        store.requestFullAccessToReminders(completion: handler)
      } else {
        store.requestAccess(to: .reminder, completion: handler)
      }
    } else {
      completion(false)
    }
  }

  private func fetchReminders(_ completion: @escaping ([EKReminder]?) -> Void) {
    let predicate = store.predicateForReminders(in: nil)
    store.fetchReminders(matching: predicate) { reminders in
      DispatchQueue.main.async { completion(reminders) }
    }
  }

  private func completed(keys: Set<String>, result: @escaping FlutterResult) {
    guard hasAccess, !keys.isEmpty else {
      result([String: Int64]())
      return
    }
    fetchReminders { reminders in
      guard let reminders else {
        result(self.error("reminders_unavailable"))
        return
      }
      var completedAt = [String: Int64]()
      for reminder in reminders where reminder.isCompleted {
        guard let key = self.key(for: reminder), keys.contains(key) else { continue }
        let timestamp = reminder.completionDate
          .map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        completedAt[key] = max(timestamp, completedAt[key] ?? 0)
      }
      result(completedAt)
    }
  }

  private func applyChanges(_ changes: [String: Change], result: @escaping FlutterResult) {
    mutate(keys: Set(changes.keys), result: result) { reminder, key in
      guard let change = changes[key] else { return }
      switch change {
      case .complete, .reopen:
        let completed = change == .complete
        guard reminder.isCompleted != completed else { return }
        reminder.isCompleted = completed
        try self.store.save(reminder, commit: true)
      case .remove:
        try self.store.remove(reminder, commit: true)
      }
    }
  }

  private func edit(_ entries: [String: Details], result: @escaping FlutterResult) {
    mutate(keys: Set(entries.keys), result: result) { reminder, key in
      guard let details = entries[key], self.setDetails(details, on: reminder) else { return }
      try self.store.save(reminder, commit: true)
    }
  }

  private func mutate(
    keys: Set<String>, result: @escaping FlutterResult,
    apply: @escaping (EKReminder, String) throws -> Void
  ) {
    guard hasAccess else {
      result(error("reminders_denied"))
      return
    }
    fetchReminders { reminders in
      guard self.hasAccess else {
        result(self.error("reminders_denied"))
        return
      }
      guard let reminders else {
        result(self.error("reminders_unavailable"))
        return
      }
      var failed = Set<String>()
      for reminder in reminders {
        guard let key = self.key(for: reminder), keys.contains(key) else { continue }
        do {
          try apply(reminder, key)
        } catch {
          failed.insert(key)
        }
      }
      result(Array(keys.subtracting(failed)))
    }
  }

  private func add(_ entries: [[String: Any]], result: @escaping FlutterResult) {
    guard !adding else {
      result(error("reminders_busy"))
      return
    }
    adding = true
    let finish: FlutterResult = { value in
      self.adding = false
      result(value)
    }
    requestAccess { granted in
      guard granted else {
        finish(self.error("reminders_denied"))
        return
      }
      self.fetchReminders { reminders in
        guard let reminders else {
          finish(self.error("reminders_unavailable"))
          return
        }
        self.save(entries, existingKeys: Set(reminders.compactMap(self.key(for:))), result: finish)
      }
    }
  }

  private func save(
    _ entries: [[String: Any]], existingKeys: Set<String>, result: FlutterResult
  ) {
    let list = store.defaultCalendarForNewReminders()
    var keys = existingKeys
    var added = 0
    var existing = 0
    var failed = 0
    for entry in entries {
      guard let key = entry["key"] as? String, !key.isEmpty, let details = Details(entry) else {
        failed += 1
        continue
      }
      if keys.contains(key) {
        existing += 1
        continue
      }
      guard let list, list.allowsContentModifications else {
        result(error("reminders_no_list"))
        return
      }

      let reminder = EKReminder(eventStore: store)
      reminder.calendar = list
      reminder.url = link(for: key)
      reminder.isCompleted = entry["completed"] as? Bool ?? false
      _ = setDetails(details, on: reminder)

      do {
        try store.save(reminder, commit: true)
        keys.insert(key)
        added += 1
      } catch {
        failed += 1
      }
    }
    result(["added": added, "existing": existing, "failed": failed])
  }

  private func setDetails(_ details: Details, on reminder: EKReminder) -> Bool {
    let fieldsChanged = reminder.title != details.title
      || reminder.notes != details.notes || reminder.location != details.location
    if fieldsChanged {
      reminder.title = details.title
      reminder.notes = details.notes
      reminder.location = details.location
    }

    let calendar = Calendar(identifier: .gregorian)
    func date(from components: DateComponents?) -> Date? {
      guard let components else { return nil }
      return (components.calendar ?? calendar).date(from: components)
    }
    let oldDue = date(from: reminder.dueDateComponents)
    let dueChanged = oldDue != details.due
    guard dueChanged || date(from: reminder.startDateComponents) != details.due else {
      return fieldsChanged
    }
    let components = calendar.dateComponents(
      [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: details.due)
    reminder.startDateComponents = components
    reminder.dueDateComponents = components
    if dueChanged {
      let originalAlarms = reminder.alarms ?? []
      let dueAlarms = originalAlarms.filter { oldDue != nil && $0.absoluteDate == oldDue }
      for alarm in dueAlarms { reminder.removeAlarm(alarm) }
      if !reminder.isCompleted && details.due > Date()
        && (originalAlarms.isEmpty || !dueAlarms.isEmpty) {
        reminder.addAlarm(EKAlarm(absoluteDate: details.due))
      }
    }
    return true
  }

  private func link(for key: String) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "deadlines"
    components.queryItems = [URLQueryItem(name: "reminder", value: key)]
    return components.url
  }

  private func key(for reminder: EKReminder) -> String? {
    guard let url = reminder.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == scheme, components.host == "deadlines"
    else { return nil }
    return components.queryItems?.first { $0.name == "reminder" }?.value
  }

  private func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
