import Foundation

public struct ScheduleWidgetCourse: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let location: String
  public let teacher: String
  public let startAt: Date
  public let endAt: Date
  public let startPeriod: Int?
  public let endPeriod: Int?
  public let periodLabel: String?
  public let isExam: Bool
  public let colorLightHex: String
  public let colorDarkHex: String

  public init(
    id: String,
    title: String,
    location: String = "",
    teacher: String = "",
    startAt: Date,
    endAt: Date,
    startPeriod: Int? = nil,
    endPeriod: Int? = nil,
    periodLabel: String? = nil,
    isExam: Bool = false,
    colorLightHex: String = "#217AD0",
    colorDarkHex: String = "#5BA5F6"
  ) {
    self.id = id
    self.title = title
    self.location = location
    self.teacher = teacher
    self.startAt = startAt
    self.endAt = endAt
    self.startPeriod = startPeriod
    self.endPeriod = endPeriod
    self.periodLabel = periodLabel
    self.isExam = isExam
    self.colorLightHex = colorLightHex
    self.colorDarkHex = colorDarkHex
  }

  public func isInProgress(at now: Date) -> Bool {
    startAt <= now && now < endAt
  }

  public func progress(at now: Date) -> Double? {
    guard isInProgress(at: now) else { return nil }
    let total = endAt.timeIntervalSince(startAt)
    guard total > 0 else { return nil }
    let elapsed = now.timeIntervalSince(startAt)
    return min(max(elapsed / total, 0), 1)
  }

  public func clockRangeText(calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return "\(formatter.string(from: startAt)) – \(formatter.string(from: endAt))"
  }

  public func startClockText(calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: startAt)
  }
}

public struct ScheduleWidgetDay: Codable, Equatable, Identifiable, Sendable {
  public let date: String
  public let weekday: Int
  public let weekNumber: Int?
  public let courses: [ScheduleWidgetCourse]

  public var id: String { date }

  public init(
    date: String,
    weekday: Int,
    weekNumber: Int? = nil,
    courses: [ScheduleWidgetCourse]
  ) {
    self.date = date
    self.weekday = weekday
    self.weekNumber = weekNumber
    self.courses = courses
  }
}

public struct ScheduleWidgetSnapshot: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let weekNumber: Int?
  public let days: [ScheduleWidgetDay]

  public init(
    schemaVersion: Int = 1,
    generatedAt: Date = Date(),
    weekNumber: Int? = nil,
    days: [ScheduleWidgetDay]
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.weekNumber = weekNumber
    self.days = days
  }

  public static func decode(_ data: Data) throws -> ScheduleWidgetSnapshot {
    let decoder = WidgetJSONCodec.decoder()
    let snapshot = try decoder.decode(ScheduleWidgetSnapshot.self, from: data)
    guard snapshot.schemaVersion == 1 else {
      throw WidgetSnapshotError.invalidData
    }
    guard Set(snapshot.days.map(\.date)).count == snapshot.days.count else {
      throw WidgetSnapshotError.invalidData
    }
    for day in snapshot.days {
      guard !day.date.isEmpty, (1...7).contains(day.weekday) else {
        throw WidgetSnapshotError.invalidData
      }
      let ids = day.courses.map(\.id)
      guard Set(ids).count == ids.count,
        day.courses.allSatisfy({ !$0.id.isEmpty && $0.endAt > $0.startAt })
      else {
        throw WidgetSnapshotError.invalidData
      }
    }
    return snapshot
  }

  public func encode() throws -> Data {
    try WidgetJSONCodec.encoder().encode(self)
  }

  public func semanticEquals(_ other: ScheduleWidgetSnapshot) -> Bool {
    schemaVersion == other.schemaVersion &&
      weekNumber == other.weekNumber &&
      days == other.days
  }
}

public enum ScheduleDayMode: String, Codable, Equatable, Sendable {
  case auto
  case today
  case tomorrow
}

public enum ScheduleDayResolution: Equatable, Sendable {
  case inProgress(
    current: ScheduleWidgetCourse,
    next: ScheduleWidgetCourse?,
    remaining: [ScheduleWidgetCourse],
    dayDate: String,
    weekday: Int,
    weekNumber: Int?,
    isTomorrow: Bool,
    allDayCourses: [ScheduleWidgetCourse]
  )
  case upcoming(
    next: ScheduleWidgetCourse,
    remaining: [ScheduleWidgetCourse],
    dayDate: String,
    weekday: Int,
    weekNumber: Int?,
    isTomorrow: Bool,
    allDayCourses: [ScheduleWidgetCourse]
  )
  case rollover(
    targetDate: String,
    targetWeekday: Int,
    targetWeekNumber: Int?,
    daysAhead: Int,
    courses: [ScheduleWidgetCourse]
  )
  case empty(
    dayDate: String,
    weekday: Int,
    weekNumber: Int?,
    isTomorrow: Bool,
    mode: ScheduleDayMode
  )

  public var isViewingTomorrowOrLater: Bool {
    switch self {
    case .inProgress(_, _, _, _, _, _, let isTomorrow, _),
      .upcoming(_, _, _, _, _, let isTomorrow, _),
      .empty(_, _, _, let isTomorrow, _):
      return isTomorrow
    case .rollover:
      return true
    }
  }
}

public enum ScheduleWidgetResolver {
  public static func resolve(
    snapshot: ScheduleWidgetSnapshot,
    at now: Date,
    mode: ScheduleDayMode = .auto,
    calendar: Calendar = .current
  ) -> ScheduleDayResolution {
    let todayStart = calendar.startOfDay(for: now)
    let todayKey = dateKey(for: todayStart, calendar: calendar)
    let todayWeekday = isoWeekday(for: todayStart, calendar: calendar)

    let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    let tomorrowKey = dateKey(for: tomorrowDate, calendar: calendar)
    let tomorrowWeekday = isoWeekday(for: tomorrowDate, calendar: calendar)

    let dayMap = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.date, $0) })
    let todayDay = dayMap[todayKey]
    let tomorrowDay = dayMap[tomorrowKey]

    switch mode {
    case .tomorrow:
      let courses = sortedCourses(tomorrowDay?.courses ?? [])
      let weekday = tomorrowDay?.weekday ?? tomorrowWeekday
      let weekNumber = tomorrowDay?.weekNumber ?? snapshot.weekNumber
      if let first = courses.first {
        return .upcoming(
          next: first,
          remaining: courses,
          dayDate: tomorrowKey,
          weekday: weekday,
          weekNumber: weekNumber,
          isTomorrow: true,
          allDayCourses: courses
        )
      }
      return .empty(
        dayDate: tomorrowKey,
        weekday: weekday,
        weekNumber: weekNumber,
        isTomorrow: true,
        mode: .tomorrow
      )

    case .today:
      return resolveTodayOnly(
        day: todayDay,
        dayKey: todayKey,
        fallbackWeekday: todayWeekday,
        fallbackWeekNumber: snapshot.weekNumber,
        at: now,
        mode: .today
      )

    case .auto:
      let todayResult = resolveTodayOnly(
        day: todayDay,
        dayKey: todayKey,
        fallbackWeekday: todayWeekday,
        fallbackWeekNumber: snapshot.weekNumber,
        at: now,
        mode: .auto
      )
      switch todayResult {
      case .inProgress, .upcoming:
        return todayResult
      case .empty, .rollover:
        let futureDays = snapshot.days
          .filter { $0.date > todayKey && !$0.courses.isEmpty }
          .sorted { $0.date < $1.date }
        for future in futureDays {
          let courses = sortedCourses(future.courses).filter { $0.endAt > now }
          guard !courses.isEmpty else { continue }
          let ahead = daysBetween(todayStart: todayStart, targetDateKey: future.date, calendar: calendar) ?? 1
          return .rollover(
            targetDate: future.date,
            targetWeekday: future.weekday,
            targetWeekNumber: future.weekNumber ?? snapshot.weekNumber,
            daysAhead: max(1, ahead),
            courses: courses
          )
        }
        return todayResult
      }
    }
  }

  public static func timelineDates(
    snapshot: ScheduleWidgetSnapshot,
    after now: Date,
    calendar: Calendar = .current
  ) -> [Date] {
    let end = now.addingTimeInterval(24 * 3600)
    var dates: Set<Date> = [now, end]
    if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
      midnight > now && midnight < end
    {
      dates.insert(midnight)
    }
    for day in snapshot.days {
      for course in day.courses {
        if course.startAt > now && course.startAt < end {
          dates.insert(course.startAt)
        }
        if course.endAt > now && course.endAt < end {
          dates.insert(course.endAt)
        }
      }
    }
    return dates.sorted()
  }

  public static func nextRefreshDate(
    snapshot: ScheduleWidgetSnapshot,
    at now: Date,
    calendar: Calendar = .current
  ) -> Date {
    var candidates: [Date] = []
    if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
      midnight > now
    {
      candidates.append(midnight)
    }
    for day in snapshot.days {
      for course in day.courses {
        if course.startAt > now { candidates.append(course.startAt) }
        if course.endAt > now { candidates.append(course.endAt) }
      }
    }
    return candidates.min() ?? now.addingTimeInterval(30 * 60)
  }

  public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    let year = comps.year ?? 1970
    let month = comps.month ?? 1
    let day = comps.day ?? 1
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  public static func isoWeekday(for date: Date, calendar: Calendar = .current) -> Int {
    let sundayBased = calendar.component(.weekday, from: date)
    return (sundayBased + 5) % 7 + 1
  }

  private static func resolveTodayOnly(
    day: ScheduleWidgetDay?,
    dayKey: String,
    fallbackWeekday: Int,
    fallbackWeekNumber: Int?,
    at now: Date,
    mode: ScheduleDayMode
  ) -> ScheduleDayResolution {
    let allDay = sortedCourses(day?.courses ?? [])
    let weekday = day?.weekday ?? fallbackWeekday
    let weekNumber = day?.weekNumber ?? fallbackWeekNumber
    let remaining = allDay.filter { $0.endAt > now }

    if let current = remaining.first(where: { $0.isInProgress(at: now) }) {
      let next = remaining.first(where: { $0.startAt > now })
      return .inProgress(
        current: current,
        next: next,
        remaining: remaining,
        dayDate: dayKey,
        weekday: weekday,
        weekNumber: weekNumber,
        isTomorrow: false,
        allDayCourses: allDay
      )
    }
    if let next = remaining.first(where: { $0.startAt > now }) {
      return .upcoming(
        next: next,
        remaining: remaining,
        dayDate: dayKey,
        weekday: weekday,
        weekNumber: weekNumber,
        isTomorrow: false,
        allDayCourses: allDay
      )
    }
    return .empty(
      dayDate: dayKey,
      weekday: weekday,
      weekNumber: weekNumber,
      isTomorrow: false,
      mode: mode
    )
  }

  private static func sortedCourses(_ courses: [ScheduleWidgetCourse]) -> [ScheduleWidgetCourse] {
    courses.sorted { lhs, rhs in
      if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
      if lhs.endAt != rhs.endAt { return lhs.endAt < rhs.endAt }
      return lhs.id < rhs.id
    }
  }

  private static func daysBetween(
    todayStart: Date,
    targetDateKey: String,
    calendar: Calendar
  ) -> Int? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let targetDate = formatter.date(from: targetDateKey) else { return nil }
    return calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: targetDate)).day
  }
}
