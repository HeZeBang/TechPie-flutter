import Foundation
import CWatchCrypto

/// eCard's existing AES envelope, including its rotated/reversed ASCII key header.
public enum WatchEcardCipher {
  public static func encode(_ payload: [String: String]) throws -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    let key = String((0..<16).map { _ in alphabet.randomElement()! })
    return try encodeJSON(JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), key: key)
  }

  public static func encodeJSON(_ json: Data, key: String) throws -> String {
    let bytes = try keyBytes(key)
    let rotated = Array(bytes[10...] + bytes[..<10]).reversed()
    return String(bytes: rotated, encoding: .ascii)! + (try crypt(json, key: bytes, encrypt: true)).base64EncodedString()
  }

  public static func decode(_ data: Data) throws -> [String: Any] {
    guard data.count <= 131_072,
      let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw WatchOnlineFailure.invalidResponse
    }
    guard let value = outer["datajson"] else { return outer }
    guard let envelope = value as? String else { throw WatchOnlineFailure.invalidResponse }
    return try decodeEnvelope(envelope)
  }

  public static func decodeEnvelope(_ envelope: String) throws -> [String: Any] {
    guard envelope.utf8.count > 16, envelope.utf8.count <= 131_072 else { throw WatchOnlineFailure.invalidResponse }
    let header = try keyBytes(String(envelope.prefix(16)))
    let reversed = Array(header.reversed())
    let key = Array(reversed[6...] + reversed[..<6])
    guard let encrypted = Data(base64Encoded: String(envelope.dropFirst(16))),
      !encrypted.isEmpty, encrypted.count.isMultiple(of: 16) else { throw WatchOnlineFailure.invalidResponse }
    let plain = try crypt(encrypted, key: key, encrypt: false)
    let decoded = try JSONSerialization.jsonObject(with: plain, options: [.fragmentsAllowed])
    if let object = decoded as? [String: Any] { return object }
    if let nested = decoded as? String, let data = nested.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
    throw WatchOnlineFailure.invalidResponse
  }

  private static func keyBytes(_ key: String) throws -> [UInt8] {
    let bytes = Array(key.utf8)
    guard bytes.count == 16, bytes.allSatisfy({
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
    }) else { throw WatchOnlineFailure.invalidResponse }
    return bytes
  }

  private static func crypt(_ data: Data, key: [UInt8], encrypt: Bool) throws -> Data {
    var output = [UInt8](repeating: 0, count: data.count + 16)
    let capacity = output.count
    let written = key.withUnsafeBytes { keyBytes in
      data.withUnsafeBytes { input in
        tp_aes_ecb(keyBytes.bindMemory(to: UInt8.self).baseAddress!,
          input.bindMemory(to: UInt8.self).baseAddress!, data.count, encrypt ? 1 : 0, &output, capacity)
      }
    }
    guard written >= 0 else { throw WatchOnlineFailure.invalidResponse }
    return Data(output.prefix(Int(written)))
  }
}
