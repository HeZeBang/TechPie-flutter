import Foundation

public struct DeadlineItem: Codable, Equatable, Identifiable {
  public enum Kind: String, Codable { case assignment, exam }
  public let id: String
  public let kind: Kind
  public let title: String
  /// The line under the title: the course for an assignment, the location for
  /// an exam (whose title already names the course). May be empty.
  public let subtitle: String
  public let dueAt: Double
  public var due: Date { Date(timeIntervalSince1970: dueAt) }

  public init(id: String, kind: Kind, title: String, subtitle: String, dueAt: Double) {
    self.id = id
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
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

/// The day groups the large widget lists deadlines under.
public enum DeadlineDay: Int, Comparable {
  case today, tomorrow, nextWeek, later

  public static func of(_ due: Date, at now: Date, calendar: Calendar = .current) -> DeadlineDay {
    let start = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: due)).day ?? 0
    switch days {
    case ..<1: return .today
    case 1: return .tomorrow
    case 2..<7: return .nextWeek
    default: return .later
    }
  }

  /// Consecutive runs of `items` (already in deadline order) that share a day.
  public static func group(_ items: [DeadlineItem], at now: Date,
                           calendar: Calendar = .current) -> [(day: DeadlineDay, items: [DeadlineItem])] {
    var groups: [(day: DeadlineDay, items: [DeadlineItem])] = []
    for item in items {
      let day = of(item.due, at: now, calendar: calendar)
      if groups.last?.day == day { groups[groups.count - 1].items.append(item) }
      else { groups.append((day, [item])) }
    }
    return groups
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Coarser the further away it is: hours matter tomorrow, not next month.
public enum DeadlineRemaining: Equatable {
  case dueSoon, hours(Int), daysHours(Int, Int), days(Int)

  public init(hours: Int) {
    switch hours {
    case ..<1: self = .dueSoon
    case ..<24: self = .hours(hours)
    case ..<48: self = .daysHours(hours / 24, hours % 24)
    default: self = .days(hours / 24)
    }
  }

  public var isUrgent: Bool {
    switch self { case .dueSoon, .hours: return true; default: return false }
  }
}

public enum DeadlineDateLabel {
  /// Time of day only, for rows already grouped under Today or Tomorrow.
  public static func time(for due: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: due)
  }

  /// `weekday` adds the day of the week to an absolute date ("11/08 Sun
  /// 23:59"), where there is room for it; Today and Tomorrow need none.
  public static func string(for due: Date, at now: Date, compact: Bool, weekday: Bool = false,
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
    let day = sameYear ? "MM/dd" : "yyyy/MM/dd"
    formatter.dateFormat = weekday ? "\(day) EEE HH:mm" : "\(day) HH:mm"
    return formatter.string(from: due)
  }

  private static func localizedDay(tomorrow: Bool, locale: Locale) -> String {
    if locale.identifier.hasPrefix("zh") { return tomorrow ? "明天" : "今天" }
    if locale.identifier.hasPrefix("ja") { return tomorrow ? "明日" : "今日" }
    return tomorrow ? "Tomorrow" : "Today"
  }
}
