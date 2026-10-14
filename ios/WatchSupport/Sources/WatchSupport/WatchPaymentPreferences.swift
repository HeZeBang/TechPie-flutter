import Foundation

/// A watch-local display preference; synchronized credentials never change it.
public struct WatchPaymentPreferences {
  private let defaults: UserDefaults
  private static let onlineKey = "watch.payment.prefersOnline"
  private static let checkingKey = "watch.payment.automaticallyChecksPayments"

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public var prefersOnline: Bool { defaults.object(forKey: Self.onlineKey) as? Bool ?? true }
  public var automaticallyChecksPayments: Bool { defaults.object(forKey: Self.checkingKey) as? Bool ?? true }

  public func setOnlinePreferred(_ value: Bool) { defaults.set(value, forKey: Self.onlineKey) }
  public func setAutomaticPaymentChecking(_ value: Bool) { defaults.set(value, forKey: Self.checkingKey) }

  public func resolvedKind(networkAvailable: Bool, hasOnlineAccount: Bool) -> WatchCodeKind {
    prefersOnline && networkAvailable && hasOnlineAccount ? .online : .offline
  }
}
