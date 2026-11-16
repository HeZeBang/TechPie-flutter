import Foundation
import Security

public enum WatchKeychain {
  private static func query(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "club.geekpie.techpie.watch",
     kSecAttrAccount as String: key,
     kSecAttrSynchronizable as String: false]
  }

  public static func read(_ key: String) throws -> Data? {
    var fields = query(key)
    fields[kSecReturnData as String] = true
    fields[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(fields as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    return result as? Data
  }

  public static func write(_ data: Data, key: String) throws {
    let values: [String: Any] = [kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    var status = SecItemUpdate(query(key) as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var fields = query(key)
      values.forEach { fields[$0.key] = $0.value }
      status = SecItemAdd(fields as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
  }

  public static func identifier(_ key: String) throws -> String {
    if let data = try read(key), let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
    let value = UUID().uuidString
    try write(Data(value.utf8), key: key)
    return value
  }
}
