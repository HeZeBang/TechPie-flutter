import Foundation
import CWatchCrypto

public enum WatchFailure: Error, LocalizedError {
  case invalidCredential, expired, unsupportedQuota, encoding, invalidSnapshot
  public var errorDescription: String? {
    switch self {
    case .expired: return "离线授权已过期，请连接手机更新"
    case .unsupportedQuota: return "请在手机更新离线授权"
    case .invalidCredential: return "离线授权无效，请在手机重新同步"
    case .encoding: return "无法生成消费码，请重试"
    case .invalidSnapshot: return "同步数据无效，请在手机重新同步"
    }
  }
}

public extension Data {
  init(strictHex: String) throws {
    guard !strictHex.isEmpty, strictHex.count.isMultiple(of: 2),
      strictHex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
    else { throw WatchFailure.invalidCredential }
    let chars = Array(strictHex.utf8)
    self.init((stride(from: 0, to: chars.count, by: 2)).map {
      UInt8(String(bytes: chars[$0...$0 + 1], encoding: .utf8)!, radix: 16)!
    })
  }
  var hex: String { map { String(format: "%02X", $0) }.joined() }
}

public enum OfflineCode {
  public static func publicKey(privateKey: Data) throws -> Data {
    guard privateKey.count == 32 else { throw WatchFailure.invalidCredential }
    var output = [UInt8](repeating: 0, count: 33)
    let ok = privateKey.withUnsafeBytes { tp_public_key($0.bindMemory(to: UInt8.self).baseAddress!, &output) }
    guard ok == 1 else { throw WatchFailure.invalidCredential }
    return Data(output)
  }

  public static func timeCRC(deviceCode: String, now: Date) throws -> Data {
    guard !deviceCode.isEmpty else { throw WatchFailure.invalidCredential }
    let source = Data(deviceCode.utf8)
    var digest = [UInt8](repeating: 0, count: 32)
    source.withUnsafeBytes { tp_sm3($0.bindMemory(to: UInt8.self).baseAddress!, source.count, &digest) }
    return try timeCRC(deviceChecksum: Int(digest.reduce(0, ^)), now: now)
  }

  public static func timeCRC(deviceChecksum: Int, now: Date) throws -> Data {
    let seconds = now.timeIntervalSince1970.rounded(.down)
    guard seconds >= 0, seconds <= Double(UInt32.max), (0...255).contains(deviceChecksum) else { throw WatchFailure.invalidCredential }
    let value = UInt32(seconds)
    var bytes = [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
    bytes.append(bytes.reduce(UInt8(deviceChecksum), ^))
    return Data(bytes)
  }

  public static func sign(message: Data, privateKey: Data) throws -> Data {
    guard privateKey.count == 32, !message.isEmpty else { throw WatchFailure.invalidCredential }
    var signature = [UInt8](repeating: 0, count: 64)
    let ok = privateKey.withUnsafeBytes { key in
      message.withUnsafeBytes { body in
        tp_sm2_sign(key.bindMemory(to: UInt8.self).baseAddress!, body.bindMemory(to: UInt8.self).baseAddress!, message.count, &signature)
      }
    }
    guard ok == 1 else { throw WatchFailure.encoding }
    return Data(signature)
  }

  public static func verify(message: Data, publicKey: Data, signature: Data) -> Bool {
    guard publicKey.count == 33, signature.count == 64, !message.isEmpty else { return false }
    return publicKey.withUnsafeBytes { key in
      message.withUnsafeBytes { body in
        signature.withUnsafeBytes { sig in
          tp_sm2_verify(key.bindMemory(to: UInt8.self).baseAddress!, body.bindMemory(to: UInt8.self).baseAddress!, message.count, sig.bindMemory(to: UInt8.self).baseAddress!) == 1
        }
      }
    }
  }

  public static func generate(_ credential: WatchCredential, now: Date = Date()) throws -> Data {
    try credential.validate()
    guard credential.expiresAt > now.timeIntervalSince1970 else { throw WatchFailure.expired }
    let message = try Data(strictHex: credential.authorInfo) + timeCRC(deviceChecksum: credential.deviceChecksum, now: now)
    return try message + sign(message: message, privateKey: Data(strictHex: credential.privateKey))
  }

  public static func qr(_ payload: Data) throws -> QRMatrix {
    guard !payload.isEmpty else { throw WatchFailure.encoding }
    var modules = [UInt8](repeating: 0, count: 177 * 177)
    let count = modules.count
    let side = payload.withUnsafeBytes { tp_qr_encode($0.bindMemory(to: UInt8.self).baseAddress!, payload.count, &modules, count) }
    guard side > 0 else { throw WatchFailure.encoding }
    return QRMatrix(side: Int(side), modules: Array(modules.prefix(Int(side * side))))
  }
}

public struct QRMatrix: Sendable {
  public let side: Int
  public let modules: [UInt8]
}
