import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications shows notifications in the foreground and reports taps
    // through the app delegate.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The app icon's badge: the notifying total, set by the Dart side.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OxiTalkBadge") {
      let badge = FlutterMethodChannel(
        name: "io.oxisoft.oxitalk/badge", binaryMessenger: registrar.messenger())
      badge.setMethodCallHandler { call, result in
        guard call.method == "setBadge", let count = call.arguments as? Int else {
          result(FlutterMethodNotImplemented)
          return
        }
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        result(nil)
      }
    }
    // What the Share Extension left in the App Group, for "Send to…": Dart asks on start and
    // whenever the app comes back to the front (the extension opens it with oxitalk-share://).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OxiTalkShare") {
      let share = FlutterMethodChannel(
        name: "io.oxisoft.oxitalk/share", binaryMessenger: registrar.messenger())
      share.setMethodCallHandler { call, result in
        guard call.method == "takeShared" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(SharedInbox.take())
      }
    }
  }
}

/// The Share Extension's hand-off: `ShareInbox/<id>/` in the App Group's container, with the
/// files and a `manifest.json` (`{"files": [names], "text": "..."}`) written last.
enum SharedInbox {
  static let appGroup = "group.io.oxisoft.oxitalk"

  /// Moves every complete share into the app's temporary folder and returns its paths and
  /// text (`nil` for none); a share left without a manifest for an hour is dropped.
  static func take() -> [String: Any]? {
    let files = FileManager.default
    guard
      let inbox = files.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
        .appendingPathComponent("ShareInbox", isDirectory: true),
      let shares = try? files.contentsOfDirectory(
        at: inbox, includingPropertiesForKeys: [.creationDateKey])
    else { return nil }
    let ordered = shares.sorted {
      let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
      let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
      return a < b
    }
    var paths: [String] = []
    var texts: [String] = []
    let target = files.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
    for share in ordered {
      let manifestURL = share.appendingPathComponent("manifest.json")
      guard let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        let created =
          (try? share.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        if created < Date(timeIntervalSinceNow: -3600) { try? files.removeItem(at: share) }
        continue
      }
      let dir = target.appendingPathComponent(share.lastPathComponent, isDirectory: true)
      try? files.createDirectory(at: dir, withIntermediateDirectories: true)
      for name in manifest["files"] as? [String] ?? [] {
        let from = share.appendingPathComponent(name)
        let to = dir.appendingPathComponent(name)
        try? files.removeItem(at: to)
        if (try? files.moveItem(at: from, to: to)) != nil { paths.append(to.path) }
      }
      if let text = manifest["text"] as? String, !text.isEmpty { texts.append(text) }
      try? files.removeItem(at: share)
    }
    if paths.isEmpty && texts.isEmpty { return nil }
    return ["paths": paths, "text": texts.joined(separator: "\n")]
  }
}
