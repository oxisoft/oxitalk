import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The dock icon's badge: the notifying total, set by the Dart side.
    let badge = FlutterMethodChannel(
      name: "io.oxisoft.oxitalk/badge",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    badge.setMethodCallHandler { call, result in
      guard call.method == "setBadge", let count = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
      result(nil)
    }

    super.awakeFromNib()
  }
}
