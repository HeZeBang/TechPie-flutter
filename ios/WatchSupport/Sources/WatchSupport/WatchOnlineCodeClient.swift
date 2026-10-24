import Foundation

public struct WatchHTTPResponse: Sendable {
  public let status: Int
  public let data: Data
  public init(status: Int, data: Data) { self.status = status; self.data = data }
}

public protocol WatchHTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> WatchHTTPResponse
}

/// Redirects cannot move OPENID/cookies to a different endpoint.
public final class WatchURLSessionTransport: WatchHTTPTransport, @unchecked Sendable {
  private let session: URLSession
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 25
    configuration.timeoutIntervalForResource = 30
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
  }
  deinit { session.invalidateAndCancel() }

  public func send(_ request: URLRequest) async throws -> WatchHTTPResponse {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, data.count <= 131_072 else {
      throw WatchOnlineFailure.invalidResponse
    }
    return WatchHTTPResponse(status: response.statusCode, data: data)
  }

  private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void) {
      completionHandler(nil)
    }
  }
}

public struct WatchOnlineCode: Sendable {
  public let id: UUID
  public let matrix: QRMatrix
  public let balanceFen: Int?
  public let generatedAt: Date
  public var expiresAt: Date { generatedAt.addingTimeInterval(30) }
}

/// Runs on the watch's network connection. No phone request or phone cookie is used.
public actor WatchOnlineCodeClient {
  private struct Session {
    let cookie: String
    var lastUsed: Date
  }
  private struct CodeLease {
    let frameID: UUID
    let payCode: String
    let cookie: String
  }
  private let account: WatchOnlineAccount
  private let transport: any WatchHTTPTransport
  private var session: Session?
  private var inFlight: (id: UUID, task: Task<WatchOnlineCode, Error>)?
  private var codeLease: CodeLease?
  private var completedPayCode: String?
  private var finishedFrameID: UUID?
  private var pollInFlight: (id: UUID, frameID: UUID, task: Task<WatchPaymentResult, Error>)?

  public init(account: WatchOnlineAccount, transport: any WatchHTTPTransport = WatchURLSessionTransport()) {
    self.account = account
    self.transport = transport
  }

  public func generate(now: Date = Date()) async throws -> WatchOnlineCode {
    if let inFlight, !inFlight.task.isCancelled {
      return try await withTaskCancellationHandler(operation: { try await inFlight.task.value },
        onCancel: { inFlight.task.cancel() })
    }
    pollInFlight?.task.cancel()
    codeLease = nil
    let id = UUID()
    let task = Task { try await generateCode(now: now) }
    inFlight = (id, task)
    defer { if inFlight?.id == id { inFlight = nil } }
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
  }

  public func fetchCard(now: Date = Date()) async throws -> WatchCard {
    do {
      try account.validate()
      for attempt in 0..<2 {
        try Task.checkCancellation()
        do {
          let cookie = try await sessionCookie(now: now)
          let response = try await campusRequest("/myaccount/openMyAccountApp", cookie: cookie, payload: [:])
          try validateIdentity(response)
          guard success(response) else { throw WatchOnlineFailure.rejected }
          let data = response["data"] as? [String: Any] ?? response
          guard let card = data["cardinfo"] as? [String: Any],
            nonempty(card["idserial"]) == account.idSerial else { throw WatchOnlineFailure.identityMismatch }
          let user = data["userInfo"] as? [String: Any]
          guard let name = nonempty(card["username"]) ?? nonempty(user?["username"]),
            let balanceFen = balance(card["cardbal"]) else { throw WatchOnlineFailure.invalidResponse }
          let status = nonempty(card["accstatusStr"]) ?? nonempty(card["accstatus"])
          return WatchCard(name: name, studentID: account.idSerial, balanceFen: balanceFen,
            updatedAt: Date().timeIntervalSince1970, permitsPayment: status == "正常" || status == "1")
        } catch WatchOnlineFailure.authentication where attempt == 0 { session = nil; codeLease = nil }
      }
      throw WatchOnlineFailure.authentication
    } catch is CancellationError { throw CancellationError() }
    catch let error as WatchOnlineFailure {
      if error == .authentication || error == .identityMismatch { session = nil; codeLease = nil }
      throw error
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw WatchOnlineFailure.network
    } catch { throw WatchOnlineFailure.invalidResponse }
  }

  public func canResume(_ frame: WatchOnlineCode) -> Bool {
    guard let lease = codeLease else { return false }
    return frame.expiresAt > Date() && lease.frameID == frame.id && session?.cookie == lease.cookie
  }

  public func poll(_ frame: WatchOnlineCode, now: Date = Date()) async throws -> WatchPaymentResult {
    try await checkOrder(frame, validUntil: frame.expiresAt, now: now, timeout: WatchPaymentSchedule.pollTimeout)
  }

  /// One final query before replacement, bound to the old code's original session.
  public func finishChecking(_ frame: WatchOnlineCode, now: Date = Date()) async throws -> WatchPaymentResult {
    let deadline = frame.expiresAt.addingTimeInterval(WatchPaymentSchedule.pollTimeout)
    guard deadline > now, codeLease?.frameID == frame.id, finishedFrameID != frame.id else { return .expired }
    finishedFrameID = frame.id
    defer { if codeLease?.frameID == frame.id { codeLease = nil } }
    return try await checkOrder(frame, validUntil: deadline, now: now,
      timeout: min(WatchPaymentSchedule.pollTimeout, deadline.timeIntervalSince(now)))
  }

  private func checkOrder(_ frame: WatchOnlineCode, validUntil: Date, now: Date,
    timeout: TimeInterval) async throws -> WatchPaymentResult {
    guard let lease = codeLease, lease.frameID == frame.id, session?.cookie == lease.cookie,
      validUntil > now else { return .expired }
    if let pollInFlight, pollInFlight.frameID == frame.id, !pollInFlight.task.isCancelled {
      return try await withTaskCancellationHandler(operation: { try await pollInFlight.task.value },
        onCancel: { pollInFlight.task.cancel() })
    }
    let id = UUID()
    let task = Task { try await pollOrder(lease, timeout: timeout) }
    pollInFlight = (id, frame.id, task)
    defer { if pollInFlight?.id == id { pollInFlight = nil } }
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
  }

  private func pollOrder(_ lease: CodeLease, timeout: TimeInterval) async throws -> WatchPaymentResult {
    do {
      // Never reauthenticate/replay a result query under a different session.
      let response = try await campusRequest("/virtualcard/queryOrderStatus", cookie: lease.cookie,
        payload: ["openid": account.openID, "paycode": lease.payCode], timeout: timeout)
      try validateIdentity(response)
      guard codeLease?.frameID == lease.frameID, session?.cookie == lease.cookie else { return .expired }
      let result = try WatchPaymentResult.decode(response)
      if case .completed = result { completedPayCode = lease.payCode }
      if result != .pending { codeLease = nil }
      session?.lastUsed = Date()
      return result
    } catch is CancellationError { throw CancellationError() }
    catch let error as WatchOnlineFailure {
      if error == .authentication || error == .identityMismatch { session = nil; codeLease = nil }
      throw error
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw WatchOnlineFailure.network
    } catch { throw WatchOnlineFailure.invalidResponse }
  }

  private func generateCode(now: Date) async throws -> WatchOnlineCode {
    do {
      try account.validate()
      for attempt in 0..<2 {
        try Task.checkCancellation()
        do {
          let cookie = try await sessionCookie(now: now)
          let response = try await campusRequest("/offlineCode/openVirtualcard", cookie: cookie,
            payload: ["openid": account.openID, "usertype": account.userType, "appcode": "1"])
          try validateIdentity(response)
          guard success(response) else {
            let message = response["message"] as? String ?? response["msg"] as? String ?? ""
            if message.contains("未开通") { throw WatchOnlineFailure.notActivated }
            throw WatchOnlineFailure.rejected
          }
          guard let data = response["data"] as? [String: Any],
            let payCode = nonempty(data["code"]) else { throw WatchOnlineFailure.invalidResponse }
          guard payCode != completedPayCode else { throw WatchOnlineFailure.invalidResponse }
          let raw = nonempty(data["qrcode"]) ?? payCode
          let payload: Data
          if raw.hasPrefix("5638") { payload = try Data(strictHex: raw) }
          else { payload = Data(raw.utf8) }
          guard payload.count <= 2953 else { throw WatchOnlineFailure.invalidResponse }
          try Task.checkCancellation()
          // The validity window starts when the code is received, after login/network latency.
          let frame = WatchOnlineCode(id: UUID(), matrix: try OfflineCode.qr(payload),
            balanceFen: balance(data["cardbal"]), generatedAt: Date())
          codeLease = CodeLease(frameID: frame.id, payCode: payCode, cookie: cookie)
          return frame
        } catch WatchOnlineFailure.authentication where attempt == 0 {
          session = nil
        }
      }
      throw WatchOnlineFailure.authentication
    } catch is CancellationError { throw CancellationError() }
    catch let error as WatchOnlineFailure {
      if error == .authentication || error == .identityMismatch { session = nil }
      throw error
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw WatchOnlineFailure.network
    } catch { throw WatchOnlineFailure.invalidResponse }
  }

  private func sessionCookie(now: Date) async throws -> String {
    if let current = session, (0..<1800).contains(now.timeIntervalSince(current.lastUsed)) {
      session?.lastUsed = now
      return current.cookie
    }
    session = nil; codeLease = nil
    let acquired = try await acquireSession(now: now)
    session = acquired
    return acquired.cookie
  }

  private func acquireSession(now: Date) async throws -> Session {
    let endpoint = URL(string: account.sessionEndpoint)!
    let response = try await request(endpoint, payload: ["method": account.method, "openid": account.openID])
    guard response["success"] as? Bool == true,
      let data = response["data"] as? [String: Any], let raw = data["raw"] as? [String: Any],
      let cookie = data["token"] as? String, validCookie(cookie), raw["cookies"] as? String == cookie,
      data["sid"] as? String == account.idSerial, raw["idserial"] as? String == account.idSerial,
      raw["cardid"] as? String == account.cardID, raw["orgid"] as? String == "2" else {
      throw WatchOnlineFailure.identityMismatch
    }
    let quota = try await campusRequest("/virtualcard/openQrcodeQuotaModify", cookie: cookie,
      payload: ["openid": account.openID])
    try validateIdentity(quota)
    let fields = quota["data"] as? [String: Any] ?? quota
    guard success(quota), nonempty(fields["idserial"]) == account.idSerial,
      nonempty(fields["cardid"]) == account.cardID else { throw WatchOnlineFailure.identityMismatch }
    return Session(cookie: cookie, lastUsed: now)
  }

  private func campusRequest(_ path: String, cookie: String, payload: [String: String], timeout: TimeInterval = 25) async throws -> [String: Any] {
    let url = URL(string: "https://ecard.shanghaitech.edu.cn" + path)!
    let response = try await request(url, payload: ["datajson": WatchEcardCipher.encode(payload)], cookie: cookie, timeout: timeout)
    let text = [response["message"], response["msg"]].compactMap { $0 as? String }.joined(separator: " ")
    if !success(response) && (text.contains("未登录") || text.contains("登录失效") || text.contains("登录过期") ||
      text.lowercased().contains("session expired") || text.lowercased().contains("not logged in")) {
      throw WatchOnlineFailure.authentication
    }
    return response
  }

  private func request(_ url: URL, payload: [String: String], cookie: String? = nil, timeout: TimeInterval = 25) async throws -> [String: Any] {
    try Task.checkCancellation()
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let cookie {
      request.setValue(cookie, forHTTPHeaderField: "Cookie")
      request.setValue("2", forHTTPHeaderField: "orgid")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let response: WatchHTTPResponse
    if timeout <= WatchPaymentSchedule.pollTimeout {
      let transport = self.transport
      response = try await withThrowingTaskGroup(of: WatchHTTPResponse.self) { group in
        group.addTask { try await transport.send(request) }
        group.addTask {
          try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
          throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        return try await group.next()!
      }
    } else { response = try await transport.send(request) }
    try Task.checkCancellation()
    if response.status == 401 || response.status == 403 { throw WatchOnlineFailure.authentication }
    guard response.status == 200 else { throw WatchOnlineFailure.server }
    return try WatchEcardCipher.decode(response.data)
  }

  private func validCookie(_ cookie: String) -> Bool {
    cookie.hasPrefix("JSESSIONID=") && cookie.count > 11 && cookie.utf8.allSatisfy {
      (33...126).contains($0) && ![34, 44, 59, 92].contains($0)
    }
  }

  private func validateIdentity(_ value: Any) throws {
    if let list = value as? [Any] { for item in list { try validateIdentity(item) } }
    guard let map = value as? [String: Any] else { return }
    for (name, value) in map {
      if let field = nonempty(value) {
        if name.lowercased() == "idserial" && field != account.idSerial { throw WatchOnlineFailure.identityMismatch }
        if name.lowercased() == "cardid" && field != account.cardID { throw WatchOnlineFailure.identityMismatch }
      }
      try validateIdentity(value)
    }
  }

  private func success(_ response: [String: Any]) -> Bool {
    if let value = response["success"] as? Bool { return value }
    return nonempty(response["success"])?.lowercased() == "true"
  }

  private func nonempty(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    let text = (value as? String ?? (value as? NSNumber)?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private func balance(_ value: Any?) -> Int? {
    guard let text = nonempty(value), let yuan = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    var amount = yuan * 100
    var rounded = Decimal()
    NSDecimalRound(&rounded, &amount, 0, .plain)
    guard rounded >= 0, rounded <= Decimal(Int.max) else { return nil }
    return NSDecimalNumber(decimal: rounded).intValue
  }
}
