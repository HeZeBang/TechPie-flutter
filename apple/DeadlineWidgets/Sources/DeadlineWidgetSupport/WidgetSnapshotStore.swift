import Foundation

public enum WidgetSnapshotError: Error {
  case invalidData
}

public enum WidgetSnapshotState<Snapshot: Equatable>: Equatable {
  case ready(Snapshot)
  case notSynced
  case unavailable
}

enum WidgetJSONCodec {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      if let date = parseISO8601(raw) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO8601 date: \(raw)"
      )
    }
    return decoder
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static func parseISO8601(_ value: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = withFractional.date(from: value) {
      return parsed
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
  }
}

public enum WidgetAppGroup {
  public static func identifier(in bundle: Bundle = .main) -> String? {
    guard let group = bundle.object(forInfoDictionaryKey: "TechPieDeadlineAppGroup") as? String,
      !group.isEmpty
    else { return nil }
    return group
  }

  public static func supportDirectory(in bundle: Bundle = .main) -> URL? {
    guard let group = identifier(in: bundle),
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group
      )
    else { return nil }
    return container.appendingPathComponent("Library/Application Support", isDirectory: true)
  }

  public static func userDefaults(in bundle: Bundle = .main) -> UserDefaults? {
    guard let group = identifier(in: bundle) else { return nil }
    return UserDefaults(suiteName: group)
  }
}

public final class ScheduleSnapshotStore {
  public static let fileName = "schedule-widget-v1.json"
  private let directory: URL

  public init(directory: URL) { self.directory = directory }

  public static func configured(in bundle: Bundle = .main) -> ScheduleSnapshotStore? {
    guard let directory = WidgetAppGroup.supportDirectory(in: bundle) else { return nil }
    return ScheduleSnapshotStore(directory: directory)
  }

  private var url: URL { directory.appendingPathComponent(Self.fileName) }

  public func read() -> WidgetSnapshotState<ScheduleWidgetSnapshot> {
    do {
      return .ready(try ScheduleWidgetSnapshot.decode(Data(contentsOf: url)))
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    {
      let root = directory.deletingLastPathComponent().deletingLastPathComponent()
      return FileManager.default.isReadableFile(atPath: root.path) ? .notSynced : .unavailable
    } catch {
      return .unavailable
    }
  }

  @discardableResult
  public func write(_ data: Data) throws -> Bool {
    let snapshot = try ScheduleWidgetSnapshot.decode(data)
    if case .ready(let saved) = read(), saved.semanticEquals(snapshot) {
      return false
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    #if os(iOS)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    #endif
    return true
  }

  @discardableResult
  public func clear() throws -> Bool {
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      return false
    }
  }
}

public final class EcardSnapshotStore {
  public static let fileName = "ecard-widget-v1.json"
  private let directory: URL

  public init(directory: URL) { self.directory = directory }

  public static func configured(in bundle: Bundle = .main) -> EcardSnapshotStore? {
    guard let directory = WidgetAppGroup.supportDirectory(in: bundle) else { return nil }
    return EcardSnapshotStore(directory: directory)
  }

  private var url: URL { directory.appendingPathComponent(Self.fileName) }

  public func read() -> WidgetSnapshotState<EcardWidgetSnapshot> {
    do {
      return .ready(try EcardWidgetSnapshot.decode(Data(contentsOf: url)))
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    {
      let root = directory.deletingLastPathComponent().deletingLastPathComponent()
      return FileManager.default.isReadableFile(atPath: root.path) ? .notSynced : .unavailable
    } catch {
      return .unavailable
    }
  }

  @discardableResult
  public func write(_ data: Data) throws -> Bool {
    let snapshot = try EcardWidgetSnapshot.decode(data)
    if case .ready(let saved) = read(), saved.semanticEquals(snapshot) {
      return false
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    #if os(iOS)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    #endif
    return true
  }

  @discardableResult
  public func clear() throws -> Bool {
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      return false
    }
  }
}

public final class WidgetPreferenceStore {
  private static let ecardMaskOverrideKey = "techpie.widget.ecard.maskOverride"
  private static let ecardSyncedHideKey = "techpie.widget.ecard.syncedHide"
  private static let scheduleDayModeKey = "techpie.widget.schedule.dayMode"
  private static let scheduleDayModeDateKey = "techpie.widget.schedule.dayModeDate"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  public static func configured(in bundle: Bundle = .main) -> WidgetPreferenceStore? {
    guard let defaults = WidgetAppGroup.userDefaults(in: bundle) else { return nil }
    return WidgetPreferenceStore(defaults: defaults)
  }

  /// Clears any local widget mask override whenever the main app changes its
  /// persisted `hideCampusCardBalance` setting, while preserving an active
  /// widget override when only the balance refreshes with the same app setting.
  public func syncEcardHideBalance(_ syncedHide: Bool) {
    let previous = defaults.object(forKey: Self.ecardSyncedHideKey) as? Bool
    if previous != syncedHide {
      defaults.set(syncedHide, forKey: Self.ecardSyncedHideKey)
      defaults.removeObject(forKey: Self.ecardMaskOverrideKey)
    }
  }

  public func effectiveHideBalance(for snapshot: EcardWidgetSnapshot) -> Bool {
    let storedSynced = defaults.object(forKey: Self.ecardSyncedHideKey) as? Bool
    if storedSynced == snapshot.hideBalance,
      let overrideMask = defaults.object(forKey: Self.ecardMaskOverrideKey) as? Bool
    {
      return overrideMask
    }
    return snapshot.hideBalance
  }

  @discardableResult
  public func toggleEcardBalanceMask(currentSyncedHide: Bool) -> Bool {
    let storedSynced = defaults.object(forKey: Self.ecardSyncedHideKey) as? Bool
    let currentEffective: Bool
    if storedSynced == currentSyncedHide,
      let overrideMask = defaults.object(forKey: Self.ecardMaskOverrideKey) as? Bool
    {
      currentEffective = overrideMask
    } else {
      currentEffective = currentSyncedHide
    }
    let next = !currentEffective
    defaults.set(currentSyncedHide, forKey: Self.ecardSyncedHideKey)
    defaults.set(next, forKey: Self.ecardMaskOverrideKey)
    return next
  }

  public func scheduleDayMode(
    at now: Date,
    calendar: Calendar = .current
  ) -> ScheduleDayMode {
    let todayKey = ScheduleWidgetResolver.dateKey(for: now, calendar: calendar)
    guard defaults.string(forKey: Self.scheduleDayModeDateKey) == todayKey,
      let raw = defaults.string(forKey: Self.scheduleDayModeKey),
      let mode = ScheduleDayMode(rawValue: raw)
    else {
      return .auto
    }
    return mode
  }

  @discardableResult
  public func toggleScheduleDayMode(
    currentlyShowingTomorrowOrLater: Bool,
    at now: Date,
    calendar: Calendar = .current
  ) -> ScheduleDayMode {
    let next: ScheduleDayMode = currentlyShowingTomorrowOrLater ? .today : .tomorrow
    let todayKey = ScheduleWidgetResolver.dateKey(for: now, calendar: calendar)
    defaults.set(next.rawValue, forKey: Self.scheduleDayModeKey)
    defaults.set(todayKey, forKey: Self.scheduleDayModeDateKey)
    return next
  }

  public func clearScheduleDayMode() {
    defaults.removeObject(forKey: Self.scheduleDayModeKey)
    defaults.removeObject(forKey: Self.scheduleDayModeDateKey)
  }
}
