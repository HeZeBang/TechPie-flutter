import Darwin
import Flutter
import NetworkExtension

final class EcardBindPlugin: NSObject {
  private static let channelName = "techpie/ecard_bind"
  private static let allowedHost = "ecard.shanghaitech.edu.cn"
  private static let allowedIP = "119.78.254.196"

  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "techpie.ecard-bind.manager")
  private var operations: [(@escaping () -> Void) -> Void] = []
  private var operationRunning = false

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let reply = { (value: Any?) in
      DispatchQueue.main.async { result(value) }
    }

    #if targetEnvironment(simulator)
      reply("unsupported")
      return
    #else
      switch call.method {
      case "start":
        guard
          let arguments = call.arguments as? [String: Any],
          let host = arguments["host"] as? String,
          let ip = arguments["ip"] as? String
        else {
          reply(FlutterError(
            code: "invalid_arguments",
            message: "start requires host and ip strings",
            details: nil
          ))
          return
        }
        guard host == Self.allowedHost, ip == Self.allowedIP else {
          reply(FlutterError(
            code: "invalid_arguments",
            message: "Only the campus eCard endpoint may use this tunnel",
            details: nil
          ))
          return
        }
        enqueue { [weak self] finished in
          self?.start(host: host, ip: ip, result: reply, finished: finished)
            ?? finished()
        }
      case "stop":
        enqueue { [weak self] finished in
          self?.stop(result: reply, finished: finished) ?? finished()
        }
      case "status":
        enqueue { [weak self] finished in
          self?.status(result: reply, finished: finished) ?? finished()
        }
      default:
        reply(FlutterMethodNotImplemented)
      }
    #endif
  }

  private func enqueue(_ operation: @escaping (@escaping () -> Void) -> Void) {
    queue.async {
      self.operations.append(operation)
      self.runNextOperationIfNeeded()
    }
  }

  private func runNextOperationIfNeeded() {
    guard !operationRunning, !operations.isEmpty else { return }
    operationRunning = true
    let operation = operations.removeFirst()
    operation { [weak self] in
      self?.queue.async {
        guard let self else { return }
        self.operationRunning = false
        self.runNextOperationIfNeeded()
      }
    }
  }

  private func start(
    host: String,
    ip: String,
    result: @escaping (Any?) -> Void,
    finished: @escaping () -> Void
  ) {
    loadManager { [weak self] loadResult in
      guard let self else {
        finished()
        return
      }
      self.queue.async {
        switch loadResult {
        case .failure(let error):
          self.complete(
            error: error,
            code: "ECARD_BIND_START_FAILED",
            result: result,
            finished: finished
          )
        case .success(let existingManager):
          let manager = existingManager ?? NETunnelProviderManager()
          let provider = NETunnelProviderProtocol()
          provider.providerBundleIdentifier = self.providerBundleIdentifier
          provider.serverAddress = host
          provider.providerConfiguration = [
            "host": host,
            "ip": ip,
          ]
          manager.protocolConfiguration = provider
          manager.localizedDescription = "TechPie eCard"
          manager.isEnabled = true
          manager.saveToPreferences { [weak self] error in
            guard let self else {
              finished()
              return
            }
            self.queue.async {
              if let error {
                self.complete(
                  error: error,
                  code: "ECARD_BIND_START_FAILED",
                  allowConfigurationDenial: true,
                  result: result,
                  finished: finished
                )
                return
              }
              manager.loadFromPreferences { [weak self] error in
                guard let self else {
                  finished()
                  return
                }
                self.queue.async {
                  if let error {
                    self.complete(
                      error: error,
                      code: "ECARD_BIND_START_FAILED",
                      result: result,
                      finished: finished
                    )
                    return
                  }
                  if manager.connection.status == .connected {
                    result("active")
                    finished()
                    return
                  }
                  if manager.connection.status != .connecting
                    && manager.connection.status != .reasserting
                  {
                    do {
                      try manager.connection.startVPNTunnel()
                    } catch {
                      self.complete(
                        error: error,
                        code: "ECARD_BIND_START_FAILED",
                        result: result,
                        finished: finished
                      )
                      return
                    }
                  }
                  self.wait(
                    for: manager.connection,
                    desired: [.connected],
                    failure: [.disconnected, .invalid],
                    timeout: 25,
                    errorCode: "ECARD_BIND_START_FAILED"
                  ) { error in
                    if let error {
                      manager.connection.stopVPNTunnel()
                      result(error)
                    } else {
                      result("active")
                    }
                    finished()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  private func stop(
    result: @escaping (Any?) -> Void,
    finished: @escaping () -> Void
  ) {
    loadManager { [weak self] loadResult in
      guard let self else {
        finished()
        return
      }
      self.queue.async {
        switch loadResult {
        case .failure(let error):
          self.complete(
            error: error,
            code: "ECARD_BIND_STOP_FAILED",
            result: result,
            finished: finished
          )
        case .success(nil):
          result("inactive")
          finished()
        case .success(let manager?):
          let status = manager.connection.status
          guard status != .disconnected && status != .invalid else {
            result("inactive")
            finished()
            return
          }
          manager.connection.stopVPNTunnel()
          self.wait(
            for: manager.connection,
            desired: [.disconnected, .invalid],
            failure: [],
            timeout: 15,
            errorCode: "ECARD_BIND_STOP_FAILED"
          ) { error in
            if let error {
              result(error)
            } else {
              result("inactive")
            }
            finished()
          }
        }
      }
    }
  }

  private func status(
    result: @escaping (Any?) -> Void,
    finished: @escaping () -> Void
  ) {
    loadManager { [weak self] loadResult in
      guard let self else {
        finished()
        return
      }
      self.queue.async {
        switch loadResult {
        case .failure(let error):
          self.complete(
            error: error,
            code: "ECARD_BIND_STATUS_FAILED",
            result: result,
            finished: finished
          )
        case .success(let manager):
          result(manager?.connection.status == .connected ? "active" : "inactive")
          finished()
        }
      }
    }
  }

  private var providerBundleIdentifier: String {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      return ""
    }
    return bundleIdentifier + ".EcardBindTunnel"
  }

  private func loadManager(
    completion: @escaping (Result<NETunnelProviderManager?, Error>) -> Void
  ) {
    let expectedIdentifier = providerBundleIdentifier
    guard !expectedIdentifier.isEmpty else {
      completion(.failure(PluginError.missingBundleIdentifier))
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(.failure(error))
        return
      }
      let manager = managers?.first { manager in
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == expectedIdentifier
      }
      completion(.success(manager))
    }
  }

  private func wait(
    for connection: NEVPNConnection,
    desired: Set<NEVPNStatus>,
    failure: Set<NEVPNStatus>,
    timeout: TimeInterval,
    errorCode: String,
    completion: @escaping (FlutterError?) -> Void
  ) {
    var observer: NSObjectProtocol?
    var timeoutWork: DispatchWorkItem?
    var completed = false

    let finish: (FlutterError?) -> Void = { [weak self] error in
      guard let self else { return }
      self.queue.async {
        guard !completed else { return }
        completed = true
        if let observer {
          NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        timeoutWork?.cancel()
        timeoutWork = nil
        completion(error)
      }
    }

    let inspect: (Bool) -> Void = { fromNotification in
      let status = connection.status
      if desired.contains(status) {
        finish(nil)
      } else if fromNotification && failure.contains(status) {
        finish(FlutterError(
          code: errorCode,
          message: "The eCard tunnel failed to reach the requested state",
          details: nil
        ))
      }
    }

    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: connection,
      queue: nil
    ) { _ in inspect(true) }
    let work = DispatchWorkItem {
      finish(FlutterError(
        code: errorCode,
        message: "Timed out waiting for the eCard tunnel",
        details: nil
      ))
    }
    timeoutWork = work
    queue.asyncAfter(deadline: .now() + timeout, execute: work)
    inspect(false)
  }

  private func complete(
    error: Error,
    code: String,
    allowConfigurationDenial: Bool = false,
    result: @escaping (Any?) -> Void,
    finished: @escaping () -> Void
  ) {
    let nsError = error as NSError
    let deniedWhileSaving = allowConfigurationDenial
      && nsError.domain == NEVPNErrorDomain
      && nsError.code == NEVPNError.configurationReadWriteFailed.rawValue
    if deniedWhileSaving || isAuthorizationDenial(error) {
      result("denied")
    } else {
      result(FlutterError(
        code: code,
        message: nsError.localizedDescription,
        details: ["domain": nsError.domain, "code": nsError.code]
      ))
    }
    finished()
  }

  private func isAuthorizationDenial(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      return nsError.code == NSUserCancelledError
        || nsError.code == NSFileReadNoPermissionError
        || nsError.code == NSFileWriteNoPermissionError
    }
    if nsError.domain == NSPOSIXErrorDomain {
      return nsError.code == Int(EPERM) || nsError.code == Int(EACCES)
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      return isAuthorizationDenial(underlying)
    }
    return false
  }
}

private enum PluginError: LocalizedError {
  case missingBundleIdentifier

  var errorDescription: String? {
    switch self {
    case .missingBundleIdentifier:
      return "The host app has no bundle identifier"
    }
  }
}
