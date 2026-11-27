import Foundation

/// Display-only snapshot for the campus e-card widget.
///
/// Security contract: holds only configuration status, formatted balance text,
/// and the app's balance visibility toggle — never account IDs, tokens, or
/// offline payment credentials.
public struct EcardWidgetSnapshot: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let configured: Bool
  public let balanceText: String?
  public let hideBalance: Bool

  public init(
    schemaVersion: Int = 1,
    generatedAt: Date = Date(),
    configured: Bool,
    balanceText: String?,
    hideBalance: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.configured = configured
    self.balanceText = balanceText
    self.hideBalance = hideBalance
  }

  public static func decode(_ data: Data) throws -> EcardWidgetSnapshot {
    let snapshot = try WidgetJSONCodec.decoder().decode(EcardWidgetSnapshot.self, from: data)
    guard snapshot.schemaVersion == 1 else {
      throw WidgetSnapshotError.invalidData
    }
    return snapshot
  }

  public func encode() throws -> Data {
    try WidgetJSONCodec.encoder().encode(self)
  }

  public func semanticEquals(_ other: EcardWidgetSnapshot) -> Bool {
    schemaVersion == other.schemaVersion &&
      configured == other.configured &&
      balanceText == other.balanceText &&
      hideBalance == other.hideBalance
  }

  public func effectiveHideBalance(using preferences: WidgetPreferenceStore?) -> Bool {
    preferences?.effectiveHideBalance(for: self) ?? hideBalance
  }
}
