import Foundation

public struct DeadlineItem: Codable, Equatable, Identifiable {
  public enum Kind: String, Codable { case assignment, exam }
  public let id: String
  public let kind: Kind
  public let title: String
  public let course: String
  public let dueAt: Double
  public var due: Date { Date(timeIntervalSince1970: dueAt) }

  public init(id: String, kind: Kind, title: String, course: String, dueAt: Double) {
    self.id = id
    self.kind = kind
    self.title = title
    self.course = course
    self.dueAt = dueAt
  }
}

public struct DeadlineSnapshot: Codable, Equatable {
  public let schemaVersion: Int
  public let writtenAt: Double
  public let items: [DeadlineItem]

  public init(writtenAt: Double, items: [DeadlineItem]) {
    schemaVersion = 1
    self.writtenAt = writtenAt
    self.items = items
  }

  public static func decode(_ data: Data) throws -> DeadlineSnapshot {
    let snapshot = try JSONDecoder().decode(Self.self, from: data)
    guard snapshot.schemaVersion == 1,
      validTimestamp(snapshot.writtenAt),
      Set(snapshot.items.map(\.id)).count == snapshot.items.count,
      snapshot.items.allSatisfy({ !$0.id.isEmpty && validTimestamp($0.dueAt) })
    else { throw SnapshotError.invalidData }
    return snapshot
  }

  private static func validTimestamp(_ value: Double) -> Bool {
    value.isFinite && value >= 0 && value <= 253402300799
  }

  public func upcoming(at date: Date, limit: Int) -> [DeadlineItem] {
    Array(items.filter { $0.due > date }.sorted {
      $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt
    }.prefix(max(0, limit)))
  }

  public func timelineDates(after now: Date, calendar: Calendar = .current) -> [Date] {
    let end = now.addingTimeInterval(24 * 3600)
    var dates: Set<Date> = [now, end]
    if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
      midnight > now && midnight < end { dates.insert(midnight) }
    for item in items {
      // Full-hour labels change just after a boundary; expiry remains exact.
      guard let hours = Self.remainingHours(item, at: now) else { continue }
      let firstBoundary = item.due.addingTimeInterval(-Double(hours) * 3600 + 1)
      for offset in 0..<24 {
        let date = firstBoundary.addingTimeInterval(Double(offset) * 3600)
        if date > now && date < end && date < item.due { dates.insert(date) }
      }
      if item.due > now && item.due < end { dates.insert(item.due) }
    }
    return dates.sorted()
  }

  public static func remainingHours(_ item: DeadlineItem, at date: Date) -> Int? {
    let remaining = item.due.timeIntervalSince(date)
    guard remaining > 0 else { return nil }
    return Int(remaining / 3600)
  }

  public enum SnapshotError: Error { case invalidData }
}

public enum DeadlineDateLabel {
  public static func string(for due: Date, at now: Date, compact: Bool,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: due)
    let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
    if compact && sameYear && calendar.isDate(due, inSameDayAs: now) {
      return "\(localizedDay(tomorrow: false, locale: locale)) \(time)"
    }
    if compact && sameYear, let next = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(due, inSameDayAs: next) {
      return "\(localizedDay(tomorrow: true, locale: locale)) \(time)"
    }
    formatter.dateFormat = sameYear
      ? "MM/dd HH:mm" : "yyyy/MM/dd HH:mm"
    return formatter.string(from: due)
  }

  private static func localizedDay(tomorrow: Bool, locale: Locale) -> String {
    if locale.identifier.hasPrefix("zh") { return tomorrow ? "明天" : "今天" }
    if locale.identifier.hasPrefix("ja") { return tomorrow ? "明日" : "今日" }
    return tomorrow ? "Tomorrow" : "Today"
  }
}


public enum DeadlineSnapshotState {
  case ready(DeadlineSnapshot)
  case notSynced
  case unavailable
}

public final class DeadlineSnapshotStore {
  public static let fileName = "deadline-widget-v1.json"
  private let directory: URL

  public init(directory: URL) { self.directory = directory }

  public static func configured(in bundle: Bundle = .main) -> DeadlineSnapshotStore? {
    guard let group = bundle.object(forInfoDictionaryKey: "TechPieDeadlineAppGroup") as? String,
      !group.isEmpty,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return DeadlineSnapshotStore(directory: directory.appendingPathComponent("Library/Application Support", isDirectory: true))
  }

  private var url: URL { directory.appendingPathComponent(Self.fileName) }

  public func read() -> DeadlineSnapshotState {
    do {
      return .ready(try DeadlineSnapshot.decode(Data(contentsOf: url)))
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      // macOS can return a URL for an unauthorized group. Check access separately.
      let root = directory.deletingLastPathComponent().deletingLastPathComponent()
      return FileManager.default.isReadableFile(atPath: root.path) ? .notSynced : .unavailable
    } catch { return .unavailable }
  }

  @discardableResult public func write(_ data: Data) throws -> Bool {
    let snapshot = try DeadlineSnapshot.decode(data)
    if case .ready(let saved) = read(), saved.items == snapshot.items { return false }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    #endif
    return true
  }

  @discardableResult public func clear() throws -> Bool {
    do { try FileManager.default.removeItem(at: url); return true }
    catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { return false }
  }
}
