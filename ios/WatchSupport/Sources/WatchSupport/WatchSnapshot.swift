import Foundation

public struct WatchCard: Codable, Equatable, Sendable {
  public var name: String
  public var studentID: String
  public var balanceFen: Int
  public var updatedAt: Double?
  public var permitsPayment: Bool
}

public struct WatchCredential: Codable, Equatable, Sendable {
  public var cardID: String
  public var privateKey: String
  public var publicKey: String
  public var deviceChecksum: Int
  public var authorInfo: String
  // Exclusive UTC timestamp: the day after the upstream inclusive expiry date.
  public var expiresAt: Double
  public var totalUses: Int?

  public func validate() throws {
    guard !cardID.isEmpty, (0...255).contains(deviceChecksum),
      expiresAt.isFinite, expiresAt > 0, authorInfo.count <= 4096,
      totalUses == nil else { throw WatchFailure.invalidCredential }
    let privateBytes = try Data(strictHex: privateKey)
    guard try OfflineCode.publicKey(privateKey: privateBytes) == Data(strictHex: publicKey) else { throw WatchFailure.invalidCredential }
    _ = try Data(strictHex: authorInfo)
  }
}

public struct WatchSnapshot: Codable, Equatable, Sendable {
  public var version: Int
  public var sourceID: String
  public var targetID: String
  public var revision: Int
  public var enrollmentNonce: String?
  public var enabled: Bool
  public var subject: String?
  public var card: WatchCard?
  public var credential: WatchCredential?

  public func validate() throws {
    guard version == 1, revision > 0, !sourceID.isEmpty, !targetID.isEmpty else { throw WatchFailure.invalidSnapshot }
    if !enabled {
      guard card == nil, credential == nil, subject == nil else { throw WatchFailure.invalidSnapshot }
      return
    }
    guard let subject, !subject.isEmpty else { throw WatchFailure.invalidSnapshot }
    if let card {
      guard !card.studentID.isEmpty, !card.name.isEmpty,
        card.updatedAt == nil || (card.updatedAt!.isFinite && card.updatedAt! > 0) else { throw WatchFailure.invalidSnapshot }
    }
    if let credential {
      try credential.validate()
      guard credential.cardID == card?.studentID, card?.permitsPayment == true else { throw WatchFailure.invalidSnapshot }
    }
  }

  /// A different phone installation must answer this watch's current enrollment challenge.
  public func canReplace(_ old: WatchSnapshot?, target: String, nonce: String) throws -> Bool {
    try validate()
    guard targetID == target else { return false }
    if let old, old.sourceID == sourceID { return revision > old.revision }
    return enrollmentNonce == nonce
  }
}
