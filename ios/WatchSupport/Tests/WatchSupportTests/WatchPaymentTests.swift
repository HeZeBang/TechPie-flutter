import XCTest
@testable import WatchSupport

final class WatchPaymentTests: XCTestCase {
  private func success(_ fields: [String: Any] = [:], path: String = "/pages/common/success/success") -> [String: Any] {
    ["success": true, "url": path,
      "data": ["status": "1", "message": "支付成功", "txamt": "8.80"].merging(fields) { _, new in new }]
  }

  func testBothVerifiedSuccessDestinationsConfirmExactYuanAmount() throws {
    for path in ["/pages/common/success/success", "/pages/common/paysuccess/paysuccess"] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(path: path)), .completed(amountFen: 880))
    }
    for (amount, fen) in [("0", 0), ("0.01", 1), ("12.3400", 1234), ("128.60", 12860)] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(["txamt": amount])),
        .completed(amountFen: fen))
    }
    XCTAssertEqual(try WatchPaymentResult.decode(success(["txamt": 880])), .completed(amountFen: 88000))
  }

  func testQuerySuccessAndAmountAloneCannotConfirmPayment() throws {
    XCTAssertEqual(try WatchPaymentResult.decode(["success": true, "data": ["status": 1, "txamt": "8.80"]]), .pending)
    for path in ["/pages/common/payfail/payfail", "/unknown", "/pages/common/success/success/extra"] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(path: path)), .notCompleted)
    }
    for status in [2, true, false] as [Any] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(["status": status])), .notCompleted)
    }
    var response = success()
    response["data"] = ["status": 1, "message": "支付成功"]
    XCTAssertEqual(try WatchPaymentResult.decode(response), .notCompleted)
  }

  func testOuterAndNestedRejectionsCannotConfirmPayment() throws {
    for rejected in [false, "false", "1", 2] as [Any] {
      var response = success(); response["success"] = rejected
      XCTAssertEqual(try WatchPaymentResult.decode(response), .notCompleted)
      XCTAssertEqual(try WatchPaymentResult.decode(success(["success": rejected])), .notCompleted)
    }
    var numeric = success(); numeric["success"] = 1
    XCTAssertEqual(try WatchPaymentResult.decode(numeric), .completed(amountFen: 880))
  }

  func testUnusedCodeTakesPrecedenceOverPaymentFailureWords() throws {
    for message in ["支付失败，付款码未使用", "交易失败，付款码未被使用", "payment failed: not yet used", "unused"] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(["message": message])), .pending)
    }
    XCTAssertEqual(try WatchPaymentResult.decode(success(["status": 5])), .pending)
    XCTAssertEqual(try WatchPaymentResult.decode(success(["status": 3])), .expired)
  }

  func testBusinessFailuresAndFailureUrlMessageNeverAnimateSuccess() throws {
    for message in ["支付失败", "密码错误", "wrong password", "payment declined"] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(["message": message])), .notCompleted)
    }
    XCTAssertEqual(try WatchPaymentResult.decode(success(path: "/pages/common/success/success?message=wrong%20password")), .notCompleted)
    for message in ["开放平台返回失败", "开放平台请求超时"] {
      XCTAssertEqual(try WatchPaymentResult.decode(success(["message": message])), .useOffline)
    }
  }

  func testMalformedNegativeFractionalAndOverflowAmountsAreRejected() {
    for value in ["-1", "1.001", "8.8oops", "", "NaN", "1e3", "9999999999999999999999999999", true] as [Any] {
      XCTAssertThrowsError(try WatchPaymentResult.decode(success(["txamt": value])))
    }
  }

  func testSchedulePollsEveryFiveSecondsAndRefreshesAtExpiry() {
    let start = Date(timeIntervalSince1970: 1000)
    var schedule = WatchPaymentSchedule(refreshAt: start.addingTimeInterval(30), online: true, now: start)
    XCTAssertEqual(schedule.nextAction(now: start, automaticallyChecking: true, lowPowerMode: false), .wait(5))
    for offset in [5, 10, 15, 20] {
      let now = start.addingTimeInterval(Double(offset))
      XCTAssertEqual(schedule.nextAction(now: now, automaticallyChecking: true, lowPowerMode: false), .poll)
      schedule.didPoll(now: now, failed: false)
    }
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(25), automaticallyChecking: true, lowPowerMode: false), .wait(5))
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(30), automaticallyChecking: true, lowPowerMode: false), .refresh)
  }

  func testDisabledAndOfflineSchedulesOnlyWakeForRefresh() {
    let start = Date(timeIntervalSince1970: 1000)
    for online in [true, false] {
      let schedule = WatchPaymentSchedule(refreshAt: start.addingTimeInterval(30), online: online, now: start)
      XCTAssertEqual(schedule.nextAction(now: start, automaticallyChecking: false, lowPowerMode: false), .wait(30))
      XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(30), automaticallyChecking: false, lowPowerMode: false), .refresh)
      if !online {
        XCTAssertEqual(schedule.nextAction(now: start, automaticallyChecking: true, lowPowerMode: false), .wait(30))
      }
    }
  }

  func testLowPowerModeChecksLessOftenAndCannotDelayExpiry() {
    let start = Date(timeIntervalSince1970: 1000)
    var schedule = WatchPaymentSchedule(refreshAt: start.addingTimeInterval(30), online: true, now: start)
    XCTAssertEqual(schedule.nextAction(now: start, automaticallyChecking: true, lowPowerMode: true), .wait(10))
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(5), automaticallyChecking: true, lowPowerMode: true), .wait(5))
    schedule.didPoll(now: start.addingTimeInterval(10), failed: false)
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(10), automaticallyChecking: true, lowPowerMode: true), .wait(10))
    schedule.didPoll(now: start.addingTimeInterval(20), failed: false)
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(20), automaticallyChecking: true, lowPowerMode: true), .wait(10))
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(40), automaticallyChecking: true, lowPowerMode: true), .refresh)
  }

  func testFailedChecksBackOffAndSuccessfulCheckResetsInterval() {
    let start = Date(timeIntervalSince1970: 1000)
    var schedule = WatchPaymentSchedule(refreshAt: start.addingTimeInterval(90), online: true, now: start)
    schedule.didPoll(now: start, failed: true)
    XCTAssertEqual(schedule.nextAction(now: start, automaticallyChecking: true, lowPowerMode: false), .wait(10))
    schedule.didPoll(now: start.addingTimeInterval(10), failed: true)
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(10), automaticallyChecking: true, lowPowerMode: false), .wait(20))
    schedule.didPoll(now: start.addingTimeInterval(30), failed: false)
    XCTAssertEqual(schedule.nextAction(now: start.addingTimeInterval(30), automaticallyChecking: true, lowPowerMode: false), .wait(5))
  }
}
