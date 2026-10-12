import XCTest
@testable import DeadlineWidgetSupport

final class DeadlineSnapshotTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1780000000)
  private func item(_ id: String, seconds: Double) -> DeadlineItem {
    DeadlineItem(id: id, kind: .assignment, title: "Synthetic assignment", course: "Synthetic course", dueAt: now.timeIntervalSince1970 + seconds)
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

  func testTimelineIncludesImminentAndExpiryBoundaries() {
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [item("soon", seconds: 60), item("later", seconds: 30 * 3600)])
    let dates = snapshot.timelineDates(after: now)
    for date in [now, now.addingTimeInterval(60), now.addingTimeInterval(6 * 3600), now.addingTimeInterval(24 * 3600)] {
      XCTAssertTrue(dates.contains(date))
    }
    XCTAssertEqual(dates, dates.sorted())
    XCTAssertTrue(DeadlineSnapshot.isImminent(item("24h", seconds: 24 * 3600), at: now))
    XCTAssertFalse(DeadlineSnapshot.isImminent(item("24h+", seconds: 24 * 3600 + 1), at: now))
    XCTAssertFalse(DeadlineSnapshot.isImminent(item("expired", seconds: 0), at: now))
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
    object["items"] = [["id": "a", "kind": "exam", "title": "Exam", "course": "Course", "dueAt": -10]]
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
    object["items"] = [["id": "a", "kind": "assignment", "title": "A", "course": "C", "dueAt": "tomorrow"]]
    XCTAssertThrowsError(try DeadlineSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
  }

  func testRemainingTimeUsesFullHoursAndUrgencyBelowOneHour() {
    XCTAssertNil(DeadlineSnapshot.remainingHours(item("later", seconds: 24 * 3600 + 1), at: now))
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
    let snapshot = DeadlineSnapshot(writtenAt: now.timeIntervalSince1970, items: [DeadlineItem(id: "a", kind: .exam, title: "Exam", course: "Course", dueAt: due.timeIntervalSince1970)])
    let midnight = ISO8601DateFormatter().date(from: "2026-10-12T16:00:00Z")!
    XCTAssertTrue(snapshot.timelineDates(after: now, calendar: calendar).contains(midnight))
    let locale = Locale(identifier: "zh_CN")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: now, compact: true, calendar: calendar, locale: locale), "明天 00:10")
    XCTAssertEqual(DeadlineDateLabel.string(for: due, at: midnight, compact: true, calendar: calendar, locale: locale), "今天 00:10")
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
