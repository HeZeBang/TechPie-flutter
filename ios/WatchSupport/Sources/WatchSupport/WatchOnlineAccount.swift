import Foundation
import CryptoKit

/// Login parameters approved by the paired phone. The watch acquires its own cookie.
public struct WatchOnlineAccount: Codable, Equatable, Sendable {
  public var openID: String
  public var method: String
  public var idSerial: String
  public var cardID: String
  public var sessionEndpoint: String

  public init(openID: String, method: String, idSerial: String, cardID: String, sessionEndpoint: String) {
    self.openID = openID
    self.method = method
    self.idSerial = idSerial
    self.cardID = cardID
    self.sessionEndpoint = sessionEndpoint
  }

  public var subject: String {
    let value = method == "wechat_openid" ? openID : "\(method):\(openID)"
    return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public var userType: String { method == "alipay_openid" ? "18" : "8" }

  public func validate() throws {
    guard (16...256).contains(openID.count), !openID.contains(where: { $0.isWhitespace }),
      ["wechat_openid", "alipay_openid"].contains(method),
      !idSerial.isEmpty, idSerial.count <= 256, !cardID.isEmpty, cardID.count <= 256,
      let endpoint = URLComponents(string: sessionEndpoint), endpoint.scheme == "https",
      let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil,
      endpoint.query == nil, endpoint.fragment == nil,
      endpoint.path.hasSuffix("/auth/third-party/ecard"),
      endpoint.port == nil || (1...65535).contains(endpoint.port!) else {
      throw WatchOnlineFailure.invalidAccount
    }
  }
}

public enum WatchOnlineFailure: Error, LocalizedError, Equatable {
  case invalidAccount, authentication, identityMismatch, network, server, invalidResponse, notActivated, rejected

  public var permitsOfflineFallback: Bool { self == .network || self == .server }

  public var errorDescription: String? {
    switch self {
    case .invalidAccount: return "请在手机重新同步在线码授权"
    case .authentication: return "在线登录失败，请在手机检查校园卡账号后同步"
    case .identityMismatch: return "校园卡身份不一致，请在手机重新同步"
    case .network: return "无法联网获取在线码，请重试或切换离线码"
    case .server: return "在线码服务暂不可用，请重试或切换离线码"
    case .invalidResponse: return "在线码数据无效，请重试"
    case .notActivated: return "请在手机开通在线消费码后重试"
    case .rejected: return "服务拒绝生成在线码，请在手机检查校园卡状态"
    }
  }
}
