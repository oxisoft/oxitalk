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

    // Files opened with OxiTalk (Finder's Open With, dropped on the Dock icon), for
    // "Send to…": kept until Dart takes them; sharedArrived tells it they came.
    let share = FlutterMethodChannel(
      name: "io.oxisoft.oxitalk/share",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    openedFiles.channel = share
    share.setMethodCallHandler { [openedFiles] call, result in
      guard call.method == "takeShared" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(openedFiles.take())
    }
    flutterViewController.registrar(forPlugin: "OxiTalkShare")
      .addApplicationDelegate(openedFiles)

    super.awakeFromNib()
  }

  /// Kept here: the registrar holds its application delegates weakly.
  private let openedFiles = OpenedFiles()
}

/// Receives the files macOS opens with the app (FlutterAppDelegate hands
/// application(_:open:) to its plugins' application delegates).
final class OpenedFiles: NSObject, FlutterAppLifecycleDelegate {
  var channel: FlutterMethodChannel?
  private var paths: [String] = []

  @objc(handleOpenURLs:)
  func handleOpen(_ urls: [URL]) -> Bool {
    let files = urls.filter(\.isFileURL).map(\.path)
    if files.isEmpty { return false }
    for path in files where !paths.contains(path) { paths.append(path) }
    channel?.invokeMethod("sharedArrived", arguments: nil)
    return true
  }

  func take() -> [String: Any]? {
    if paths.isEmpty { return nil }
    defer { paths.removeAll() }
    return ["paths": paths, "text": ""]
  }
}
