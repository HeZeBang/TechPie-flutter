import XCTest
@testable import DeadlineWidgetSupport

final class ScheduleSnapshotTests: XCTestCase {
  private var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    return cal
  }

  private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
  }

  private func course(
    _ id: String,
    start: String,
    end: String,
    title: String = "Linear Algebra",
    isExam: Bool = false
  ) -> ScheduleWidgetCourse {
    ScheduleWidgetCourse(
      id: id,
      title: title,
      location: "SIST 1A-204",
      teacher: "Prof. Li",
      startAt: date(start),
      endAt: date(end),
      startPeriod: 1,
      endPeriod: 2,
      periodLabel: "1-2",
      isExam: isExam,
      colorLightHex: "#217AD0",
      colorDarkHex: "#5BA5F6"
    )
  }

  func testDecodeAndAtomicStoreDeduplication() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ScheduleSnapshotStore(directory: dir)
    let c1 = course("c1", start: "2026-11-27T00:15:00Z", end: "2026-11-27T01:55:00Z")
    let snap1 = ScheduleWidgetSnapshot(
      generatedAt: date("2026-11-27T00:00:00Z"),
      weekNumber: 12,
      days: [ScheduleWidgetDay(date: "2026-11-27", weekday: 5, weekNumber: 12, courses: [c1])]
    )
    XCTAssertTrue(try store.write(try snap1.encode()))
    let snap2 = ScheduleWidgetSnapshot(
      generatedAt: date("2026-11-27T00:05:00Z"),
      weekNumber: 12,
      days: snap1.days
    )
    XCTAssertFalse(try store.write(try snap2.encode()))
    guard case .ready(let loaded) = store.read() else {
      return XCTFail("Expected ready snapshot")
    }
    XCTAssertEqual(loaded.days.first?.courses.first?.title, "Linear Algebra")
    XCTAssertTrue(try store.clear())
    XCTAssertFalse(try store.clear())
  }

  func testDecodeRejectsBadSchemaDuplicateCoursesAndBadIntervals() throws {
    let badSchema = """
    {"schemaVersion":2,"generatedAt":"2026-11-27T00:00:00Z","days":[]}
    """
    XCTAssertThrowsError(try ScheduleWidgetSnapshot.decode(Data(badSchema.utf8)))

    let badInterval = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-11-27T00:00:00Z",
      "days": [{
        "date": "2026-11-27",
        "weekday": 5,
        "courses": [{
          "id": "x",
          "title": "Bad",
          "location": "",
          "teacher": "",
          "startAt": "2026-11-27T02:00:00Z",
          "endAt": "2026-11-27T01:00:00Z",
          "isExam": false,
          "colorLightHex": "#000000",
          "colorDarkHex": "#FFFFFF"
        }]
      }]
    }
    """
    XCTAssertThrowsError(try ScheduleWidgetSnapshot.decode(Data(badInterval.utf8)))
  }

  func testResolverDetectsInProgressUpcomingAndEndOfDayRollover() {
    let fri1 = course("fri1", start: "2026-11-27T08:15:00+08:00", end: "2026-11-27T09:55:00+08:00", title: "Calculus")
    let fri2 = course("fri2", start: "2026-11-27T14:00:00+08:00", end: "2026-11-27T15:40:00+08:00", title: "Physics")
    let mon1 = course("mon1", start: "2026-11-30T08:15:00+08:00", end: "2026-11-30T09:55:00+08:00", title: "Algorithms")
    let snapshot = ScheduleWidgetSnapshot(
      generatedAt: date("2026-11-27T07:00:00+08:00"),
      weekNumber: 12,
      days: [
        ScheduleWidgetDay(date: "2026-11-27", weekday: 5, weekNumber: 12, courses: [fri1, fri2]),
        ScheduleWidgetDay(date: "2026-11-28", weekday: 6, weekNumber: 12, courses: []),
        ScheduleWidgetDay(date: "2026-11-29", weekday: 7, weekNumber: 12, courses: []),
        ScheduleWidgetDay(date: "2026-11-30", weekday: 1, weekNumber: 13, courses: [mon1]),
      ]
    )

    // Before first class -> upcoming Calculus.
    let resBefore = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: date("2026-11-27T07:50:00+08:00"),
      mode: .auto,
      calendar: calendar
    )
    if case .upcoming(let next, let remaining, _, _, _, let isTomorrow, _) = resBefore {
      XCTAssertEqual(next.id, "fri1")
      XCTAssertEqual(remaining.map(\.id), ["fri1", "fri2"])
      XCTAssertFalse(isTomorrow)
    } else {
      XCTFail("Expected upcoming before first class, got \(resBefore)")
    }

    // During Calculus -> inProgress with next = Physics.
    let resDuring = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: date("2026-11-27T09:05:00+08:00"),
      mode: .auto,
      calendar: calendar
    )
    if case .inProgress(let current, let next, _, _, _, _, _, _) = resDuring {
      XCTAssertEqual(current.id, "fri1")
      XCTAssertEqual(next?.id, "fri2")
      XCTAssertEqual(current.progress(at: date("2026-11-27T09:05:00+08:00")) ?? -1, 0.5, accuracy: 0.01)
    } else {
      XCTFail("Expected inProgress, got \(resDuring)")
    }

    // Friday evening -> weekend empty -> automatic rollover 3 days ahead to Monday.
    let resEvening = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: date("2026-11-27T20:00:00+08:00"),
      mode: .auto,
      calendar: calendar
    )
    if case .rollover(let targetDate, let weekday, let week, let daysAhead, let courses) = resEvening {
      XCTAssertEqual(targetDate, "2026-11-30")
      XCTAssertEqual(weekday, 1)
      XCTAssertEqual(week, 13)
      XCTAssertEqual(daysAhead, 3)
      XCTAssertEqual(courses.map(\.id), ["mon1"])
    } else {
      XCTFail("Expected Monday rollover, got \(resEvening)")
    }

    // Manual `.today` on Friday evening stays empty for today instead of rolling over.
    let resManualToday = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: date("2026-11-27T20:00:00+08:00"),
      mode: .today,
      calendar: calendar
    )
    if case .empty(_, _, _, let isTomorrow, let mode) = resManualToday {
      XCTAssertFalse(isTomorrow)
      XCTAssertEqual(mode, .today)
    } else {
      XCTFail("Expected empty today in manual today mode, got \(resManualToday)")
    }

    // Manual `.tomorrow` explicitly peeks Saturday (empty).
    let resManualTomorrow = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: date("2026-11-27T09:05:00+08:00"),
      mode: .tomorrow,
      calendar: calendar
    )
    if case .empty(let dayDate, _, _, let isTomorrow, let mode) = resManualTomorrow {
      XCTAssertEqual(dayDate, "2026-11-28")
      XCTAssertTrue(isTomorrow)
      XCTAssertEqual(mode, .tomorrow)
    } else {
      XCTFail("Expected Saturday empty in manual tomorrow mode, got \(resManualTomorrow)")
    }
  }

  func testDayModeResetsAutomaticallyAtLocalMidnight() {
    let suite = "SchedulePrefsTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let prefs = WidgetPreferenceStore(defaults: defaults)

    let morning = date("2026-11-27T09:00:00+08:00")
    XCTAssertEqual(prefs.scheduleDayMode(at: morning, calendar: calendar), .auto)

    let toggled = prefs.toggleScheduleDayMode(
      currentlyShowingTomorrowOrLater: false,
      at: morning,
      calendar: calendar
    )
    XCTAssertEqual(toggled, .tomorrow)
    XCTAssertEqual(prefs.scheduleDayMode(at: morning, calendar: calendar), .tomorrow)

    // Next calendar day reverts cleanly to .auto.
    let nextMorning = date("2026-11-28T07:00:00+08:00")
    XCTAssertEqual(prefs.scheduleDayMode(at: nextMorning, calendar: calendar), .auto)
  }

  func testNextRefreshDateFindsEarliestTransition() {
    let fri1 = course("fri1", start: "2026-11-27T08:15:00+08:00", end: "2026-11-27T09:55:00+08:00")
    let snapshot = ScheduleWidgetSnapshot(
      days: [ScheduleWidgetDay(date: "2026-11-27", weekday: 5, courses: [fri1])]
    )
    XCTAssertEqual(
      ScheduleWidgetResolver.nextRefreshDate(
        snapshot: snapshot,
        at: date("2026-11-27T08:00:00+08:00"),
        calendar: calendar
      ),
      date("2026-11-27T08:15:00+08:00")
    )
    XCTAssertEqual(
      ScheduleWidgetResolver.nextRefreshDate(
        snapshot: snapshot,
        at: date("2026-11-27T09:00:00+08:00"),
        calendar: calendar
      ),
      date("2026-11-27T09:55:00+08:00")
    )
  }
}
