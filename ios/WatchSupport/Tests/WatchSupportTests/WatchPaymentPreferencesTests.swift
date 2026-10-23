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

  func testAutomaticCheckingSettingPersistsIndependentlyOfDefaultCode() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    XCTAssertTrue(preferences.automaticallyChecksPayments)
    preferences.setAutomaticPaymentChecking(false)
    preferences.setOnlinePreferred(false)
    let restored = WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertFalse(restored.automaticallyChecksPayments)
    restored.setOnlinePreferred(true)
    XCTAssertFalse(restored.automaticallyChecksPayments)
    restored.setAutomaticPaymentChecking(true)
    XCTAssertTrue(WatchPaymentPreferences(defaults: UserDefaults(suiteName: suite)!).automaticallyChecksPayments)
  }

  func testSavedCodePreferenceSurvivesNetworkFallback() {
    let preferences = WatchPaymentPreferences(defaults: defaults)
    XCTAssertTrue(preferences.prefersOnline)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .online)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: false, hasOnlineAccount: true), .offline)
    XCTAssertTrue(WatchPaymentPreferences(defaults: defaults).prefersOnline)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .online)
    XCTAssertEqual(preferences.resolvedKind(networkAvailable: true, hasOnlineAccount: false), .offline)
    preferences.setOnlinePreferred(false)
    let restored = WatchPaymentPreferences(defaults: defaults)
    XCTAssertFalse(restored.prefersOnline)
    XCTAssertEqual(restored.resolvedKind(networkAvailable: true, hasOnlineAccount: true), .offline)
  }
}
