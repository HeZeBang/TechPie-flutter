import Foundation
import WidgetKit
import DeadlineWidgetSupport

#if canImport(AppIntents)
import AppIntents

@available(iOS 17.0, macOS 14.0, *)
struct ToggleEcardBalanceMaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Toggle Balance Visibility"
  static var description = IntentDescription("Show or hide cached campus card balance on the widget.")

  @Parameter(title: "Synced Hide Balance")
  var currentSyncedHide: Bool

  init() {
    self.currentSyncedHide = false
  }

  init(currentSyncedHide: Bool) {
    self.currentSyncedHide = currentSyncedHide
  }

  func perform() async throws -> some IntentResult {
    WidgetPreferenceStore.configured()?.toggleEcardBalanceMask(
      currentSyncedHide: currentSyncedHide
    )
    WidgetCenter.shared.reloadTimelines(ofKind: "EcardPayWidget")
    return .result()
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct ToggleScheduleDayIntent: AppIntent {
  static var title: LocalizedStringResource = "Switch Schedule Day"
  static var description = IntentDescription("Switch between today's and tomorrow's schedule.")

  @Parameter(title: "Showing Tomorrow Or Later")
  var showingTomorrowOrLater: Bool

  init() {
    self.showingTomorrowOrLater = false
  }

  init(showingTomorrowOrLater: Bool) {
    self.showingTomorrowOrLater = showingTomorrowOrLater
  }

  func perform() async throws -> some IntentResult {
    WidgetPreferenceStore.configured()?.toggleScheduleDayMode(
      currentlyShowingTomorrowOrLater: showingTomorrowOrLater,
      at: Date()
    )
    WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    return .result()
  }
}

#if os(iOS) && compiler(>=6.0)
@available(iOS 18.0, *)
struct OpenEcardPayCodeControlIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Pay Code"
  static var description = IntentDescription("Open campus card Pay Code in TechPie.")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(TechPieWidgetURL.ecardPay()))
  }
}
#endif
#endif
