import XCTest
@testable import WatchSupport

final class WatchPaymentPreferencesTests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!

  override func setUp() {
    suite = "techpie.watch.settings.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
  }

  override func tearDown() { defaults.removePersistentDomain(forName: suite) }

  func testFreshInstallationDefaultsToOnlineWhenNetworkAndAccountAreAvailable() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    XCTAssertTrue(preferences.prefersOnline)
    XCTAssertTrue(preferences.automaticallyChecksPayments)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .online)
  }

  func testAutomaticCheckingSettingPersistsIndependentlyOfDefaultCode() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    preferences.setAutomaticPaymentChecking(false)
    preferences.setOnlinePreferred(false)
    let restored = WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertFalse(restored.automaticallyChecksPayments)
    restored.setOnlinePreferred(true)
    XCTAssertFalse(restored.automaticallyChecksPayments)
    restored.setAutomaticPaymentChecking(true)
    XCTAssertTrue(WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!).automaticallyChecksPayments)
  }

  func testOfflineSelectionIsRestoredWithoutStartingOnlineWorkOnReconnection() {
    WatchPaymentPreferences(defaults: defaults).setOnlinePreferred(false)
    let restored = WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertFalse(restored.prefersOnline)
    XCTAssertEqual(restored.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .offline)
    XCTAssertEqual(restored.resolvedKind(networkAvailable: false, hasOnlineAccount: true), .offline)
  }

  func testNetworkFallbackKeepsSavedOnlineDefaultAndRestoresItWhenConnected() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    preferences.setOnlinePreferred(true)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: false, hasOnlineAccount: true), .offline)
    XCTAssertTrue(WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!).prefersOnline)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .online)
  }

  func testLegacyOfflineOnlyAuthorizationRemainsUsableWithEitherDefault() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    for choice in [true, false] {
      preferences.setOnlinePreferred(choice)
      XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: false), .offline)
    }
  }

  func testNetworkTransitionRejectsPendingOnlineCodeAndKeepsValidOfflineDisplay() throws {
    var state = WatchCodeDisplayState()
    // Prepare an authorized state using the existing fixture.
    let url = Bundle.module.url(forResource: "dart-grant", withExtension: "json", subdirectory: "Fixtures")!
    let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(contentsOf: url))
    state.reconcile(previous: nil, incoming: snapshot)
    state.setActive(true)
    let offline = QRMatrix(side: 1, modules: [1])
    state.finish(.success(offline), generation: state.beginGeneration()!)
    let oldOnlineTicket = state.beginGeneration()!
    state.cancelGeneration()
    XCTAssertEqual(state.matrix?.modules, offline.modules)
    XCTAssertFalse(state.generating)
    state.finish(.success(QRMatrix(side: 1, modules: [0])), generation: oldOnlineTicket,
      kind: .online, expiresAt: Date().addingTimeInterval(30))
    XCTAssertEqual(state.matrix?.modules, offline.modules)
    XCTAssertNotNil(state.beginGeneration())
  }
}
