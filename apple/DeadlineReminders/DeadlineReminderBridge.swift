import EventKit
import Foundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class DeadlineReminderBridge {
  private static let listTitle = "Deadline"
  // The previous key could contain a list found by its title alone.
  private static let listIdentifierKey = "TechPieCreatedDeadlineReminderListIdentifier"

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
  private var savingSelection = false
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
      case "linked":
        guard let keys = call.arguments as? [String] else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.linked(keys: Set(keys), result: result)
      case "saveSelection":
        guard let arguments = call.arguments as? [String: Any],
          let entries = arguments["add"] as? [[String: Any]],
          let removedKeys = arguments["remove"] as? [String]
        else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.saveSelection(entries, removing: Set(removedKeys), result: result)
      case "completionStates":
        guard let keys = call.arguments as? [String] else {
          result(self.error("reminders_invalid_arguments"))
          return
        }
        self.completionStates(keys: Set(keys), result: result)
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

  private func fetchWithAccess(
    result: @escaping FlutterResult, completion: @escaping ([EKReminder]) -> Void
  ) {
    requestAccess { granted in
      guard granted else {
        result(self.error("reminders_denied"))
        return
      }
      self.fetchReminders { reminders in
        guard self.hasAccess else {
          result(self.error("reminders_denied"))
          return
        }
        guard let reminders else {
          result(self.error("reminders_unavailable"))
          return
        }
        completion(reminders)
      }
    }
  }

  private func linked(keys: Set<String>, result: @escaping FlutterResult) {
    fetchWithAccess(result: result) { reminders in
      result(Array(keys.intersection(reminders.compactMap(self.key(for:)))))
    }
  }

  private func completionStates(keys: Set<String>, result: @escaping FlutterResult) {
    guard hasAccess, !keys.isEmpty else {
      result([String: Any]())
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
      // A null value describes a linked, open reminder. An absent key leaves
      // the corresponding TechPie deadline untouched.
      var states = [String: Any]()
      for reminder in reminders {
        guard let key = self.key(for: reminder), keys.contains(key) else { continue }
        if reminder.isCompleted {
          let timestamp = reminder.completionDate
            .map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
          states[key] = max(timestamp, states[key] as? Int64 ?? 0)
        } else if states[key] == nil {
          states[key] = NSNull()
        }
      }
      result(states)
    }
  }

  private func applyChanges(_ changes: [String: Change], result: @escaping FlutterResult) {
    mutate(keys: Set(changes.keys), result: result) { reminder, key in
      guard let change = changes[key] else { return }
      switch change {
      case .complete, .reopen:
        let completed = change == .complete
        let completionChanged = reminder.isCompleted != completed
        if completionChanged { reminder.isCompleted = completed }
        let alarmRestored = !completed && self.restoreDueAlarm(on: reminder)
        guard completionChanged || alarmRestored else { return }
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
      result(Array(self.apply(to: reminders, keys: keys, mutation: apply)))
    }
  }

  private func apply(
    to reminders: [EKReminder], keys: Set<String>,
    mutation: (EKReminder, String) throws -> Void
  ) -> Set<String> {
    var failed = Set<String>()
    for reminder in reminders {
      guard let key = self.key(for: reminder), keys.contains(key) else { continue }
      do {
        try mutation(reminder, key)
      } catch {
        failed.insert(key)
      }
    }
    return keys.subtracting(failed)
  }

  private func saveSelection(
    _ entries: [[String: Any]], removing removedKeys: Set<String>, result: @escaping FlutterResult
  ) {
    guard !savingSelection else {
      result(error("reminders_busy"))
      return
    }
    savingSelection = true
    let finish: FlutterResult = { value in
      self.savingSelection = false
      result(value)
    }
    fetchWithAccess(result: finish) { reminders in
      self.save(entries, removing: removedKeys, from: reminders, result: finish)
    }
  }

  private func save(
    _ entries: [[String: Any]], removing removedKeys: Set<String>,
    from reminders: [EKReminder], result: FlutterResult
  ) {
    let existingKeys = Set(reminders.compactMap(key(for:)))
    var list: EKCalendar?
    var added = Set<String>()
    var existing = Set<String>()
    for entry in entries {
      guard let key = entry["key"] as? String, !key.isEmpty,
        !removedKeys.contains(key), let details = Details(entry)
      else { continue }
      if existingKeys.contains(key) {
        existing.insert(key)
        continue
      }
      if added.contains(key) { continue }
      if list == nil {
        do {
          list = try resolveDeadlineList()
        } catch {
          result(self.error("reminders_list_creation_failed"))
          return
        }
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
        added.insert(key)
      } catch {
        continue
      }
    }
    let removed = apply(to: reminders, keys: removedKeys) { reminder, _ in
      try self.store.remove(reminder, commit: true)
    }
    result(["added": Array(added), "existing": Array(existing), "removed": Array(removed)])
  }

  private func resolveDeadlineList() throws -> EKCalendar? {
    let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
    let defaults = UserDefaults.standard
    if let identifier = defaults.string(forKey: Self.listIdentifierKey),
      let list = lists.first(where: { $0.calendarIdentifier == identifier }) {
      return list
    }

    let defaultSource = store.defaultCalendarForNewReminders()?.source
    let sources = store.sources
    guard let source = defaultSource ?? lists.first?.source
      ?? sources.first(where: { $0.sourceType == .calDAV })
      ?? sources.first(where: { $0.sourceType == .local }) else { return nil }

    let list = EKCalendar(for: .reminder, eventStore: store)
    list.title = Self.listTitle
    list.source = source
    try store.saveCalendar(list, commit: true)
    defaults.set(list.calendarIdentifier, forKey: Self.listIdentifierKey)
    return list
  }

  private func restoreDueAlarm(on reminder: EKReminder) -> Bool {
    guard !reminder.hasAlarms, let due = date(from: reminder.dueDateComponents),
      due > Date()
    else { return false }
    reminder.addAlarm(EKAlarm(absoluteDate: due))
    return true
  }

  private func date(from components: DateComponents?) -> Date? {
    guard let components else { return nil }
    return (components.calendar ?? Calendar(identifier: .gregorian)).date(from: components)
  }

  private func setDetails(_ details: Details, on reminder: EKReminder) -> Bool {
    let fieldsChanged = reminder.title != details.title
      || reminder.notes != details.notes || reminder.location != details.location
    if fieldsChanged {
      reminder.title = details.title
      reminder.notes = details.notes
      reminder.location = details.location
    }

    let oldDue = date(from: reminder.dueDateComponents)
    let dueChanged = oldDue != details.due
    guard dueChanged || date(from: reminder.startDateComponents) != details.due else {
      return fieldsChanged
    }
    let components = Calendar(identifier: .gregorian).dateComponents(
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
