import Flutter
import NetworkExtension

/// Starts the short-lived, single-domain resolver used to read a bind code in
/// the WeChat mini program. The packet tunnel has no default IP route.
final class EcardBindTunnelPlugin {
  private let channel: FlutterMethodChannel
  private let providerBundleIdentifier: String

  init(messenger: FlutterBinaryMessenger) {
    providerBundleIdentifier = "\(Bundle.main.bundleIdentifier ?? "com.example.techpie").EcardBindTunnel"
    channel = FlutterMethodChannel(name: "techpie/ecard_bind", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      #if targetEnvironment(simulator)
      // Simulator has no nehelper connection; manual OPENID login remains available.
      switch call.method {
      case "start", "status": result("unsupported")
      case "stop": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
      #else
      guard let self else {
        result(FlutterError(code: "ECARD_TUNNEL_UNAVAILABLE", message: "无法读取自动获取状态", details: nil))
        return
      }
      switch call.method {
      case "start": self.start(call, result)
      case "stop": self.stop(result)
      case "status": self.status(result)
      default: result(FlutterMethodNotImplemented)
      }
      #endif
    }
  }

  private func load(_ completion: @escaping (NETunnelProviderManager?, FlutterError?) -> Void) {
    let providerIdentifier = providerBundleIdentifier
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if error != nil {
        completion(nil, FlutterError(
          code: "ECARD_TUNNEL_PREFERENCES_UNAVAILABLE",
          message: "无法读取自动获取配置，请重试", details: nil
        ))
        return
      }
      let selected = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
          == providerIdentifier
      }
      completion(selected, nil)
    }
  }

  private func status(_ result: @escaping FlutterResult) {
    load { manager, error in
      if let error {
        result(error)
        return
      }
      guard let manager else {
        result("inactive")
        return
      }
      switch manager.connection.status {
      case .disconnected, .invalid: result("inactive")
      case .connected: result("active")
      default: result("unknown")
      }
    }
  }

  private func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    load { [weak self] existing, error in
      if let error {
        result(error)
        return
      }
      guard let self else {
        result("unknown")
        return
      }
      let manager = existing ?? NETunnelProviderManager()
      if manager.connection.status == .connected {
        result("active")
        return
      }
      let configuration = NETunnelProviderProtocol()
      configuration.providerBundleIdentifier = self.providerBundleIdentifier
      configuration.serverAddress = "TechPie eCard DNS"
      // The host and mirror address come from Dart so the tunnel does not keep a
      // second copy of them; the provider falls back to its own defaults when
      // they are absent.
      if let arguments = call.arguments as? [String: Any],
        let host = arguments["host"] as? String,
        let ip = arguments["ip"] as? String
      {
        configuration.providerConfiguration = ["host": host, "ip": ip]
      }
      manager.protocolConfiguration = configuration
      manager.localizedDescription = "TechPie eCard 自动获取"
      manager.isEnabled = true
      manager.isOnDemandEnabled = false
      manager.saveToPreferences { error in
        guard error == nil else {
          result("unknown")
          return
        }
        manager.loadFromPreferences { error in
          guard error == nil else {
            result("unknown")
            return
          }
          do {
            try manager.connection.startVPNTunnel()
            self.waitForConnection(manager, result: result, remaining: 20)
          } catch {
            result("unknown")
          }
        }
      }
    }
  }

  private func waitForConnection(
    _ manager: NETunnelProviderManager,
    result: @escaping FlutterResult,
    remaining: Int
  ) {
    if manager.connection.status == .connected {
      result("active")
    } else if remaining == 0 {
      manager.connection.stopVPNTunnel()
      waitForDisconnection(manager, result: { value in
        if let error = value as? FlutterError {
          result(error)
        } else {
          result("inactive")
        }
      }, remaining: 10)
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        guard let self else {
          result("unknown")
          return
        }
        self.waitForConnection(manager, result: result, remaining: remaining - 1)
      }
    }
  }

  private func stop(_ result: @escaping FlutterResult) {
    load { [weak self] manager, error in
      if let error {
        result(error)
        return
      }
      guard let self else {
        result(FlutterError(code: "ECARD_TUNNEL_UNAVAILABLE", message: "无法停止自动获取", details: nil))
        return
      }
      guard let manager else {
        result(nil)
        return
      }
      manager.connection.stopVPNTunnel()
      self.waitForDisconnection(manager, result: result, remaining: 10)
    }
  }

  private func waitForDisconnection(
    _ manager: NETunnelProviderManager,
    result: @escaping FlutterResult,
    remaining: Int
  ) {
    let status = manager.connection.status
    if status == .disconnected || status == .invalid {
      result(nil)
    } else if remaining == 0 {
      result(FlutterError(code: "ECARD_TUNNEL_STILL_ACTIVE", message: "eCard DNS 仍在断开中", details: nil))
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        guard let self else {
          result(FlutterError(code: "ECARD_TUNNEL_UNAVAILABLE", message: "无法确认自动获取已停止", details: nil))
          return
        }
        self.waitForDisconnection(manager, result: result, remaining: remaining - 1)
      }
    }
  }
}
