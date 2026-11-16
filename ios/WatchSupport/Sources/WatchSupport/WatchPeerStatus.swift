import Foundation

/// Installation metadata can lag behind a working WatchConnectivity session.
/// Only a live message from the system-authenticated counterpart establishes a peer.
public struct WatchPeerStatus {
  public let active: Bool
  public let paired: Bool
  public let reportedInstalled: Bool
  public let directory: String?
  public let liveInstallationID: String?
  public let nonce: String?

  public init(active: Bool, paired: Bool, reportedInstalled: Bool, directory: String?,
              liveInstallationID: String?, nonce: String?) {
    self.active = active; self.paired = paired
    self.reportedInstalled = reportedInstalled; self.directory = directory
    self.liveInstallationID = liveInstallationID; self.nonce = nonce
  }

  public var canEnroll: Bool {
    active && paired && liveInstallationID?.isEmpty == false && nonce?.isEmpty == false
  }

  public func canDeliver(to target: String?) -> Bool {
    canEnroll && target != nil && target == liveInstallationID
  }
}
