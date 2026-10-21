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
  }
}
