import XCTest
@testable import WatchSupport

final class WatchOnlineCodeTests: XCTestCase {
  private func account(method: String = "wechat_openid") -> WatchOnlineAccount {
    WatchOnlineAccount(openID: "SYNTHETIC_OPENID_0123456789", method: method,
      idSerial: "SYNTHETIC-CARD", cardID: "SYNTHETIC-CARD-ID",
      sessionEndpoint: "https://example.invalid/api/auth/third-party/ecard")
  }

  private func fixture() throws -> WatchSnapshot {
    let url = Bundle.module.url(forResource: "dart-grant", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(WatchSnapshot.self, from: Data(contentsOf: url))
  }

  func testCipherMatchesExistingDartAndOpenSSLVector() throws {
    let json = Data("{\"code\":\"abc\",\"n\":1}".utf8)
    let envelope = try WatchEcardCipher.encodeJSON(json, key: "AbCdEfGhIjKlMnOp")
    XCTAssertEqual(envelope, "jIhGfEdCbApOnMlKxon/WjfDlQ4cQy8wUg4Iz8a71vR0PtdnPN+VpQ3WT3k=")
    let decoded = try WatchEcardCipher.decodeEnvelope(envelope)
    XCTAssertEqual(decoded["code"] as? String, "abc")
    XCTAssertEqual(decoded["n"] as? Int, 1)
    for invalid in ["short", "jIhGfEdCbApOnMlK***", "jIhGfEdCbApOnMlKAAAA", "****************AAAA"] {
      XCTAssertThrowsError(try WatchEcardCipher.decodeEnvelope(invalid))
    }
  }

  func testSnapshotPersistsOnlineAccountAndRejectsMismatchedOrRevokedParameters() throws {
    var snapshot = try fixture()
    XCTAssertNil(snapshot.onlineAccount)
    snapshot.onlineAccount = account()
    snapshot.subject = account().subject
    try snapshot.validate()
    let restored = try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertEqual(restored.onlineAccount, account())
    snapshot.onlineAccount?.idSerial = "ANOTHER-STUDENT"
    XCTAssertThrowsError(try snapshot.validate())
    snapshot.onlineAccount = account()
    snapshot.subject = "OTHER"
    XCTAssertThrowsError(try snapshot.validate())
    snapshot.enabled = false; snapshot.card = nil; snapshot.credential = nil; snapshot.subject = nil
    XCTAssertThrowsError(try snapshot.validate())
    snapshot.onlineAccount = nil
    try snapshot.validate()
  }

  func testRejectsUnsafeEndpointsAndUnknownLoginChannels() throws {
    for endpoint in ["http://example.invalid/api/auth/third-party/ecard",
      "https://user:pass@example.invalid/api/auth/third-party/ecard",
      "https://example.invalid/api/auth/third-party/ecard?token=x", "https://example.invalid/other"] {
      var value = account(); value.sessionEndpoint = endpoint
      XCTAssertThrowsError(try value.validate())
    }
    XCTAssertThrowsError(try account(method: "unknown").validate())
    XCTAssertNotEqual(account().subject, account(method: "alipay_openid").subject)
  }

  func testWatchAcquiresOwnSessionAndRequestsEncryptedCodeWithoutPhoneCookie() async throws {
    for (method, userType, subject) in [
      ("wechat_openid", "8", "cc64076d7631233ac425307f95e1fa9752723c78efdc9632e2adf7465b229d96"),
      ("alipay_openid", "18", "4bd16fe8924f3ef8971b92b18e7286541b10b33b3e61947178b5066a300d1bc2")
    ] {
      XCTAssertEqual(account(method: method).subject, subject)
      let transport = ScriptedTransport([.session(), .quota(), .code()])
      let client = WatchOnlineCodeClient(account: account(method: method), transport: transport)
      let frame = try await client.generate()
      XCTAssertEqual(frame.balanceFen, 12860)
      XCTAssertEqual(frame.matrix.modules, try OfflineCode.qr(Data(strictHex: "5638A1B2C3D4")).modules)
      let requests = await transport.requests
      XCTAssertEqual(requests.map { $0.url!.path }, ["/api/auth/third-party/ecard", "/virtualcard/openQrcodeQuotaModify", "/offlineCode/openVirtualcard"])
      XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
      let login = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: String]
      XCTAssertEqual(login["openid"], account().openID)
      XCTAssertEqual(login["method"], method)
      XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Cookie"), "JSESSIONID=watch-only")
      XCTAssertEqual(requests[2].value(forHTTPHeaderField: "orgid"), "2")
      let envelope = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: String]
      let payload = try WatchEcardCipher.decodeEnvelope(envelope["datajson"]!)
      XCTAssertEqual(payload["openid"] as? String, account().openID)
      XCTAssertEqual(payload["usertype"] as? String, userType)
    }
  }

  func testSessionIsReusedThenRenewedAfterThirtyMinutesIdle() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .code(), .session(), .quota(), .code()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let now = Date()
    _ = try await client.generate(now: now)
    _ = try await client.generate(now: now.addingTimeInterval(60))
    _ = try await client.generate(now: now.addingTimeInterval(1860))
    let requests = await transport.requests
    XCTAssertEqual(requests.filter { $0.url!.host == "example.invalid" }.count, 2)
    XCTAssertEqual(requests.count, 7)
  }

  func testUnauthorizedCodeRefreshesSessionOnce() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .http(401),
      .session(cookie: "JSESSIONID=renewed-watch"), .quota(), .code()])
    _ = try await WatchOnlineCodeClient(account: account(), transport: transport).generate()
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 6)
    XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=renewed-watch")
    let rejected = ScriptedTransport([.session(), .quota(), .http(401), .session(), .quota(), .http(401)])
    do {
      _ = try await WatchOnlineCodeClient(account: account(), transport: rejected).generate()
      XCTFail("Repeated authentication failure produced a code")
    } catch let error as WatchOnlineFailure { XCTAssertEqual(error, .authentication) }
    let failedRequests = await rejected.requests
    XCTAssertEqual(failedRequests.count, 6)
  }

  func testIdentityMismatchNeverProducesCodeOrBecomesOfflineFallback() async throws {
    for responses in [[Reply.session(student: "OTHER")], [.session(), .quota(student: "OTHER")],
      [.session(), .quota(), .code(student: "OTHER")]] {
      let transport = ScriptedTransport(responses)
      do {
        _ = try await WatchOnlineCodeClient(account: account(), transport: transport).generate()
        XCTFail("Identity mismatch was accepted")
      } catch let error as WatchOnlineFailure {
        XCTAssertEqual(error, .identityMismatch)
        XCTAssertFalse(error.permitsOfflineFallback)
      }
    }
  }

  func testNetworkAndServerFailuresPermitFallbackButBusinessRejectionDoesNot() async throws {
    for (reply, expected, permitsFallback) in [(Reply.network, WatchOnlineFailure.network, true),
      (.http(503), .server, true), (.http(302), .server, true),
      (.body(["success": false, "message": "校园卡挂失"], encrypted: true), .rejected, false)] {
      let transport = ScriptedTransport([.session(), .quota(), reply])
      do {
        _ = try await WatchOnlineCodeClient(account: account(), transport: transport).generate()
        XCTFail("Failed response produced a code")
      } catch let error as WatchOnlineFailure {
        XCTAssertEqual(error, expected)
        XCTAssertEqual(error.permitsOfflineFallback, permitsFallback)
      }
    }
    XCTAssertFalse(WatchOnlineFailure.rejected.permitsOfflineFallback)
    XCTAssertFalse(WatchOnlineFailure.notActivated.permitsOfflineFallback)
  }

  func testConcurrentRefreshesShareOneLoginAndOneCodeRequest() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code()], slow: true)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    async let first = client.generate()
    async let second = client.generate()
    let (a, b) = try await (first, second)
    XCTAssertEqual(a.matrix.modules, b.matrix.modules)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 3)
  }

  func testPollingUsesTheWatchCodeAndSameSessionWithBoundedTimeout() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .payment()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let result = try await client.poll(frame)
    XCTAssertEqual(result, .completed(amountFen: 880))
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
    let request = requests[3]
    XCTAssertEqual(request.url?.path, "/virtualcard/queryOrderStatus")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), requests[2].value(forHTTPHeaderField: "Cookie"))
    XCTAssertEqual(request.timeoutInterval, 6)
    let envelope = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
    let payload = try WatchEcardCipher.decodeEnvelope(envelope["datajson"]!)
    XCTAssertEqual(payload["paycode"] as? String, "SYNTHETIC-PAYCODE")
    XCTAssertEqual(payload["openid"] as? String, account().openID)
    let repeated = try await client.poll(frame)
    XCTAssertEqual(repeated, .expired)
    let afterRepeat = await transport.requests
    XCTAssertEqual(afterRepeat.count, 4, "A consumed code cannot confirm payment twice")
  }

  func testExpiredOrReplacedCodeIsNeverPolled() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .code()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let old = try await client.generate()
    let expired = try await client.poll(old, now: old.expiresAt)
    XCTAssertEqual(expired, .expired)
    _ = try await client.generate()
    let replaced = try await client.poll(old)
    XCTAssertEqual(replaced, .expired)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
  }

  func testConcurrentChecksShareOneResultRequest() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .pending()], slow: true)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    async let first = client.poll(frame)
    async let second = client.poll(frame)
    let (a, b) = try await (first, second)
    XCTAssertEqual(a, .pending); XCTAssertEqual(b, .pending)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
  }

  func testFinalCheckFindsLatePaymentUsingTheOriginalSessionOnce() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .pending(), .payment()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let earlier = try await client.poll(frame, now: frame.generatedAt.addingTimeInterval(20))
    XCTAssertEqual(earlier, .pending)
    let expired = try await client.poll(frame, now: frame.expiresAt)
    XCTAssertEqual(expired, .expired)
    let final = try await client.finishChecking(frame, now: frame.expiresAt.addingTimeInterval(0.1))
    XCTAssertEqual(final, .completed(amountFen: 880))
    let repeated = try await client.finishChecking(frame)
    XCTAssertEqual(repeated, .expired)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 5)
    XCTAssertEqual(requests.last?.url?.path, "/virtualcard/queryOrderStatus")
    XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=watch-only")
  }

  func testManualReplacementChecksBeforeExpiryAndReleasesTheOldLease() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .pending(), .code()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let result = try await client.finishChecking(frame)
    XCTAssertEqual(result, .pending)
    let old = try await client.poll(frame)
    XCTAssertEqual(old, .expired)
    _ = try await client.generate()
    let requests = await transport.requests
    XCTAssertEqual(requests.map { $0.url!.path }, ["/api/auth/third-party/ecard",
      "/virtualcard/openQrcodeQuotaModify", "/offlineCode/openVirtualcard",
      "/virtualcard/queryOrderStatus", "/offlineCode/openVirtualcard"])
  }

  func testFinalCheckCannotQueryBeyondItsGracePeriodOrReauthenticate() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .http(401)])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let late = try await client.finishChecking(frame,
      now: frame.expiresAt.addingTimeInterval(WatchPaymentSchedule.pollTimeout))
    XCTAssertEqual(late, .expired)
    do { _ = try await client.finishChecking(frame); XCTFail("Authentication failure returned a result") }
    catch let error as WatchOnlineFailure { XCTAssertEqual(error, .authentication) }
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
  }

  func testFinalCheckUsesOnlyTheRemainingDeadlineAndCancelsSlowRequest() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .stall])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let started = ProcessInfo.processInfo.systemUptime
    do {
      _ = try await client.finishChecking(frame, now: frame.expiresAt.addingTimeInterval(5.95))
      XCTFail("A stalled final check returned a result")
    } catch let error as WatchOnlineFailure { XCTAssertEqual(error, .network) }
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
    let repeated = try await client.finishChecking(frame)
    XCTAssertEqual(repeated, .expired)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
    XCTAssertGreaterThan(requests.last!.timeoutInterval, 0)
    XCTAssertLessThan(requests.last!.timeoutInterval, 0.1)
  }

  func testCancellingAJoinedGenerationAlsoCancelsTheSharedRequest() async throws {
    let started = expectation(description: "Generation is waiting for transport")
    let transport = ScriptedTransport([.session(), .session(), .quota(), .code()], holdFirst: started)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let first = Task { try await client.generate() }
    await fulfillment(of: [started], timeout: 5)
    let joined = Task { try await client.generate() }
    try await Task.sleep(for: .milliseconds(50))
    joined.cancel()
    await transport.releaseFirst()
    for task in [first, joined] {
      do { _ = try await task.value; XCTFail("Cancelled shared generation produced a code") }
      catch is CancellationError {}
    }
    _ = try await client.generate()
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
  }

  func testCancellingAJoinedCheckAlsoCancelsTheSharedRequest() async throws {
    let started = expectation(description: "Result check is waiting for transport")
    let transport = ScriptedTransport([.session(), .quota(), .code(), .pending(), .pending()],
      holdFirst: started, holdRequest: 4)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let first = Task { try await client.poll(frame) }
    await fulfillment(of: [started], timeout: 5)
    let joined = Task { try await client.poll(frame) }
    try await Task.sleep(for: .milliseconds(50))
    joined.cancel()
    await transport.releaseFirst()
    for task in [first, joined] {
      do { _ = try await task.value; XCTFail("Cancelled shared query returned a result") }
      catch is CancellationError {}
    }
    let retry = try await client.poll(frame)
    XCTAssertEqual(retry, .pending)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 5)
  }

  func testPollAuthenticationFailureDoesNotLoginAndReplayOldCode() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .http(401), .session(), .quota(), .code()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    do { _ = try await client.poll(frame); XCTFail("Unexpected payment result") }
    catch let error as WatchOnlineFailure { XCTAssertEqual(error, .authentication) }
    let beforeRefresh = await transport.requests
    XCTAssertEqual(beforeRefresh.count, 4)
    _ = try await client.generate()
    let old = try await client.poll(frame)
    XCTAssertEqual(old, .expired)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 7)
  }

  func testTransientPollingFailureKeepsCodeLeaseForLaterCheck() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .network, .pending()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    do { _ = try await client.poll(frame); XCTFail("Network failure confirmed a result") }
    catch let error as WatchOnlineFailure { XCTAssertEqual(error, .network) }
    let later = try await client.poll(frame)
    XCTAssertEqual(later, .pending)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 5)
  }

  func testSlowCheckTimesOutAndCancelsItsRequest() async throws {
    let finished = expectation(description: "Result check respects total deadline")
    let transport = ScriptedTransport([.session(), .quota(), .code(), .stall, .pending()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let check = Task {
      defer { finished.fulfill() }
      do { _ = try await client.poll(frame); XCTFail("A stalled check returned a result") }
      catch let error as WatchOnlineFailure { XCTAssertEqual(error, .network) }
      catch { XCTFail("Unexpected error: \(error)") }
    }
    await fulfillment(of: [finished], timeout: 9)
    await check.value
    let retry = try await client.poll(frame)
    XCTAssertEqual(retry, .pending)
  }

  func testIdentityMismatchInPaymentResponseIsRejected() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .payment(student: "ANOTHER-STUDENT")])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    do { _ = try await client.poll(frame); XCTFail("Wrong owner confirmed a payment") }
    catch let error as WatchOnlineFailure { XCTAssertEqual(error, .identityMismatch) }
    let invalidated = try await client.poll(frame)
    XCTAssertEqual(invalidated, .expired)
  }

  func testCancelledCheckCannotReportSuccessAfterCodeReplacement() async throws {
    let started = expectation(description: "Held result check started")
    let transport = ScriptedTransport([.session(), .quota(), .code(), .payment(), .code()],
      holdFirst: started, holdRequest: 4)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    let poll = Task { try await client.poll(frame) }
    await fulfillment(of: [started], timeout: 5)
    _ = try await client.generate()
    await transport.releaseFirst()
    do { _ = try await poll.value; XCTFail("A cancelled old check reported payment") }
    catch is CancellationError {}
    let old = try await client.poll(frame)
    XCTAssertEqual(old, .expired)
  }

  func testServerCannotReissueTheAlreadyConsumedCode() async throws {
    let transport = ScriptedTransport([.session(), .quota(), .code(), .payment(), .code()])
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let frame = try await client.generate()
    _ = try await client.poll(frame)
    do { _ = try await client.generate(); XCTFail("A consumed code was displayed again") }
    catch let error as WatchOnlineFailure { XCTAssertEqual(error, .invalidResponse) }
  }

  func testRetryDoesNotWaitForACancelledRequest() async throws {
    let started = expectation(description: "First request started")
    let retried = expectation(description: "Retry completed before the cancelled request")
    let transport = ScriptedTransport([.http(200), .session(), .quota(), .code()], holdFirst: started)
    let client = WatchOnlineCodeClient(account: account(), transport: transport)
    let first = Task { try await client.generate() }
    await fulfillment(of: [started], timeout: 5)
    first.cancel()
    let retry = Task {
      defer { retried.fulfill() }
      return try await client.generate()
    }
    await fulfillment(of: [retried], timeout: 5)
    await transport.releaseFirst()
    do {
      _ = try await first.value
      XCTFail("Cancelled request produced a code")
    } catch is CancellationError {}
    let frame = try await retry.value
    XCTAssertEqual(frame.balanceFen, 12860)
    let requests = await transport.requests
    XCTAssertEqual(requests.count, 4)
  }

  func testOfflineGrantExpiryClearsOfflineCodeEvenWhenOnlineAccountRemainsAvailable() throws {
    var snapshot = try fixture()
    snapshot.onlineAccount = account(); snapshot.subject = account().subject
    snapshot.credential?.expiresAt = Date().addingTimeInterval(10).timeIntervalSince1970
    var state = WatchCodeDisplayState()
    state.reconcile(previous: nil, incoming: snapshot)
    state.setActive(true)
    state.finish(.success(QRMatrix(side: 1, modules: [1])), generation: state.beginGeneration()!)
    state.reconcile(previous: snapshot, incoming: snapshot, now: Date().addingTimeInterval(11))
    XCTAssertNil(state.matrix)
    XCTAssertFalse(state.requiresAuthorization)
  }

  func testAnOnlineRequestFinishingAfterSuspensionCannotExposeItsCode() throws {
    var snapshot = try fixture()
    snapshot.onlineAccount = account(); snapshot.subject = account().subject; snapshot.credential = nil
    var state = WatchCodeDisplayState()
    state.reconcile(previous: nil, incoming: snapshot)
    state.setActive(true)
    let ticket = state.beginGeneration()!
    state.setActive(false)
    state.finish(.success(QRMatrix(side: 1, modules: [1])), generation: ticket,
      kind: .online, expiresAt: Date().addingTimeInterval(30))
    XCTAssertNil(state.matrix)
    XCTAssertFalse(state.generating)
    XCTAssertFalse(state.requiresAuthorization)
  }
}

private enum Reply {
  case body([String: Any], encrypted: Bool), http(Int), network, stall
  static func session(cookie: String = "JSESSIONID=watch-only", student: String = "SYNTHETIC-CARD") -> Reply {
    .body(["success": true, "data": ["sid": student, "token": cookie,
      "raw": ["cookies": cookie, "idserial": student, "cardid": "SYNTHETIC-CARD-ID", "orgid": "2"]]], encrypted: false)
  }
  static func quota(student: String = "SYNTHETIC-CARD") -> Reply {
    .body(["success": true, "data": ["idserial": student, "cardid": "SYNTHETIC-CARD-ID"]], encrypted: true)
  }
  static func code(student: String = "SYNTHETIC-CARD") -> Reply {
    .body(["success": true, "data": ["code": "SYNTHETIC-PAYCODE", "qrcode": "5638A1B2C3D4",
      "cardbal": "128.60", "idserial": student, "cardid": "SYNTHETIC-CARD-ID"]], encrypted: true)
  }
  static func payment(student: String = "SYNTHETIC-CARD") -> Reply {
    .body(["success": true, "url": "/pages/common/success/success",
      "data": ["status": "1", "txamt": "8.80", "message": "支付成功", "idserial": student]], encrypted: true)
  }
  static func pending() -> Reply {
    .body(["success": true, "data": ["status": 5, "message": "支付失败，付款码未使用"]], encrypted: true)
  }
}

private actor ScriptedTransport: WatchHTTPTransport {
  private var replies: [Reply]
  private let slow: Bool
  private let holdFirst: XCTestExpectation?
  private let holdRequest: Int
  private var firstContinuation: CheckedContinuation<Void, Never>?
  private(set) var requests: [URLRequest] = []
  init(_ replies: [Reply], slow: Bool = false, holdFirst: XCTestExpectation? = nil, holdRequest: Int = 1) {
    self.replies = replies; self.slow = slow; self.holdFirst = holdFirst
    self.holdRequest = holdRequest
  }
  func releaseFirst() { firstContinuation?.resume(); firstContinuation = nil }
  func send(_ request: URLRequest) async throws -> WatchHTTPResponse {
    requests.append(request)
    guard !replies.isEmpty else { throw URLError(.badServerResponse) }
    let reply = replies.removeFirst()
    if requests.count == holdRequest, let holdFirst {
      await withCheckedContinuation { continuation in
        firstContinuation = continuation
        holdFirst.fulfill()
      }
    }
    if slow { try await Task.sleep(for: .milliseconds(10)) }
    switch reply {
    case .stall:
      try await Task.sleep(for: .seconds(60))
      throw URLError(.timedOut)
    case .network: throw URLError(.notConnectedToInternet)
    case .http(let status): return WatchHTTPResponse(status: status, data: Data())
    case .body(let body, let encrypted):
      let json = try JSONSerialization.data(withJSONObject: body)
      let response = encrypted ? try JSONSerialization.data(withJSONObject: ["datajson": WatchEcardCipher.encodeJSON(json, key: "AbCdEfGhIjKlMnOp")]) : json
      return WatchHTTPResponse(status: 200, data: response)
    }
  }
}
