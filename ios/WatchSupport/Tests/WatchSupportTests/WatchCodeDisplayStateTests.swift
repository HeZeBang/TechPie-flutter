import XCTest
@testable import WatchSupport

final class WatchCodeDisplayStateTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1790000000)
  private let first = QRMatrix(side: 1, modules: [1])
  private let second = QRMatrix(side: 2, modules: [1, 0, 0, 1])

  private func snapshot() throws -> WatchSnapshot {
    let url = Bundle.module.url(forResource: "dart-grant", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(WatchSnapshot.self, from: Data(contentsOf: url))
  }

  private func ready(_ snapshot: WatchSnapshot) -> WatchCodeDisplayState {
    var state = WatchCodeDisplayState()
    state.reconcile(previous: nil, incoming: snapshot, now: now)
    state.setActive(true)
    state.finish(.success(first), generation: state.beginGeneration()!)
    return state
  }

  func testBriefInactivityAndWakeKeepCodeUntilReplacementIsReady() throws {
    var state = ready(try snapshot())
    state.setActive(false)
    XCTAssertEqual(state.matrix?.modules, first.modules)
    XCTAssertFalse(state.requiresAuthorization)
    XCTAssertNil(state.beginGeneration())
    state.setActive(true)
    let ticket = state.beginGeneration()!
    XCTAssertEqual(state.matrix?.modules, first.modules)
    XCTAssertNil(state.message)
    state.finish(.success(second), generation: ticket)
    XCTAssertEqual(state.matrix?.modules, second.modules)
  }

  func testFirstComputationMayFinishWhileInactiveAndBeReadyForPagePreview() throws {
    var state = WatchCodeDisplayState()
    state.reconcile(previous: nil, incoming: try snapshot(), now: now)
    state.setActive(true)
    let ticket = state.beginGeneration()!
    state.setActive(false)
    state.finish(.success(first), generation: ticket)
    XCTAssertEqual(state.matrix?.modules, first.modules)
    XCTAssertFalse(state.requiresAuthorization)
  }

  func testWakeRejectsAResultStartedBeforeInactivityWithoutBlankingTheCode() throws {
    var state = ready(try snapshot())
    let oldTicket = state.beginGeneration()!
    state.setActive(false)
    state.setActive(true)
    let newTicket = state.beginGeneration()!
    state.finish(.success(second), generation: oldTicket)
    XCTAssertEqual(state.matrix?.modules, first.modules)
    state.finish(.success(second), generation: newTicket)
    XCTAssertEqual(state.matrix?.modules, second.modules)
  }

  func testRenderingFailureKeepsUsableCodeAndDoesNotAskForAuthorization() throws {
    var state = ready(try snapshot())
    let ticket = state.beginGeneration()!
    state.finish(.failure(WatchFailure.encoding), generation: ticket)
    XCTAssertEqual(state.matrix?.modules, first.modules)
    XCTAssertFalse(state.requiresAuthorization)
    XCTAssertFalse(state.generating)
  }

  func testCardInformationUpdateDoesNotClearOrRegenerateCode() throws {
    let original = try snapshot()
    var state = ready(original)
    var updated = original
    updated.revision += 1
    updated.card!.balanceFen += 100
    XCTAssertFalse(state.reconcile(previous: original, incoming: updated, now: now))
    XCTAssertEqual(state.matrix?.modules, first.modules)
  }

  func testRenewalPreservesCurrentCodeAndRejectsTheOldComputation() throws {
    let original = try snapshot()
    var state = ready(original)
    let oldTicket = state.beginGeneration()!
    var renewed = original
    renewed.credential!.authorInfo += "00"
    XCTAssertTrue(state.reconcile(previous: original, incoming: renewed, now: now))
    XCTAssertEqual(state.matrix?.modules, first.modules)
    state.finish(.success(second), generation: oldTicket)
    XCTAssertEqual(state.matrix?.modules, first.modules)
    let newTicket = state.beginGeneration()!
    state.finish(.success(second), generation: newTicket)
    XCTAssertEqual(state.matrix?.modules, second.modules)
  }

  func testRevocationExpiryAndAccountSwitchNeverKeepAnotherUsableCode() throws {
    let original = try snapshot()
    var revoked = original
    revoked.enabled = false; revoked.card = nil; revoked.credential = nil; revoked.subject = nil
    var expired = original
    expired.credential!.expiresAt = now.timeIntervalSince1970
    for invalid in [revoked, expired] {
      var state = ready(original)
      let ticket = state.beginGeneration()!
      state.reconcile(previous: original, incoming: invalid, now: now)
      state.finish(.success(second), generation: ticket)
      XCTAssertNil(state.matrix)
      XCTAssertTrue(state.requiresAuthorization)
    }
    var state = ready(original)
    var other = original; other.subject = "OTHER"
    state.reconcile(previous: original, incoming: other, now: now)
    XCTAssertNil(state.matrix)
  }
}
