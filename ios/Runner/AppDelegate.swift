import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let displayChannel = FlutterMethodChannel(
        name: "ogvibes/sos_display",
        binaryMessenger: controller.binaryMessenger
      )
      var savedBrightness: CGFloat?
      displayChannel.setMethodCallHandler { call, result in
        guard call.method == "setStealthMode",
              let arguments = call.arguments as? [String: Any],
              let enabled = arguments["enabled"] as? Bool else {
          result(FlutterMethodNotImplemented)
          return
        }
        if enabled {
          if savedBrightness == nil {
            savedBrightness = UIScreen.main.brightness
          }
          UIScreen.main.brightness = 0.04
        } else {
          if let savedBrightness {
            UIScreen.main.brightness = savedBrightness
          }
          savedBrightness = nil
        }
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
