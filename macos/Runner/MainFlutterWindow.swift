import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let deadlineReminderBridge = DeadlineReminderBridge()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApp.delegate as? AppDelegate)?.deadlineWidgetBridge.configure(messenger: flutterViewController.engine.binaryMessenger)
    deadlineReminderBridge.configure(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
