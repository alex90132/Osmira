import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // If the app was cold-launched by opening a .vpn file / vpn:// link, stash it
    // so Dart can pull it via `getInitial`.
    if let url = launchOptions?[.url] as? URL {
      OsmiraImportPlugin.shared.queueInitial(url: url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // .vpn file or vpn:// link delivered while the app is already running.
    OsmiraImportPlugin.shared.handleIncoming(url: url)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Hand-written bridges (not pub plugins) are registered manually.
    if let vpn = engineBridge.pluginRegistry.registrar(forPlugin: "OsmiraVpnPlugin") {
      OsmiraVpnPlugin.register(with: vpn)
    }
    if let importReg = engineBridge.pluginRegistry.registrar(forPlugin: "OsmiraImportPlugin") {
      OsmiraImportPlugin.register(with: importReg)
    }
  }
}
