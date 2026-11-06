import Foundation

public enum DeadlineSnapshotState {
  case ready(DeadlineSnapshot)
  case notSynced
  case unavailable
}

public final class DeadlineSnapshotStore {
  public static let fileName = "deadline-widget-v1.json"
  private let directory: URL

  public init(directory: URL) { self.directory = directory }

  public static func configured(in bundle: Bundle = .main) -> DeadlineSnapshotStore? {
    guard let group = bundle.object(forInfoDictionaryKey: "TechPieDeadlineAppGroup") as? String,
      !group.isEmpty,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return DeadlineSnapshotStore(directory: directory.appendingPathComponent("Library/Application Support", isDirectory: true))
  }

  private var url: URL { directory.appendingPathComponent(Self.fileName) }

  public func read() -> DeadlineSnapshotState {
    do {
      return .ready(try DeadlineSnapshot.decode(Data(contentsOf: url)))
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      // macOS can return a URL for an unauthorized group. Check access separately.
      let root = directory.deletingLastPathComponent().deletingLastPathComponent()
      return FileManager.default.isReadableFile(atPath: root.path) ? .notSynced : .unavailable
    } catch { return .unavailable }
  }

  @discardableResult public func write(_ data: Data) throws -> Bool {
    let snapshot = try DeadlineSnapshot.decode(data)
    if case .ready(let saved) = read(), saved.items == snapshot.items { return false }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    #endif
    return true
  }

  @discardableResult public func clear() throws -> Bool {
    do { try FileManager.default.removeItem(at: url); return true }
    catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { return false }
  }
}
