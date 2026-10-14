import Foundation
import SwiftUI
import WatchConnectivity
import WatchSupport
import Network

struct WatchPaymentConfirmation: Identifiable, Equatable {
  let id: UUID
  let amountFen: Int
}

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
  @Published private(set) var snapshot: WatchSnapshot?
  @Published private(set) var display = WatchCodeDisplayState()
  @Published private(set) var message: String?
  @Published private(set) var prefersOnline = true
  @Published private(set) var automaticallyChecksPayments = true
  @Published private(set) var paymentConfirmation: WatchPaymentConfirmation?
  @Published private var onlineBalance: Int?
  @Published private var onlineBalanceAt: Double?
  var matrix: QRMatrix? { display.matrix }
  var generating: Bool { display.generating || finishingCheck }
  var requiresAuthorization: Bool { display.requiresAuthorization }
  var codeMessage: String? { display.message ?? message }
  var codeLabel: String { display.kind == .online ? "在线消费码" : "离线消费码" }
  var balanceFen: Int? {
    if let onlineBalanceAt, onlineBalanceAt >= (snapshot?.card?.updatedAt ?? 0) { return onlineBalance }
    return snapshot?.card?.balanceFen
  }
  var balanceUpdatedAt: Double? {
    if let onlineBalanceAt, onlineBalanceAt >= (snapshot?.card?.updatedAt ?? 0) { return onlineBalanceAt }
    return snapshot?.card?.updatedAt
  }
  private var onlineClient: WatchOnlineCodeClient?
  private var clientAccount: WatchOnlineAccount?
  private var codeTask: Task<Void, Never>?
  private var cycleTask: Task<Void, Never>?
  private var codeExpiryTask: Task<Void, Never>?
  private var cycleID: UUID?
  private var onlineFrame: WatchOnlineCode?
  private var codeVisible = false
  @Published private var finishingCheck = false
  private var nextManualRefreshAt = Date.distantPast
  private let paymentPreferences = WatchPaymentPreferences()
  private let pathMonitor = NWPathMonitor()
  private let pathQueue = DispatchQueue(label: "techpie.watch.network")
  private var networkAvailable = false
  private var targetID = ""
  private var storageReady = false
  private let nonce = UUID().uuidString
  private var syncInFlight = false
  private let session = WCSession.default

  override init() {
    super.init()
    prefersOnline = paymentPreferences.prefersOnline
    automaticallyChecksPayments = paymentPreferences.automaticallyChecksPayments
    restoreStorage()
    startNetworkMonitoring()
    if WCSession.isSupported() { session.delegate = self; session.activate() }
    #if DEBUG && targetEnvironment(simulator)
    if ProcessInfo.processInfo.arguments.contains("--watch-preview") { installPreview() }
    #endif
  }

  deinit { pathMonitor.cancel(); codeTask?.cancel(); cycleTask?.cancel(); codeExpiryTask?.cancel() }

  private func startNetworkMonitoring() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      // An on-demand path can be established by URLSession; only an
      // unsatisfied path is known to have no available network.
      let available = path.status != .unsatisfied
      DispatchQueue.main.async { self.updateNetworkAvailability(available) }
    }
    pathMonitor.start(queue: pathQueue)
  }

  private func updateNetworkAvailability(_ available: Bool) {
    guard available != networkAvailable else { return }
    networkAvailable = available
    guard prefersOnline, snapshot?.onlineAccount != nil else { return }
    if !codeVisible {
      codeTask?.cancel()
      stopCodeCycle(keepingFrame: true)
      display.pauseOnlineCode()
      scheduleDisplayedCodeExpiry()
      return
    }
    stopCodeCycle()
    codeTask?.cancel()
    if !available && display.kind == .online { display.clearCode() }
    else { display.cancelGeneration() }
    refreshCode()
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
    guard storageReady || restoreStorage(), !targetID.isEmpty, session.activationState == .activated,
      session.isCompanionAppInstalled, !syncInFlight else { return }
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
    guard value != codeVisible else { return }
    codeVisible = value
    display.setActive(value)
    if !value {
      codeTask?.cancel()
      stopCodeCycle(keepingFrame: true)
      display.pauseOnlineCode()
      scheduleDisplayedCodeExpiry()
      return
    }
    if let snapshot { display.reconcile(previous: snapshot, incoming: snapshot) }
    codeExpiryTask?.cancel()
    codeExpiryTask = nil
    let preferred = paymentPreferences.resolvedKind(networkAvailable: networkAvailable,
      hasOnlineAccount: snapshot?.onlineAccount != nil)
    if preferred == .online, display.kind == .online, display.matrix != nil,
      let frame = onlineFrame, frame.expiresAt > Date() {
      startCodeCycle(frame: frame)
    } else { refreshCode(preservingCurrentCode: true) }
  }

  func setOnlinePreferred(_ value: Bool) {
    guard value != prefersOnline else { return }
    paymentPreferences.setOnlinePreferred(value)
    prefersOnline = value
    stopCodeCycle()
    codeTask?.cancel()
    display.clearCode()
    refreshCode()
  }

  func setAutomaticPaymentChecking(_ value: Bool) {
    guard value != automaticallyChecksPayments else { return }
    paymentPreferences.setAutomaticPaymentChecking(value)
    automaticallyChecksPayments = value
    if generating { return }
    let frame = onlineFrame
    stopCodeCycle()
    if codeVisible && display.matrix == nil { refreshCode() }
    else { startCodeCycle(frame: frame) }
  }

  func dismissPaymentConfirmation(_ id: UUID) {
    if paymentConfirmation?.id == id { paymentConfirmation = nil }
  }

  func manuallyRefreshCode() {
    let now = Date()
    guard codeVisible, !generating, now >= nextManualRefreshAt else { return }
    nextManualRefreshAt = now.addingTimeInterval(2)
    if display.kind == .online, let frame = onlineFrame, let client = onlineClient, networkAvailable {
      refreshAfterChecking(frame, client: client)
    } else { refreshCode(preservingCurrentCode: true) }
  }

  private func refreshAfterChecking(_ frame: WatchOnlineCode, client: WatchOnlineCodeClient) {
    stopCodeCycle()
    let id = UUID()
    cycleID = id
    finishingCheck = true
    display.expireOnlineCode()
    scheduleDisplayedCodeExpiry()
    cycleTask = Task { @MainActor [weak self] in
      var result: WatchPaymentResult?
      var failure: WatchOnlineFailure?
      do { result = try await client.finishChecking(frame) }
      catch is CancellationError { return }
      catch { failure = error as? WatchOnlineFailure }
      guard !Task.isCancelled, let self, self.codeVisible, self.cycleID == id,
        self.networkAvailable else { return }
      self.finishingCheck = false
      if failure == .identityMismatch || failure == .invalidAccount {
        if let generation = self.display.beginGeneration(), let failure {
          self.display.finish(.failure(failure), generation: generation)
        }
        self.stopCodeCycle()
        return
      }
      if case .completed(let amount)? = result {
        self.display.clearCode()
        self.paymentConfirmation = WatchPaymentConfirmation(id: frame.id, amountFen: amount)
      }
      let useOffline = result == .useOffline &&
        (self.snapshot?.credential?.expiresAt ?? 0) > Date().timeIntervalSince1970
      self.refreshCode(preservingCurrentCode: true, keepingConfirmation: self.paymentConfirmation != nil,
        forceOffline: useOffline)
    }
  }

  private func stopCodeCycle(keepingConfirmation: Bool = false, keepingFrame: Bool = false) {
    cycleTask?.cancel()
    codeExpiryTask?.cancel()
    codeExpiryTask = nil
    cycleTask = nil
    cycleID = nil
    finishingCheck = false
    if !keepingFrame { onlineFrame = nil }
    if !keepingConfirmation { paymentConfirmation = nil }
  }

  private func startCodeCycle(frame: WatchOnlineCode?) {
    guard codeVisible, display.matrix != nil, !display.requiresAuthorization else { return }
    cycleTask?.cancel()
    let id = UUID()
    cycleID = id
    onlineFrame = frame
    let now = Date()
    let refreshAt = frame?.expiresAt ?? min(now.addingTimeInterval(30),
      Date(timeIntervalSince1970: snapshot?.credential?.expiresAt ?? 0))
    let client = onlineClient
    cycleTask = Task { @MainActor [weak self] in
      var schedule = WatchPaymentSchedule(refreshAt: refreshAt, online: frame != nil, now: now)
      while !Task.isCancelled {
        guard let self, self.codeVisible, self.cycleID == id, !self.requiresAuthorization else { return }
        switch schedule.nextAction(automaticallyChecking: self.automaticallyChecksPayments,
          lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled) {
        case .wait(let delay):
          do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        case .refresh:
          if let frame, let client, self.automaticallyChecksPayments, self.networkAvailable {
            self.refreshAfterChecking(frame, client: client)
          } else { self.refreshCode() }
          return
        case .poll:
          guard let frame, let client, self.networkAvailable else { return }
          do {
            let result = try await client.poll(frame)
            guard !Task.isCancelled, self.codeVisible, self.cycleID == id else { return }
            schedule.didPoll(failed: false)
            switch result {
            case .pending: break
            case .completed(let amount):
              self.paymentConfirmation = WatchPaymentConfirmation(id: frame.id, amountFen: amount)
              self.refreshCode(keepingConfirmation: true)
              return
            case .expired, .notCompleted:
              self.refreshCode()
              return
            case .useOffline:
              if (self.snapshot?.credential?.expiresAt ?? 0) > Date().timeIntervalSince1970 {
                self.refreshCode(forceOffline: true)
                return
              }
              schedule = WatchPaymentSchedule(refreshAt: frame.expiresAt, online: false)
            }
          } catch is CancellationError { return }
          catch {
            guard !Task.isCancelled, self.codeVisible, self.cycleID == id else { return }
            if let failure = error as? WatchOnlineFailure, failure == .authentication {
              self.refreshCode()
              return
            }
            if let failure = error as? WatchOnlineFailure, failure == .identityMismatch || failure == .invalidAccount {
              if let generation = self.display.beginGeneration() {
                self.display.finish(.failure(failure), generation: generation)
              }
              self.stopCodeCycle()
              return
            }
            // A failed check cannot confirm payment or destroy a still-valid code.
            schedule.didPoll(failed: true)
          }
        }
      }
    }
  }

  private func scheduleDisplayedCodeExpiry() {
    guard display.matrix != nil, let deadline = display.onlineExpiresAt else { return }
    let revision = display.codeRevision
    codeExpiryTask = Task { @MainActor [weak self] in
      let delay = max(0, deadline.timeIntervalSinceNow)
      do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
      guard !Task.isCancelled, let self, self.display.codeRevision == revision else { return }
      self.display.expireOnlineCode()
    }
  }

  func refreshCode(preservingCurrentCode: Bool = false, keepingConfirmation: Bool = false, forceOffline: Bool = false) {
    guard codeVisible, let snapshot, !display.generating, !finishingCheck else { return }
    display.reconcile(previous: snapshot, incoming: snapshot)
    if display.kind == .online && !preservingCurrentCode { display.clearCode() }
    guard let currentGeneration = display.beginGeneration() else { return }
    stopCodeCycle(keepingConfirmation: keepingConfirmation)
    scheduleDisplayedCodeExpiry()
    let useOnline = !forceOffline && paymentPreferences.resolvedKind(networkAvailable: networkAvailable,
      hasOnlineAccount: snapshot.onlineAccount != nil) == .online
    if useOnline, clientAccount != snapshot.onlineAccount {
      clientAccount = snapshot.onlineAccount
      onlineClient = snapshot.onlineAccount.map { WatchOnlineCodeClient(account: $0) }
    }
    let client = useOnline ? onlineClient : nil
    let credential = snapshot.credential
    codeTask = Task.detached(priority: .userInitiated) { [self] in
      do {
        if let client {
          do {
            let frame = try await client.generate()
            try Task.checkCancellation()
            await MainActor.run {
              guard self.display.accepts(generation: currentGeneration) else { return }
              self.codeExpiryTask?.cancel()
              self.codeExpiryTask = nil
              self.display.finish(.success(frame.matrix), generation: currentGeneration, kind: .online, expiresAt: frame.expiresAt)
              if let balance = frame.balanceFen {
                self.onlineBalance = balance
                self.onlineBalanceAt = frame.generatedAt.timeIntervalSince1970
              }
              self.startCodeCycle(frame: frame)
            }
            return
          } catch let failure as WatchOnlineFailure where failure.permitsOfflineFallback {
            guard let credential, credential.expiresAt > Date().timeIntervalSince1970 else { throw failure }
          }
        }
        guard let credential else { throw WatchFailure.invalidCredential }
        let matrix = try OfflineCode.qr(OfflineCode.generate(credential))
        try Task.checkCancellation()
        await MainActor.run {
          guard self.display.accepts(generation: currentGeneration) else { return }
          self.codeExpiryTask?.cancel()
          self.codeExpiryTask = nil
          self.display.finish(.success(matrix), generation: currentGeneration)
          self.startCodeCycle(frame: nil)
        }
      } catch is CancellationError {
        await MainActor.run {
          if self.display.accepts(generation: currentGeneration) { self.display.cancelGeneration() }
        }
      } catch {
        await MainActor.run {
          self.display.finish(.failure(error), generation: currentGeneration)
          if self.display.accepts(generation: currentGeneration), self.display.matrix == nil {
            self.codeExpiryTask?.cancel()
            self.codeExpiryTask = nil
          }
        }
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
        if incoming.subject != snapshot?.subject || incoming.onlineAccount != snapshot?.onlineAccount ||
          !incoming.enabled || incoming.card?.permitsPayment != true {
          codeTask?.cancel()
          stopCodeCycle()
          onlineClient = nil
          clientAccount = nil
          onlineBalance = nil
          onlineBalanceAt = nil
        }
        let needsCode = display.reconcile(previous: snapshot, incoming: incoming)
        snapshot = incoming
        if needsCode { refreshCode() }
      }
      var receipt: [String: Any] = ["sourceID": incoming.sourceID, "targetID": targetID,
        "revision": incoming.revision, "accepted": true, "onlineReady": incoming.onlineAccount != nil]
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
