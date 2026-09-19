import XCTest
@testable import WatchSupport

final class OfflineCodeTests: XCTestCase {
  let keyHex = String(repeating: "0", count: 63) + "1"
  func testLivePeerSurvivesStaleInstallationMetadataButNeverTargetsAnotherWatch() {
    let live = WatchPeerStatus(active: true, paired: true, reportedInstalled: false,
      directory: nil, liveInstallationID: "WATCH-A", nonce: "CHALLENGE")
    XCTAssertTrue(live.canEnroll)
    XCTAssertTrue(live.canDeliver(to: "WATCH-A"))
    XCTAssertFalse(live.canDeliver(to: "WATCH-B"))
    let metadataOnly = WatchPeerStatus(active: true, paired: true, reportedInstalled: true,
      directory: "legacy-directory", liveInstallationID: nil, nonce: nil)
    XCTAssertFalse(metadataOnly.canEnroll)
    XCTAssertFalse(metadataOnly.canDeliver(to: "WATCH-A"))
    let inactive = WatchPeerStatus(active: false, paired: true, reportedInstalled: true,
      directory: "legacy-directory", liveInstallationID: "WATCH-A", nonce: "CHALLENGE")
    XCTAssertFalse(inactive.canDeliver(to: "WATCH-A"))
  }
  func testFullGrantFromDartWithNontrivialKey() throws {
    let url = Bundle.module.url(forResource: "dart-grant", withExtension: "json", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    let incoming = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let encoded = try JSONSerialization.data(withJSONObject: incoming)
    let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: encoded)
    XCTAssertNoThrow(try snapshot.validate())
    XCTAssertTrue(try snapshot.canReplace(nil, target: "SYNTHETIC-WATCH", nonce: "SYNTHETIC-NONCE"))
  }
  func testSignatureProducedByExistingDartImplementation() throws {
    let url = Bundle.module.url(forResource: "dart-sm2", withExtension: "json", subdirectory: "Fixtures")!
    let vector = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    XCTAssertTrue(OfflineCode.verify(message: try Data(strictHex: vector["message"]!),
      publicKey: try Data(strictHex: vector["publicKey"]!), signature: try Data(strictHex: vector["signature"]!)))
  }
  func testSM3TimeAndRawSignature() throws {
    let date = ISO8601DateFormatter().date(from: "2026-08-31T12:00:00Z")!
    XCTAssertEqual(try OfflineCode.timeCRC(deviceCode: "DEMO-DEVICE-0001", now: date).hex, "6A956CC09D")
    // This is the only device value transmitted by the phone; raw OpenID stays there.
    XCTAssertEqual(try OfflineCode.timeCRC(deviceChecksum: 206, now: date).hex, "6A956CC09D")
    let key = try Data(strictHex: keyHex)
    let publicKey = try OfflineCode.publicKey(privateKey: key)
    XCTAssertEqual(publicKey.hex, "0232C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7")
    let message = Data([0x56, 0x38, 0x00, 0x80, 0xff])
    let signature = try OfflineCode.sign(message: message, privateKey: key)
    XCTAssertEqual(signature.count, 64)
    XCTAssertTrue(OfflineCode.verify(message: message, publicKey: publicKey, signature: signature))
    XCTAssertFalse(OfflineCode.verify(message: message + Data([0]), publicKey: publicKey, signature: signature))
    XCTAssertThrowsError(try OfflineCode.publicKey(privateKey: Data(repeating: 0, count: 32)))
    XCTAssertThrowsError(try Data(strictHex: "0g"))
    XCTAssertThrowsError(try Data(strictHex: "123"))
  }

  func testQRPreservesBinaryInput() throws {
    let binary = try OfflineCode.qr(Data([0x56, 0x38, 0x00, 0x80, 0xff]))
    let utf8 = try OfflineCode.qr(Data("V8\0\u{80}ÿ".utf8))
    XCTAssertNotEqual(binary.modules, utf8.modules)
    XCTAssertEqual(binary.side, 21)
    XCTAssertEqual(binary.modules.count, 21 * 21)
  }

  func testExpiryKeyMismatchAndReplay() throws {
    let key = try Data(strictHex: keyHex)
    var grant = WatchCredential(cardID: "TEST", privateKey: keyHex,
      publicKey: try OfflineCode.publicKey(privateKey: key).hex, deviceChecksum: 42,
      authorInfo: "5638A1B2", expiresAt: 200, totalUses: nil)
    XCTAssertNoThrow(try OfflineCode.generate(grant, now: Date(timeIntervalSince1970: 199)))
    XCTAssertThrowsError(try OfflineCode.generate(grant, now: Date(timeIntervalSince1970: 200)))
    grant.publicKey = "03" + grant.publicKey.dropFirst(2)
    XCTAssertThrowsError(try grant.validate())
    let old = WatchSnapshot(version: 1, sourceID: "PHONE", targetID: "WATCH", revision: 2,
      enrollmentNonce: "NONCE", enabled: false, subject: nil, card: nil, credential: nil)
    XCTAssertTrue(try old.canReplace(nil, target: "WATCH", nonce: "NONCE"))
    XCTAssertFalse(try old.canReplace(nil, target: "OTHER", nonce: "NONCE"))
    XCTAssertFalse(try old.canReplace(nil, target: "WATCH", nonce: "STALE"))
    XCTAssertFalse(try old.canReplace(old, target: "WATCH", nonce: "NONCE"))
    var newer = old; newer.revision = 3
    XCTAssertTrue(try newer.canReplace(old, target: "WATCH", nonce: "NONCE"))
    newer.sourceID = "OTHER-PHONE"; newer.enrollmentNonce = nil
    XCTAssertFalse(try newer.canReplace(old, target: "WATCH", nonce: "NONCE"))
  }
}
