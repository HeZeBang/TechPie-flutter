import Foundation

/// Scheduling and presentation have separate lifetimes: pausing work must not
/// replace an authorized card/code with a first-time enrollment screen.
public struct WatchCodeDisplayState {
  public private(set) var matrix: QRMatrix?
  public private(set) var message: String?
  public private(set) var generating = false
  public private(set) var requiresAuthorization = true
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
    guard incoming.enabled, incoming.card?.permitsPayment == true,
      let credential = incoming.credential else {
      invalidate("请在手机同步离线授权")
      return false
    }
    guard credential.expiresAt > now.timeIntervalSince1970 else {
      invalidate(WatchFailure.expired.errorDescription)
      return false
    }
    let sameOwner = previous?.subject == incoming.subject && previous?.card?.studentID == incoming.card?.studentID
    let changed = !sameOwner || previous?.credential != credential
    requiresAuthorization = false
    if changed {
      generation += 1
      generating = false
      message = nil
      // Renewal and balance updates keep the current display until replacement;
      // an account/card switch must never reuse the other owner's code.
      if !sameOwner || (previous?.credential?.expiresAt ?? 0) <= now.timeIntervalSince1970 { matrix = nil }
    }
    return changed || matrix == nil
  }

  public mutating func beginGeneration() -> Int? {
    guard active, !generating, !requiresAuthorization else { return nil }
    generation += 1
    generating = true
    message = nil
    return generation
  }

  public mutating func finish(_ result: Result<QRMatrix, Error>, generation ticket: Int) {
    guard generation == ticket else { return }
    generating = false
    switch result {
    case .success(let replacement): matrix = replacement; message = nil
    case .failure(let error):
      let failure = error as? WatchFailure
      if failure == .expired || failure == .invalidCredential || failure == .unsupportedQuota {
        invalidate(failure?.errorDescription)
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
    requiresAuthorization = true
    self.message = message
  }
}
