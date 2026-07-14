import Flutter
import UIKit
import UniformTypeIdentifiers

/// iOS side of the config-import bridge. Mirrors the Android `osmi.awg2/import`
/// channel:
///
///   getInitial -> String?              (payload the app was launched with)
///   pickFile   -> {name, text}         (document picker)
///   onImport   (host -> Dart, String)  (payload delivered while running)
///
/// Payload is either a `vpn://` link string or the UTF-8 text of a `.vpn` file,
/// exactly what the Dart parser expects.
public class OsmiraImportPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  static let shared = OsmiraImportPlugin()

  private var channel: FlutterMethodChannel?
  private var pendingInitial: String?
  private var pickResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(name: "osmi.awg2/import", binaryMessenger: registrar.messenger())
    shared.channel = ch
    registrar.addMethodCallDelegate(shared, channel: ch)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitial":
      let payload = pendingInitial
      pendingInitial = nil
      result(payload)
    case "pickFile":
      pickFile(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Called by AppDelegate when the OS opens the app with a `.vpn` file or a
  /// `vpn://` link. Queues the payload until Flutter asks for it, or forwards it
  /// live if the engine is already running.
  func handleIncoming(url: URL) {
    guard let text = Self.readPayload(from: url) else { return }
    if let channel = channel {
      channel.invokeMethod("onImport", arguments: text)
    } else {
      pendingInitial = text
    }
  }

  /// Stores a cold-launch payload so Dart can retrieve it via `getInitial`.
  func queueInitial(url: URL) {
    if let text = Self.readPayload(from: url) { pendingInitial = text }
  }

  static func readPayload(from url: URL) -> String? {
    if url.scheme == "vpn" { return url.absoluteString }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  // MARK: - Document picker

  private func pickFile(_ result: @escaping FlutterResult) {
    guard let root = Self.topViewController() else { result(nil); return }
    pickResult = result

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      let vpnType = UTType(filenameExtension: "vpn") ?? .data
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [vpnType, .data, .text])
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.text"], in: .import)
    }
    picker.allowsMultipleSelection = false
    picker.delegate = self
    root.present(picker, animated: true)
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    defer { pickResult = nil }
    guard let url = urls.first, let text = Self.readPayload(from: url), !text.isEmpty else {
      pickResult?(nil)
      return
    }
    pickResult?(["name": url.lastPathComponent, "text": text])
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickResult?(nil)
    pickResult = nil
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
