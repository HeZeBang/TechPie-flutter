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
      let hourBoundaries = (1...24).map { item.due.addingTimeInterval(-Double($0) * 3600 + 1) }
      for date in [item.due, item.due.addingTimeInterval(-24 * 3600)] + hourBoundaries {
        if date > now && date < end { dates.insert(date) }
      }
    }
    return dates.sorted()
  }

  public static func isImminent(_ item: DeadlineItem, at date: Date) -> Bool {
    let remaining = item.due.timeIntervalSince(date)
    return remaining > 0 && remaining <= 24 * 3600
  }

  public static func remainingHours(_ item: DeadlineItem, at date: Date) -> Int? {
    guard isImminent(item, at: date) else { return nil }
    return Int(item.due.timeIntervalSince(date) / 3600)
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
