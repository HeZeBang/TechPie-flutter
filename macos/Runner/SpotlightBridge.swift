import Cocoa
import CoreSpotlight
import FlutterMacOS
import UniformTypeIdentifiers

/// Mirrors TechPie's desktop command palette into macOS Spotlight via
/// CoreSpotlight and routes Spotlight item activations back to Flutter.
final class SpotlightBridge {
  static let channelName = "techpie/spotlight"
  static let domainIdentifier = "club.geekpie.techpie.commands"
  static let commandActivityType = "club.geekpie.techpie.command"
  private static let indexedIdsDefaultsKey = "techpie.spotlight.indexed_command_ids"

  private var channel: FlutterMethodChannel?
  private var pendingCommandId: String?
  private var currentActivity: NSUserActivity?

  func configure(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let methodChannel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "syncItems":
        guard let rawItems = call.arguments as? [[String: Any]] else {
          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "Expected a list of Spotlight command maps.",
              details: nil
            )
          )
          return
        }
        self.syncItems(rawItems, result: result)
      case "donateUsage":
        guard let rawItem = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "Expected a Spotlight command map.",
              details: nil
            )
          )
          return
        }
        self.donateUsage(rawItem, result: result)
      case "clearItems":
        self.clearItems(result: result)
      case "consumePendingCommand":
        result(self.pendingCommandId)
      case "acknowledgePendingCommand":
        self.pendingCommandId = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }

  /// Handles Spotlight activation via `NSUserActivity`. Returns `true` when
  /// the activity is a TechPie Spotlight command item.
  func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
    guard
      userActivity.activityType == CSSearchableItemActionType
        || userActivity.activityType == Self.commandActivityType
    else {
      return false
    }
    guard
      let rawId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    else {
      return false
    }
    let commandId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !commandId.isEmpty else { return false }
    pendingCommandId = commandId
    channel?.invokeMethod("openCommand", arguments: commandId)
    return true
  }

  private func buildSearchableItem(
    from map: [String: Any],
    lastUsedDate: Date? = nil
  ) -> (item: CSSearchableItem, title: String, id: String)? {
    guard
      let id = (map["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !id.isEmpty,
      let title = (map["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    else {
      return nil
    }
    let subtitle = (map["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let group = (map["group"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let rawAliases = map["aliases"] as? [String] ?? []
    let rawKeywords = map["keywords"] as? [String] ?? []
    let rankingHint = (map["rankingHint"] as? NSNumber)?.intValue ?? 50

    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    attributes.displayName = title
    attributes.rankingHint = NSNumber(value: max(0, min(100, rankingHint)))
    if let lastUsedDate {
      attributes.lastUsedDate = lastUsedDate
      attributes.contentModificationDate = lastUsedDate
    }

    if !group.isEmpty && !subtitle.isEmpty {
      attributes.contentDescription = "\(group) · \(subtitle)"
    } else if !subtitle.isEmpty {
      attributes.contentDescription = subtitle
    } else if !group.isEmpty {
      attributes.contentDescription = group
    }

    // Keep alternateNames tight (title + explicit short aliases) so Spotlight
    // ranks exact alias hits cleanly without diluting term weight.
    let alternateNames = deduplicated([title] + rawAliases)
    attributes.alternateNames = alternateNames

    let keywords = deduplicated([title, group, "TechPie"] + rawAliases + rawKeywords)
    attributes.keywords = keywords

    let item = CSSearchableItem(
      uniqueIdentifier: id,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
    item.expirationDate = .distantFuture
    return (item, title, id)
  }

  private func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for candidate in values {
      let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let lowered = trimmed.lowercased()
      if seen.insert(lowered).inserted {
        out.append(trimmed)
      }
    }
    return out
  }

  private func syncItems(_ rawItems: [[String: Any]], result: @escaping FlutterResult) {
    guard CSSearchableIndex.isIndexingAvailable() else {
      result(false)
      return
    }
    let built = rawItems.compactMap { buildSearchableItem(from: $0) }
    let searchableItems = built.map(\.item)
    let currentIds = Set(built.map(\.id))
    let previousIds = Set(
      UserDefaults.standard.stringArray(forKey: Self.indexedIdsDefaultsKey) ?? []
    )
    let removedIds = Array(previousIds.subtracting(currentIds))

    let index = CSSearchableIndex.default()
    let finishUpsert: () -> Void = {
      UserDefaults.standard.set(Array(currentIds), forKey: Self.indexedIdsDefaultsKey)
      guard !searchableItems.isEmpty else {
        DispatchQueue.main.async { result(true) }
        return
      }
      // Upsert directly without wiping the domain so Spotlight preserves
      // learned engagement/selection history for existing commands.
      index.indexSearchableItems(searchableItems) { indexError in
        if let indexError {
          NSLog("[TechPie Spotlight] indexSearchableItems error: %@", indexError.localizedDescription)
          DispatchQueue.main.async { result(false) }
          return
        }
        DispatchQueue.main.async { result(true) }
      }
    }

    if removedIds.isEmpty {
      finishUpsert()
    } else {
      index.deleteSearchableItems(withIdentifiers: removedIds) { deleteError in
        if let deleteError {
          NSLog(
            "[TechPie Spotlight] deleteSearchableItems(removed) error: %@",
            deleteError.localizedDescription
          )
        }
        finishUpsert()
      }
    }
  }

  private func donateUsage(_ rawItem: [String: Any], result: @escaping FlutterResult) {
    let now = Date()
    guard let built = buildSearchableItem(from: rawItem, lastUsedDate: now) else {
      result(false)
      return
    }

    // Donate an NSUserActivity linked to the CoreSpotlight item so Spotlight
    // learns command recency and frequency.
    DispatchQueue.main.async {
      let activity = NSUserActivity(activityType: Self.commandActivityType)
      activity.title = built.title
      activity.isEligibleForSearch = true
      activity.userInfo = [CSSearchableItemActivityIdentifier: built.id]
      if let attrs = built.item.attributeSet.copy() as? CSSearchableItemAttributeSet {
        attrs.relatedUniqueIdentifier = built.id
        activity.contentAttributeSet = attrs
      }
      self.currentActivity = activity
      activity.becomeCurrent()
    }

    guard CSSearchableIndex.isIndexingAvailable() else {
      result(false)
      return
    }
    CSSearchableIndex.default().indexSearchableItems([built.item]) { error in
      if let error {
        NSLog("[TechPie Spotlight] donateUsage index error: %@", error.localizedDescription)
        DispatchQueue.main.async { result(false) }
        return
      }
      DispatchQueue.main.async { result(true) }
    }
  }

  private func clearItems(result: @escaping FlutterResult) {
    UserDefaults.standard.removeObject(forKey: Self.indexedIdsDefaultsKey)
    guard CSSearchableIndex.isIndexingAvailable() else {
      result(false)
      return
    }
    CSSearchableIndex.default().deleteSearchableItems(
      withDomainIdentifiers: [Self.domainIdentifier]
    ) { error in
      if let error {
        NSLog("[TechPie Spotlight] clearItems error: %@", error.localizedDescription)
        DispatchQueue.main.async { result(false) }
        return
      }
      DispatchQueue.main.async { result(true) }
    }
  }
}
