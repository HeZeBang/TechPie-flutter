import AppIntents
import UIKit

@available(iOS 16.0, *)
struct OpenEcardPayCodeIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Pay Code"
  static var description = IntentDescription("Open the campus card payment code in TechPie.")
  static var openAppWhenRun: Bool = true

  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let app = UIApplication.shared.delegate as? AppDelegate else {
      throw NSError(
        domain: "TechPieShortcuts", code: 1,
        userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to open Pay Code. Open TechPie and try again.")]
      )
    }
    // The existing bridge retains this request until Flutter is ready.
    app.openEcardPayCode()
    return .result()
  }
}

@available(iOS 16.0, *)
struct EcardAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenEcardPayCodeIntent(),
      phrases: [
        "Open Pay Code in \(.applicationName)",
        "Show my Pay Code in \(.applicationName)",
      ],
      shortTitle: "Pay Code",
      systemImageName: "qrcode"
    )
  }

  static var shortcutTileColor: ShortcutTileColor { .red }
}
