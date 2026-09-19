import Foundation
import SwiftUI
import WatchConnectivity
import WatchSupport

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
  @Published private(set) var snapshot: WatchSnapshot?
  @Published private(set) var display = WatchCodeDisplayState()
  @Published private(set) var message: String?
  var matrix: QRMatrix? { display.matrix }
  var generating: Bool { display.generating }
  var requiresAuthorization: Bool { display.requiresAuthorization }
  var codeMessage: String? { display.message ?? message }
  private var targetID = ""
  private var storageReady = false
  private let nonce = UUID().uuidString
  private var syncInFlight = false
  private let session = WCSession.default

  override init() {
    super.init()
    restoreStorage()
    if WCSession.isSupported() { session.delegate = self; session.activate() }
    #if DEBUG && targetEnvironment(simulator)
    if ProcessInfo.processInfo.arguments.contains("--watch-preview") { installPreview() }
    #endif
  }

  @discardableResult
  private func restoreStorage() -> Bool {
    do {
      let restoredID = try WatchKeychain.identifier("watch.installation")
      targetID = restoredID
      storageReady = true
      var restoredSnapshot: WatchSnapshot?
      if let data = try WatchKeychain.read("watch.snapshot") {
        let value = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        try value.validate()
        guard value.targetID == restoredID else { throw WatchFailure.invalidSnapshot }
        restoredSnapshot = value
      }
      snapshot = restoredSnapshot
      if let restoredSnapshot { display.reconcile(previous: nil, incoming: restoredSnapshot) }
      message = nil
      return true
    } catch {
      message = "请解锁手表后重试同步"
      return storageReady
    }
  }

  func requestSync() {
    guard storageReady || restoreStorage(), !targetID.isEmpty, session.activationState == .activated, !syncInFlight else { return }
    let hello: [String: Any] = ["watchID": targetID, "nonce": nonce,
      "knownSourceID": snapshot?.sourceID ?? "", "knownRevision": snapshot?.revision ?? 0]
    if session.isReachable {
      syncInFlight = true
      session.sendMessage(hello, replyHandler: { [weak self] reply in
        DispatchQueue.main.async {
          guard let self else { return }
          self.syncInFlight = false
          let receipt = self.receive(reply)
          if !receipt.isEmpty {
            if self.session.isReachable {
              self.session.sendMessage(receipt, replyHandler: { _ in }, errorHandler: { [weak self] _ in
                DispatchQueue.main.async { self?.session.transferUserInfo(receipt) }
              })
            } else { self.session.transferUserInfo(receipt) }
          }
        }
      }, errorHandler: { [weak self] _ in
        DispatchQueue.main.async { self?.syncInFlight = false; self?.queueHello(hello) }
      })
    } else { queueHello(hello) }
  }

  private func queueHello(_ hello: [String: Any]) {
    for transfer in session.outstandingUserInfoTransfers where transfer.userInfo["watchID"] != nil { transfer.cancel() }
    session.transferUserInfo(hello)
  }

  func setCodeVisible(_ value: Bool) {
    display.setActive(value)
    if value { refreshCode() }
  }

  func refreshCode() {
    guard let snapshot else { return }
    display.reconcile(previous: snapshot, incoming: snapshot)
    guard let credential = snapshot.credential,
      let currentGeneration = display.beginGeneration() else { return }
    Task.detached(priority: .userInitiated) { [self] in
      let result: Result<QRMatrix, Error>
      do { result = .success(try OfflineCode.qr(OfflineCode.generate(credential))) }
      catch { result = .failure(error) }
      await MainActor.run {
        self.display.finish(result, generation: currentGeneration)
      }
    }
  }

  private func receive(_ message: [String: Any]) -> [String: Any] {
    guard storageReady || restoreStorage() else { return [:] }
    guard let data = message["snapshot"] as? Data, data.count < 32_768,
      let incoming = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return [:] }
    do {
      // Duplicate delivery acknowledges a previously committed state without reinstalling it.
      if incoming != snapshot {
        guard try incoming.canReplace(snapshot, target: targetID, nonce: nonce) else { return [:] }
        try WatchKeychain.write(data, key: "watch.snapshot")
        let needsCode = display.reconcile(previous: snapshot, incoming: incoming)
        snapshot = incoming
        if needsCode { refreshCode() }
      }
      var receipt: [String: Any] = ["sourceID": incoming.sourceID, "targetID": targetID,
        "revision": incoming.revision, "accepted": true]
      if let expiresAt = incoming.credential?.expiresAt { receipt["expiresAt"] = expiresAt }
      return receipt
    } catch { self.message = "保存授权失败，请解锁手表后重试"; return [:] }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { [weak self] in self?.requestSync() }
  }
  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { [weak self] in if session.isReachable { self?.requestSync() } }
  }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async { [weak self] in replyHandler(self?.receive(message) ?? [:]) }
  }
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let receipt = self.receive(userInfo)
      if !receipt.isEmpty {
        for transfer in session.outstandingUserInfoTransfers where transfer.userInfo["accepted"] != nil { transfer.cancel() }
        session.transferUserInfo(receipt)
      }
    }
  }

  #if DEBUG && targetEnvironment(simulator)
  private func installPreview() {
    // Synthetic, simulator-only data. Never persisted or sent to another device.
    let key = String(repeating: "0", count: 63) + "1"
    let sample: [String: Any] = ["version": 1, "sourceID": "PREVIEW", "targetID": targetID,
      "revision": 1, "enabled": true, "subject": "PREVIEW",
      "card": ["name": "林同学", "studentID": "2026000001", "balanceFen": 12860,
        "updatedAt": Date().timeIntervalSince1970, "permitsPayment": true],
      "credential": ["cardID": "2026000001", "privateKey": key,
        "publicKey": "0232C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7",
        "deviceChecksum": 42, "authorInfo": "5638A1B2C3D4",
        "expiresAt": Date().addingTimeInterval(86400).timeIntervalSince1970]]
    snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: sample))
    if let snapshot { display.reconcile(previous: nil, incoming: snapshot) }
  }
  #endif
}
