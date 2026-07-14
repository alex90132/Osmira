import Flutter
import Foundation
import NetworkExtension

/// Host-app side of the VPN bridge. Mirrors the exact platform-channel contract
/// the Dart layer already uses on Android:
///
///   MethodChannel  "osmi.awg2/vpn"         -> prepare / connect / disconnect / status / listApps
///   EventChannel   "osmi.awg2/vpn_status"  -> {state,id,rxBytes,txBytes,lastHandshake,error}
///
/// The actual tunnelling runs in the PacketTunnel network extension; this class
/// only creates/loads the NETunnelProviderManager, ships the connect payload to
/// the extension via `providerConfiguration`, and relays status + stats back to
/// Flutter.
public class OsmiraVpnPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  // Must match the extension target's bundle id and the App Group.
  private static let tunnelBundleId = "osmi.awg2.PacketTunnel"

  private var manager: NETunnelProviderManager?
  private var eventSink: FlutterEventSink?
  private var lastId: String?
  private var statsTimer: Timer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OsmiraVpnPlugin()
    let method = FlutterMethodChannel(name: "osmi.awg2/vpn", binaryMessenger: registrar.messenger())
    let status = FlutterEventChannel(name: "osmi.awg2/vpn_status", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: method)
    status.setStreamHandler(instance)

    NotificationCenter.default.addObserver(
      instance,
      selector: #selector(vpnStatusChanged(_:)),
      name: .NEVPNStatusDidChange,
      object: nil
    )
  }

  // MARK: - MethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepare":
      loadManager { _ in result(true) }
    case "connect":
      guard let payload = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "connect payload missing", details: nil))
        return
      }
      connect(payload, result: result)
    case "disconnect":
      disconnect(result: result)
    case "status":
      result(currentStatusMap())
    case "listApps":
      // iOS has no per-app VPN for consumer apps; the routing screen is Android-only.
      result([])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Connect / disconnect

  private func connect(_ payload: [String: Any], result: @escaping FlutterResult) {
    lastId = payload["id"] as? String
    loadManager { manager in
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = Self.tunnelBundleId
      proto.serverAddress = (payload["endpointHost"] as? String) ?? "AmneziaWG"

      // Only plist-safe values cross into the extension.
      var providerConfig: [String: Any] = [:]
      providerConfig["uapi"] = payload["uapi"] as? String ?? ""
      providerConfig["mtu"] = payload["mtu"] as? Int ?? 1280
      providerConfig["addresses"] = payload["addresses"] as? [String] ?? []
      providerConfig["dns"] = payload["dns"] as? [String] ?? []
      providerConfig["searchDomains"] = payload["searchDomains"] as? [String] ?? []
      providerConfig["routes"] = payload["routes"] as? [String] ?? []
      proto.providerConfiguration = providerConfig

      manager.protocolConfiguration = proto
      manager.localizedDescription = (payload["name"] as? String) ?? "Osmira"
      manager.isEnabled = true

      manager.saveToPreferences { saveErr in
        if let saveErr = saveErr {
          result(FlutterError(code: "save_failed", message: saveErr.localizedDescription, details: nil))
          return
        }
        // iOS quirk: reload after saving before the session is usable.
        manager.loadFromPreferences { _ in
          do {
            try manager.connection.startVPNTunnel()
            result(nil)
          } catch {
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func disconnect(result: @escaping FlutterResult) {
    manager?.connection.stopVPNTunnel()
    result(nil)
  }

  // MARK: - Manager lifecycle

  private func loadManager(_ completion: @escaping (NETunnelProviderManager) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
      let mgr = managers?.first ?? NETunnelProviderManager()
      self?.manager = mgr
      completion(mgr)
    }
  }

  // MARK: - Status + stats

  @objc private func vpnStatusChanged(_ note: Notification) {
    emitStatus()
    let status = manager?.connection.status ?? .invalid
    if status == .connected {
      startStatsPolling()
    } else {
      stopStatsPolling()
    }
  }

  private func startStatsPolling() {
    guard statsTimer == nil else { return }
    statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      self?.emitStatus()
    }
  }

  private func stopStatsPolling() {
    statsTimer?.invalidate()
    statsTimer = nil
  }

  private func mappedState() -> String {
    switch manager?.connection.status ?? .invalid {
    case .connecting: return "connecting"
    case .connected: return "connected"
    case .reasserting: return "reconnecting"
    case .disconnecting, .disconnected, .invalid: return "disconnected"
    @unknown default: return "disconnected"
    }
  }

  private func currentStatusMap() -> [String: Any] {
    return [
      "state": mappedState(),
      "id": lastId as Any,
      "rxBytes": 0,
      "txBytes": 0,
      "lastHandshake": 0,
    ]
  }

  /// Emits the current state immediately, then asks the extension for live
  /// rx/tx/handshake counters and emits an enriched snapshot when they arrive.
  private func emitStatus() {
    guard let sink = eventSink else { return }
    let state = mappedState()
    sink([
      "state": state,
      "id": lastId as Any,
      "rxBytes": 0,
      "txBytes": 0,
      "lastHandshake": 0,
    ])

    guard state == "connected",
          let session = manager?.connection as? NETunnelProviderSession,
          let req = "stats".data(using: .utf8) else { return }
    try? session.sendProviderMessage(req) { [weak self] resp in
      guard let self = self, let sink = self.eventSink,
            let resp = resp,
            let obj = try? JSONSerialization.jsonObject(with: resp) as? [String: Any] else { return }
      sink([
        "state": "connected",
        "id": self.lastId as Any,
        "rxBytes": obj["rxBytes"] ?? 0,
        "txBytes": obj["txBytes"] ?? 0,
        "lastHandshake": obj["lastHandshake"] ?? 0,
      ])
    }
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    loadManager { [weak self] _ in self?.emitStatus() }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stopStatsPolling()
    return nil
  }
}
