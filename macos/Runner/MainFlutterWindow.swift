import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let deadlineReminderBridge = DeadlineReminderBridge()
  private var windowChromeChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = false
    self.minSize = NSSize(width: 520, height: 600)

    let chromeChannel = FlutterMethodChannel(
      name: "techpie/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    chromeChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "toggleZoom":
        self.performZoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.windowChromeChannel = chromeChannel

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let appDelegate = NSApp.delegate as? AppDelegate {
      let messenger = flutterViewController.engine.binaryMessenger
      appDelegate.deadlineWidgetBridge.configure(messenger: messenger)
      appDelegate.homeWidgetsBridge.configure(messenger: messenger)
      appDelegate.configureEcardDeepLink(messenger: messenger)
    }
    deadlineReminderBridge.configure(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
