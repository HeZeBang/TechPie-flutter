import XCTest
@testable import DeadlineWidgetSupport

final class DeadlineSnapshotTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1780000000)
  private func item(_ id: String, seconds: Double) -> DeadlineItem {
    DeadlineItem(id: id, kind: .assignment, title: "Synthetic assignment", subtitle: "Synthetic course", dueAt: now.timeIntervalSince1970 + seconds)
  }

  func testSortingFilteringAndFamilyLimits() {
    let items = (1...10).reversed().map { item("\($0)", seconds: Double($0) * 3600) }
      + [item("past", seconds: -1), item("due", seconds: 0)]
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: items)
    for limit in [2, 4, 8] {
      XCTAssertEqual(snapshot.upcoming(at: now, limit: limit).map(\.id), (1...limit).map(String.init))
    }
    XCTAssertEqual(snapshot.upcoming(at: now.addingTimeInterval(3600), limit: 2).map(\.id), ["2", "3"])
  }

  func testTimelineIncludesHourlyAndExpiryBoundaries() {
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [item("soon", seconds: 60), item("later", seconds: 30 * 3600)])
    let dates = snapshot.timelineDates(after: now)
    for date in [now, now.addingTimeInterval(60), now.addingTimeInterval(6 * 3600 + 1), now.addingTimeInterval(24 * 3600)] {
      XCTAssertTrue(dates.contains(date))
    }
    XCTAssertEqual(dates, dates.sorted())
  }

  func testDecodeRejectsUnknownSchemaDuplicateIDsAndInvalidDates() throws {
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [item("a", seconds: 10)])
    let data = try JSONEncoder().encode(snapshot)
    XCTAssertEqual(try DeadlineSnapshot.decode(data), snapshot)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schemaVersion"] = 2
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
    object["schemaVersion"] = 1
    object["items"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([item("a", seconds: 10), item("a", seconds: 20)]))
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
    object["items"] = [["id": "a", "kind": "exam", "title": "Exam", "subtitle": "Course", "dueAt": -10]]
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
    object["items"] = [["id": "a", "kind": "assignment", "title": "A", "subtitle": "C", "dueAt": "tomorrow"]]
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
  }

  func testRemainingTimeUsesFullHoursAndUrgencyBelowOneHour() {
    XCTAssertEqual(DeadlineSnapshot.remainingHours(item("later", seconds: 24 * 3600 + 1), at: now), 24)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(item("24h", seconds: 24 * 3600), at: now), 24)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(item("1h30m", seconds: 5400), at: now), 1)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(item("1h", seconds: 3600), at: now), 1)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(item("soon", seconds: 3599), at: now), 0)
    XCTAssertNil(DeadlineSnapshot.remainingHours(item("expired", seconds: 0), at: now))
    let deadline = item("boundary", seconds: 2 * 3600)
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [deadline])
    let urgentDate = now.addingTimeInterval(3601)
    XCTAssertTrue(snapshot.timelineDates(after: now).contains(urgentDate))
    XCTAssertEqual(DeadlineSnapshot.remainingHours(deadline, at: urgentDate), 0)
  }

  func testDistantDeadlinesUpdateHoursAndDaysWhileHostIsClosed() {
    let deadline = item("distant", seconds: 49 * 3600 + 1800)
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [deadline])
    let dates = snapshot.timelineDates(after: now)
    let firstTransition = now.addingTimeInterval(1801)
    let dayTransition = now.addingTimeInterval(5401)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(deadline, at: now), 49)
    XCTAssertTrue(dates.contains(firstTransition))
    XCTAssertTrue(dates.contains(dayTransition))
    XCTAssertEqual(DeadlineSnapshot.remainingHours(deadline, at: firstTransition), 48)
    XCTAssertEqual(DeadlineSnapshot.remainingHours(deadline, at: dayTransition), 47)
    XCTAssertTrue(dates.contains(now.addingTimeInterval(23 * 3600 + 1801)))
    XCTAssertEqual(dates.last, now.addingTimeInterval(24 * 3600))
  }

  func testDateLabelsUseLocalCalendarAndIncludeYearAcrossYearBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let now = ISO8601DateFormatter().date(from: "2026-12-31T15:30:00Z")!
    let due = ISO8601DateFormatter().date(from: "2026-12-31T16:10:00Z")!
    let locale = Locale(identifier: "zh_CN")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: now, compact: true, calendar: calendar, locale: locale), "2027/01/01 00:10")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: now, compact: false, calendar: calendar, locale: locale), "2027/01/01 00:10")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: now, compact: true, calendar: calendar, locale: locale), "今天 16:10")
  }

  func testTimelineRefreshesLocalDateAtMidnight() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let now = ISO8601DateFormatter().date(from: "2026-10-12T15:30:00Z")!
    let due = ISO8601DateFormatter().date(from: "2026-10-12T16:10:00Z")!
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [DeadlineItem(id: "a", kind: .exam, title: "Exam", subtitle: "Course", dueAt: due.timeIntervalSince1970)])
    let midnight = ISO8601DateFormatter().date(from: "2026-10-12T16:00:00Z")!
    XCTAssertTrue(snapshot.timelineDates(after: now, calendar: calendar).contains(midnight))
    let locale = Locale(identifier: "zh_CN")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: now, compact: true, calendar: calendar, locale: locale), "明天 00:10")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: midnight, compact: true, calendar: calendar, locale: locale), "今天 00:10")
  }

  func testGroupsByLocalDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    // 23:30 local: an hour later is already tomorrow.
    let now = ISO8601DateFormatter().date(from: "2026-10-12T15:30:00Z")!
    let items = [0.25, 1, 20, 72, 24 * 6.5, 24 * 7].enumerated().map { index, hours in
      DeadlineItem(id: "\(index)", kind: .assignment, title: "A", subtitle: "",
                   dueAt: now.timeIntervalSince1970 + hours * 3600)
    }
    let groups = DeadlineDay.group(items, at: now, calendar: calendar)
    XCTAssertEqual(groups.map(\.day), [.today, .tomorrow, .nextWeek, .later])
    XCTAssertEqual(groups.map { $0.items.map(\.id) }, [["0"], ["1", "2"], ["3"], ["4", "5"]])
  }

  func testRemainingGetsCoarserFurtherOut() {
    XCTAssertEqual(DeadlineRemaining(hours: 0), .dueSoon)
    XCTAssertEqual(DeadlineRemaining(hours: 23), .hours(23))
    XCTAssertEqual(DeadlineRemaining(hours: 29), .daysHours(1, 5))
    XCTAssertEqual(DeadlineRemaining(hours: 48 + 13), .days(2))
    XCTAssertTrue(DeadlineRemaining(hours: 5).isUrgent)
    XCTAssertFalse(DeadlineRemaining(hours: 29).isUrgent)
  }

  func testWeekdayLabelSkipsRelativeDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let now = ISO8601DateFormatter().date(from: "2026-11-03T02:00:00Z")!
    let sunday = ISO8601DateFormatter().date(from: "2026-11-08T15:59:00Z")!
    let tomorrow = ISO8601DateFormatter().date(from: "2026-11-04T15:59:00Z")!
    let zh = Locale(identifier: "zh_CN")
    XCTAssertEqual(DeadlineDateLabel.string(for: sunday, at: now, compact: true, weekday: true,
                                            calendar: calendar, locale: zh), "11/08 周日 23:59")
    XCTAssertEqual(DeadlineDateLabel.string(for: sunday, at: now, compact: true, weekday: true,
                                            calendar: calendar, locale: Locale(identifier: "en_US")), "11/08 Sun 23:59")
    XCTAssertEqual(DeadlineDateLabel.string(for: tomorrow, at: now, compact: true, weekday: true,
                                            calendar: calendar, locale: zh), "明天 23:59")
  }

  func testAtomicStoreKeepsLastValidSnapshotAndClears() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DeadlineSnapshotStore(directory: directory)
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [item("a", seconds: 3600)])
    XCTAssertTrue(try store.write(JSONEncoder().encode(snapshot)))
    let unchanged = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970 + 10, items: snapshot.items)
    XCTAssertFalse(try store.write(JSONEncoder().encode(unchanged)))
    XCTAssertThrowsError(try store.write(Data("{}".utf8)))
    guard case .ready(let saved) = store.read() else { return XCTFail("Missing valid snapshot") }
    XCTAssertEqual(saved, snapshot)
    XCTAssertTrue(try store.clear())
    XCTAssertFalse(try store.clear())
  }
}
