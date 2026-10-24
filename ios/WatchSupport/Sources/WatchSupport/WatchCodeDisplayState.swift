import Foundation

public enum WatchCodeKind: Sendable { case online, offline }

/// Scheduling and presentation have separate lifetimes: pausing work must not
/// replace an authorized card/code with a first-time enrollment screen.
public struct WatchCodeDisplayState {
  public private(set) var matrix: QRMatrix?
  public private(set) var message: String?
  public private(set) var generating = false
  public private(set) var requiresAuthorization = true
  public private(set) var kind = WatchCodeKind.offline
  public private(set) var codeRevision = 0
  public private(set) var onlineExpiresAt: Date?
  private var active = false
  private var generation = 0

  public init() {}

  public mutating func setActive(_ value: Bool) {
    guard value != active else { return }
    active = value
    if value {
      // Refresh on wake, discarding a computation from before suspension.
      generation += 1
      generating = false
    }
    // An already-started computation may finish while inactive. Keep both it
    // and the last rendered matrix; only future scheduling is paused.
  }

  @discardableResult
  public mutating func reconcile(previous: WatchSnapshot?, incoming: WatchSnapshot, now: Date = Date()) -> Bool {
    guard incoming.enabled, incoming.card?.permitsPayment == true else {
      invalidate("请在手机同步校园卡授权")
      return false
    }
    let offlineReady = (incoming.credential?.expiresAt ?? 0) > now.timeIntervalSince1970
    guard offlineReady || incoming.onlineAccount != nil else {
      invalidate(incoming.credential == nil ? "请在手机同步校园卡授权" : WatchFailure.expired.errorDescription)
      return false
    }
    let sameOwner = previous?.subject == incoming.subject && previous?.card?.studentID == incoming.card?.studentID
    let changed = !sameOwner || previous?.credential != incoming.credential || previous?.onlineAccount != incoming.onlineAccount
    requiresAuthorization = false
    if kind == .offline && !offlineReady { matrix = nil }
    if changed {
      generation += 1
      generating = false
      message = nil
      // Renewal and balance updates keep the current display until replacement;
      // an account/card switch must never reuse the other owner's code.
      if !sameOwner || (kind == .offline && (!offlineReady || (previous?.credential?.expiresAt ?? 0) <= now.timeIntervalSince1970)) ||
        (kind == .online && previous?.onlineAccount != incoming.onlineAccount) { matrix = nil }
    }
    expireOnlineCode(now: now)
    return changed || matrix == nil
  }

  public mutating func expireOnlineCode(now: Date = Date()) {
    if kind == .online, let onlineExpiresAt, onlineExpiresAt <= now { matrix = nil }
  }

  public mutating func pauseOnlineCode(now: Date = Date()) {
    if kind == .online {
      cancelGeneration()
      expireOnlineCode(now: now)
    }
  }

  public mutating func clearCode() {
    cancelGeneration()
    matrix = nil
    onlineExpiresAt = nil
  }

  public mutating func cancelGeneration() {
    generation += 1
    generating = false
    message = nil
  }

  public mutating func beginGeneration() -> Int? {
    guard active, !generating, !requiresAuthorization else { return nil }
    generation += 1
    generating = true
    message = nil
    return generation
  }

  public func accepts(generation ticket: Int) -> Bool { generation == ticket }

  public mutating func finish(_ result: Result<QRMatrix, Error>, generation ticket: Int,
    kind: WatchCodeKind = .offline, expiresAt: Date? = nil) {
    guard generation == ticket else { return }
    generating = false
    switch result {
    case .success(let replacement):
      guard kind != .online || (active && (expiresAt ?? .distantPast) > Date()) else { return }
      matrix = replacement; message = nil; self.kind = kind; onlineExpiresAt = expiresAt
      codeRevision = ticket
    case .failure(let error):
      let failure = error as? WatchFailure
      if failure == .expired || failure == .invalidCredential || failure == .unsupportedQuota {
        invalidate(failure?.errorDescription)
      } else if let onlineFailure = error as? WatchOnlineFailure {
        if !onlineFailure.permitsOfflineFallback { matrix = nil }
        message = onlineFailure.errorDescription
      } else {
        // A transient rendering failure does not destroy a usable prior image.
        message = "无法刷新消费码，请重试"
      }
    }
  }

  private mutating func invalidate(_ message: String?) {
    generation += 1
    generating = false
    matrix = nil
    onlineExpiresAt = nil
    requiresAuthorization = true
    self.message = message
  }
}
