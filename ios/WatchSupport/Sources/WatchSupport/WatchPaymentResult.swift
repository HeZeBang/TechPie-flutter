import Foundation

public enum WatchPaymentResult: Equatable, Sendable {
  case pending, expired, notCompleted, useOffline
  case completed(amountFen: Int)

  // A successful status query is not itself a successful payment.
  static func decode(_ response: [String: Any]) throws -> Self {
    let data = response["data"] as? [String: Any] ?? response
    let status = data["status"].map(isBoolean) == true ? nil : Int(text(data["status"]))
    let message = text(data["message"]).isEmpty ? text(response["message"]) : text(data["message"])
    if status == 5 { return .pending }
    if status == 3 { return .expired }
    if matches(message, #"未(?:被)?使用|\bunused\b|\bnot (?:yet )?used\b"#) { return .pending }
    if ["开放平台返回失败", "开放平台请求超时"].contains(message) { return .useOffline }
    if paymentFailed(message) { return .notCompleted }
    let url = text(data["url"] ?? response["url"])
    let components = URLComponents(string: url)
    if paymentFailed(components?.queryItems?.first(where: { $0.name == "message" })?.value ?? "") {
      return .notCompleted
    }
    if succeeded(response), !(data["success"] != nil && !succeeded(data)), status == 1,
      ["/pages/common/success/success", "/pages/common/paysuccess/paysuccess"].contains(components?.path ?? ""),
      let rawAmount = data["txamt"], !(rawAmount is NSNull) {
      let amount = text(rawAmount)
      // Exact yuan, with no nonzero precision below one fen or partial number parsing.
      guard matches(amount, #"^[0-9]+(?:\.[0-9]{1,2}0*)?$"#),
        let yuan = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
        yuan * 100 <= Decimal(Int.max),
        !isBoolean(rawAmount) else {
        throw WatchOnlineFailure.invalidResponse
      }
      return .completed(amountFen: NSDecimalNumber(decimal: yuan * 100).intValue)
    }
    return url.isEmpty ? .pending : .notCompleted
  }

  private static func text(_ value: Any?) -> String {
    (value as? String ?? (value as? NSNumber)?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
  }

  private static func succeeded(_ map: [String: Any]) -> Bool {
    if let value = map["success"] as? NSNumber { return value == NSNumber(value: 1) }
    return text(map["success"]).lowercased() == "true"
  }

  private static func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func paymentFailed(_ text: String) -> Bool {
    matches(text, #"密码.*(?:错误|不正确|有误|失败|锁定|不匹配)|(?:支付|付款|交易)(?:失败|被拒绝|已取消)|(?:incorrect|invalid|wrong)\s+password|password.*(?:error|incorrect|invalid|failed|locked)|(?:payment|transaction)\s+(?:failed|declined|rejected|cancelled)"#)
  }
}
