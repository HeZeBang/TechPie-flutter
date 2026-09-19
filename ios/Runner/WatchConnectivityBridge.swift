import Flutter
import WatchConnectivity
import WatchSupport

/// Owns background delivery independently of Flutter's page/engine lifecycle.
final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
  private struct State: Codable {
    var revision = 0
    var targetID: String?
    var pairing: String?
    var enabled = false
    var pending: Data?
    var acknowledged = 0
    var acknowledgedExpiry: Double?
    var grantStatus: String?
    var revocationReason: String?
  }
  private let channel: FlutterMethodChannel
  private var state = State()
  private var sourceID = ""
  private var discoveredID: String?
  private var nonce: String?
  private var storageReady = false
  private let session = WCSession.default

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "techpie/watch", binaryMessenger: registrar.messenger())
    super.init()
    restoreStorage()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    if WCSession.isSupported() { session.delegate = self; session.activate() }
  }

  @discardableResult
  private func restoreStorage() -> Bool {
    do {
      let restoredID = try WatchKeychain.identifier("phone.source")
      let restoredState: State
      if let data = try WatchKeychain.read("phone.state") {
        restoredState = try JSONDecoder().decode(State.self, from: data)
      } else { restoredState = State() }
      sourceID = restoredID
      state = restoredState
      storageReady = true
      return true
    } catch { storageReady = false; return false }
  }

  private var pairing: String? { session.watchDirectoryURL?.lastPathComponent }
  private var peer: WatchPeerStatus {
    WatchPeerStatus(active: session.activationState == .activated, paired: session.isPaired,
      reportedInstalled: session.isWatchAppInstalled, directory: pairing,
      liveInstallationID: discoveredID, nonce: nonce)
  }
  private func save() throws { try WatchKeychain.write(JSONEncoder().encode(state), key: "phone.state") }

  private func status() -> [String: Any] {
    var value: [String: Any] = ["installed": session.isWatchAppInstalled,
      "ready": storageReady && peer.canEnroll,
      "enabled": state.enabled,
      "revision": state.revision, "acknowledged": state.acknowledged]
    if let reason = state.revocationReason { value["revocationReason"] = reason }
    if let expiry = state.acknowledgedExpiry { value["watchExpiresAt"] = expiry }
    if let data = state.pending, let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
      snapshot.enabled {
      value["subject"] = snapshot.subject
      if let credential = snapshot.credential { value["phoneExpiresAt"] = credential.expiresAt }
    }
    return value
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard WCSession.isSupported(), storageReady || restoreStorage() else {
      result(FlutterError(code: "WATCH_STORAGE_UNAVAILABLE", message: "无法访问手表同步存储", details: nil)); return
    }
    let previous = state
    var stage = "session"
    do {
      switch call.method {
      case "status": result(status())
      case "disable":
        let requested = (call.arguments as? [String: Any])?["reason"] as? String ?? "userRevoked"
        let reason = ["userRevoked", "userSignedOut", "accountChanged"].contains(requested) ? requested : "userRevoked"
        try publishDisabled(reason: reason)
        result(status())
      case "publish":
        guard let input = call.arguments as? [String: Any] else { throw WatchFailure.invalidSnapshot }
        let enroll = input["enroll"] as? Bool == true
        if enroll {
          guard peer.canEnroll, let target = discoveredID else { throw WatchFailure.invalidSnapshot }
          state.targetID = target
          state.pairing = pairing
        } else {
          guard state.enabled else { throw WatchFailure.invalidSnapshot }
          if let data = state.pending,
            let previous = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
            previous.subject != input["subject"] as? String {
            try publishDisabled(reason: "accountChanged"); result(status()); return
          }
        }
        guard let target = state.targetID else { throw WatchFailure.invalidSnapshot }
        var envelope: [String: Any] = ["version": 1, "sourceID": sourceID, "targetID": target,
          "revision": state.revision + 1, "enabled": true,
          "subject": input["subject"] ?? NSNull(), "card": input["card"] ?? NSNull(),
          "credential": input["credential"] ?? NSNull()]
        if enroll { envelope["enrollmentNonce"] = nonce }
        stage = "encode"
        let data = try JSONSerialization.data(withJSONObject: envelope)
        stage = "decode"
        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        stage = "validate"
        try snapshot.validate()
        // Duplicate card/grant refreshes need no new transport revision or receipt.
        if !enroll, let old = state.pending,
          let previous = try? JSONDecoder().decode(WatchSnapshot.self, from: old),
          previous.subject == snapshot.subject, previous.card == snapshot.card,
          previous.credential == snapshot.credential {
          deliver(); result(status()); return
        }
        state.revision += 1
        state.enabled = true
        state.revocationReason = nil
        state.pending = data
        let grantStatus = input["grantStatus"] as? String ?? "unknown"
        state.grantStatus = ["ready", "cardUnavailable", "missing", "limited", "missingExpiry", "expired", "changed"].contains(grantStatus) ? grantStatus : "unknown"
        state.acknowledgedExpiry = nil
        stage = "persist"
        try save()
        deliver()
        result(status())
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      state = previous
      // Diagnostics contain only fixed stage names, platform codes and booleans.
      // Never serialize the error description, input payload, identifiers or keys.
      let statusCode = (error as NSError).domain == NSOSStatusErrorDomain ? (error as NSError).code : 0
      let failureKind: String
      if let failure = error as? WatchFailure {
        switch failure {
        case .invalidCredential: failureKind = "credential"
        default: failureKind = "snapshot"
        }
      } else if error is DecodingError { failureKind = "decode" }
      else { failureKind = "platform" }
      let diagnostic: [String: Any] = ["stage": stage, "failure": failureKind, "osStatus": statusCode,
        "activated": session.activationState == .activated, "installed": session.isWatchAppInstalled,
        "paired": session.isPaired, "hasPairDirectory": pairing != nil,
        "hasHello": discoveredID != nil, "hasNonce": nonce != nil]
      if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        let data = try? JSONSerialization.data(withJSONObject: diagnostic) {
        try? data.write(to: directory.appendingPathComponent("watch-sync-diagnostic.json"), options: .atomic)
      }
      result(FlutterError(code: "WATCH_SYNC_\(stage.uppercased())", message: "手表同步未完成，请重试", details: diagnostic))
    }
  }

  private func publishDisabled(reason: String) throws {
    state.enabled = false
    state.revocationReason = reason
    state.grantStatus = nil
    state.acknowledgedExpiry = nil
    guard let target = state.targetID else { state.pending = nil; try save(); return }
    state.revision += 1
    let envelope: [String: Any] = ["version": 1, "sourceID": sourceID, "targetID": target,
      "revision": state.revision, "enabled": false]
    state.pending = try JSONSerialization.data(withJSONObject: envelope)
    try save()
    deliver()
  }

  private func deliver() {
    guard peer.canDeliver(to: state.targetID), state.acknowledged < state.revision,
      let data = state.pending else { return }
    // Keep one latest full state, including revocation, for eventual delivery.
    for transfer in session.outstandingUserInfoTransfers { transfer.cancel() }
    session.transferUserInfo(["snapshot": data])
    if session.isReachable { session.sendMessage(["snapshot": data], replyHandler: { [weak self] reply in
      DispatchQueue.main.async { self?.receive(reply) }
    }, errorHandler: { _ in }) }
  }

  private func receive(_ message: [String: Any], live: Bool = false) {
    guard storageReady, session.activationState == .activated else { return }
    if live, let target = message["watchID"] as? String, let challenge = message["nonce"] as? String,
      !target.isEmpty, !challenge.isEmpty, target.count <= 64, challenge.count <= 64 {
      discoveredID = target; nonce = challenge
      // A new watch installation needs explicit enrollment on the phone.
      if state.enabled && state.targetID != target {
        state.enabled = false; state.pending = nil; state.acknowledgedExpiry = nil
        state.revocationReason = "peerChanged"
        try? save()
      }
      // A watch can restart before committing its first enrollment. Update that
      // already-approved installation's challenge instead of replaying the old one.
      if state.enabled, state.targetID == target,
        state.acknowledged < state.revision, let data = state.pending,
        var snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
        snapshot.enrollmentNonce != nil, snapshot.enrollmentNonce != challenge {
        snapshot.enrollmentNonce = challenge
        snapshot.revision = state.revision + 1
        let old = state
        do {
          state.pending = try JSONEncoder().encode(snapshot)
          state.revision = snapshot.revision
          try save()
        } catch { state = old }
      }
      deliver()
      channel.invokeMethod("watchChanged", arguments: nil)
    }
    if message["sourceID"] as? String == sourceID,
      message["targetID"] as? String == state.targetID,
      let revision = message["revision"] as? Int, revision == state.revision,
      message["accepted"] as? Bool == true {
      state.acknowledged = revision
      state.acknowledgedExpiry = message["expiresAt"] as? Double
      try? save()
      if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        let data = try? JSONSerialization.data(withJSONObject: ["stage": "acknowledged",
          "revision": revision, "hasCredential": state.acknowledgedExpiry != nil,
          "grantStatus": state.grantStatus ?? "unknown"] as [String: Any]) {
        try? data.write(to: directory.appendingPathComponent("watch-sync-diagnostic.json"), options: .atomic)
      }
      channel.invokeMethod("watchChanged", arguments: nil)
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { [weak self] in self?.deliver(); self?.channel.invokeMethod("watchChanged", arguments: nil) }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {
    DispatchQueue.main.async { [weak self] in self?.discoveredID = nil; self?.nonce = nil }
  }
  func sessionDidDeactivate(_ session: WCSession) {
    DispatchQueue.main.async { [weak self] in self?.discoveredID = nil; self?.nonce = nil; session.activate() }
  }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { replyHandler([:]); return }
      self.receive(message, live: true)
      // Reply on the working watch-initiated channel even if iOS's installation
      // metadata still says false. The payload stays bound to the enrolled peer.
      if message["watchID"] as? String == self.state.targetID,
        self.peer.canDeliver(to: self.state.targetID), let data = self.state.pending,
        self.state.acknowledged < self.state.revision ||
          message["knownSourceID"] as? String != self.sourceID ||
          message["knownRevision"] as? Int != self.state.revision {
        replyHandler(["snapshot": data])
      } else { replyHandler([:]) }
    }
  }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.receive(message, live: true) }
  }
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.receive(userInfo) }
  }
  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { [weak self] in self?.deliver() }
  }
}
