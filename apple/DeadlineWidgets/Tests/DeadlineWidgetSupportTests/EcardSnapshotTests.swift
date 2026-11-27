import XCTest
@testable import DeadlineWidgetSupport

final class EcardSnapshotTests: XCTestCase {
  func testDecodeAtomicWriteAndPrivacyDefaultsOverrideLifecycle() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = "EcardPrefsTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = EcardSnapshotStore(directory: dir)
    let prefs = WidgetPreferenceStore(defaults: defaults)

    let snap1 = EcardWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1780000000),
      configured: true,
      balanceText: "¥ 86.20",
      hideBalance: false
    )
    XCTAssertTrue(try store.write(try snap1.encode()))
    prefs.syncEcardHideBalance(snap1.hideBalance)

    // Identical semantic snapshot (only newer generatedAt) is deduplicated.
    let snapSame = EcardWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1780000300),
      configured: true,
      balanceText: "¥ 86.20",
      hideBalance: false
    )
    XCTAssertFalse(try store.write(try snapSame.encode()))

    // Widget eye toggle temporarily masks the balance while keeping app setting unchanged.
    XCTAssertFalse(snap1.effectiveHideBalance(using: prefs))
    prefs.toggleEcardBalanceMask(currentSyncedHide: snap1.hideBalance)
    XCTAssertTrue(snap1.effectiveHideBalance(using: prefs))

    // A balance update that keeps the same app hideBalance preserves widget override.
    let snapNewBalance = EcardWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1780000600),
      configured: true,
      balanceText: "¥ 74.20",
      hideBalance: false
    )
    XCTAssertTrue(try store.write(try snapNewBalance.encode()))
    prefs.syncEcardHideBalance(snapNewBalance.hideBalance)
    XCTAssertTrue(snapNewBalance.effectiveHideBalance(using: prefs))

    // Changing hideBalance inside the main app supersedes any old widget override.
    let snapAppChanged = EcardWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1780000900),
      configured: true,
      balanceText: "¥ 74.20",
      hideBalance: true
    )
    prefs.syncEcardHideBalance(snapAppChanged.hideBalance)
    XCTAssertTrue(snapAppChanged.effectiveHideBalance(using: prefs))

    // Turning app setting back to false does not resurrect an old widget override.
    let snapAppUnhid = EcardWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1780001200),
      configured: true,
      balanceText: "¥ 74.20",
      hideBalance: false
    )
    prefs.syncEcardHideBalance(snapAppUnhid.hideBalance)
    XCTAssertFalse(snapAppUnhid.effectiveHideBalance(using: prefs))
  }

  func testWidgetURLConstruction() {
    XCTAssertEqual(TechPieWidgetURL.ecardPay().absoluteString, "techpie://ecard/pay")
    XCTAssertEqual(TechPieWidgetURL.schedule().absoluteString, "techpie://schedule")
    XCTAssertEqual(TechPieWidgetURL.deadlines().absoluteString, "techpie://deadlines")
  }
}
