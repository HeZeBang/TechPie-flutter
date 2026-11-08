import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  let deadlineWidgetBridge = DeadlineWidgetBridge()

  override func application(_ application: NSApplication, open urls: [URL]) {
    if urls.contains(where: { deadlineWidgetBridge.capture($0) }) {
      application.activate(ignoringOtherApps: true)
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
