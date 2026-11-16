import Foundation

/// One sleeping loop serves code expiry and optional polling; no per-second timer.
public struct WatchPaymentSchedule {
  public enum Action: Equatable { case wait(TimeInterval), poll, refresh }
  public static let pollTimeout: TimeInterval = 6
  private let refreshAt: Date
  private let online: Bool
  private var lastPollAt: Date
  private var failures = 0

  public init(refreshAt: Date, online: Bool, now: Date = Date()) {
    self.refreshAt = refreshAt
    self.online = online
    lastPollAt = now
  }

  public func nextAction(now: Date = Date(), automaticallyChecking: Bool, lowPowerMode: Bool) -> Action {
    if now >= refreshAt { return .refresh }
    let interval: TimeInterval = max(lowPowerMode ? 10 : 5, failures == 0 ? 5 : (failures == 1 ? 10 : 20))
    let pollAt = lastPollAt.addingTimeInterval(interval)
    // Leave the expiry boundary to the final bounded check before replacement.
    guard online, automaticallyChecking, pollAt < refreshAt.addingTimeInterval(-Self.pollTimeout),
      now < refreshAt.addingTimeInterval(-Self.pollTimeout) else {
      return .wait(refreshAt.timeIntervalSince(now))
    }
    return now >= pollAt ? .poll : .wait(pollAt.timeIntervalSince(now))
  }

  public mutating func didPoll(now: Date = Date(), failed: Bool) {
    lastPollAt = now
    failures = failed ? min(failures + 1, 2) : 0
  }
}
