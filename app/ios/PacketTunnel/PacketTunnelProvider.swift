import NetworkExtension
import os.log

/// AmneziaWG packet tunnel. Runs in a separate process (the Network Extension).
///
/// It receives the connect payload from the host app via
/// `protocolConfiguration.providerConfiguration`, builds the TUN network
/// settings, and hands the same UAPI string the Dart layer already produces
/// (private_key + jc/jmin/jmax/s1..s4/h1..h4/i1..i5 + peers) straight to the
/// AmneziaWG-Go backend via `wgTurnOn`. This is the 1:1 counterpart of the
/// Android `GoBackend.awgTurnOn(name, tunFd, uapi)` call.
class PacketTunnelProvider: NEPacketTunnelProvider {
  private var handle: Int32 = -1
  private let log = OSLog(subsystem: "osmi.awg2.PacketTunnel", category: "tunnel")

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard
      let proto = protocolConfiguration as? NETunnelProviderProtocol,
      let conf = proto.providerConfiguration,
      let uapi = conf["uapi"] as? String, !uapi.isEmpty
    else {
      completionHandler(err(1, "missing providerConfiguration/uapi"))
      return
    }

    let mtu = conf["mtu"] as? Int ?? 1280
    let addresses = conf["addresses"] as? [String] ?? []
    let dns = conf["dns"] as? [String] ?? []
    let routes = conf["routes"] as? [String] ?? []

    let settings = makeNetworkSettings(
      remote: proto.serverAddress ?? "127.0.0.1",
      addresses: addresses,
      dns: dns,
      routes: routes,
      mtu: mtu
    )

    setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self = self else { return }
      if let error = error { completionHandler(error); return }
      guard let fd = self.tunnelFileDescriptor else {
        completionHandler(self.err(2, "could not locate the utun fd"))
        return
      }
      let h = wgTurnOn(uapi, fd)
      if h < 0 {
        completionHandler(self.err(Int(h), "wgTurnOn failed (\(h))"))
        return
      }
      self.handle = h
      os_log("tunnel up, handle=%d", log: self.log, type: .info, h)
      completionHandler(nil)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    if handle >= 0 {
      wgTurnOff(handle)
      handle = -1
    }
    completionHandler()
  }

  /// Answers the host app's "stats" probe with rx/tx/handshake pulled from the
  /// Go backend's UAPI dump.
  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    guard
      String(data: messageData, encoding: .utf8) == "stats",
      handle >= 0,
      let cfgPtr = wgGetConfig(handle)
    else {
      completionHandler?(nil)
      return
    }
    let dump = String(cString: cfgPtr)
    free(cfgPtr)
    let stats = parseStats(dump)
    completionHandler?(try? JSONSerialization.data(withJSONObject: stats))
  }

  // MARK: - Network settings

  private func makeNetworkSettings(
    remote: String,
    addresses: [String],
    dns: [String],
    routes: [String],
    mtu: Int
  ) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remote)

    var v4addr: [String] = [], v4mask: [String] = []
    var v6addr: [String] = [], v6prefix: [NSNumber] = []
    for cidr in addresses {
      let (ip, prefix) = splitCidr(cidr)
      if ip.contains(":") {
        v6addr.append(ip); v6prefix.append(NSNumber(value: prefix))
      } else {
        v4addr.append(ip); v4mask.append(ipv4Mask(prefix))
      }
    }

    var v4routes: [NEIPv4Route] = []
    var v6routes: [NEIPv6Route] = []
    for cidr in routes {
      let (ip, prefix) = splitCidr(cidr)
      if ip.contains(":") {
        v6routes.append(NEIPv6Route(destinationAddress: ip, networkPrefixLength: NSNumber(value: prefix)))
      } else {
        v4routes.append(NEIPv4Route(destinationAddress: ip, subnetMask: ipv4Mask(prefix)))
      }
    }

    if !v4addr.isEmpty {
      let v4 = NEIPv4Settings(addresses: v4addr, subnetMasks: v4mask)
      v4.includedRoutes = v4routes.isEmpty ? [NEIPv4Route.default()] : v4routes
      settings.ipv4Settings = v4
    }
    if !v6addr.isEmpty {
      let v6 = NEIPv6Settings(addresses: v6addr, networkPrefixLengths: v6prefix)
      v6.includedRoutes = v6routes.isEmpty ? [NEIPv6Route.default()] : v6routes
      settings.ipv6Settings = v6
    }
    if !dns.isEmpty {
      settings.dnsSettings = NEDNSSettings(servers: dns)
    }
    settings.mtu = NSNumber(value: mtu)
    return settings
  }

  // MARK: - Helpers

  private func err(_ code: Int, _ message: String) -> NSError {
    os_log("%{public}s", log: log, type: .error, message)
    return NSError(domain: "osmi.awg2.PacketTunnel", code: code,
                   userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func splitCidr(_ cidr: String) -> (String, Int) {
    let parts = cidr.split(separator: "/", maxSplits: 1)
    let ip = String(parts.first ?? "")
    let prefix = parts.count > 1 ? Int(parts[1]) ?? (ip.contains(":") ? 128 : 32)
                                 : (ip.contains(":") ? 128 : 32)
    return (ip, prefix)
  }

  private func ipv4Mask(_ prefix: Int) -> String {
    let p = max(0, min(32, prefix))
    let mask = p == 0 ? 0 : (0xFFFF_FFFF << (32 - p)) & 0xFFFF_FFFF
    return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
  }

  /// Parses a wireguard-go UAPI dump: sums rx/tx across peers, takes the newest
  /// handshake timestamp.
  private func parseStats(_ dump: String) -> [String: Any] {
    var rx: Int64 = 0, tx: Int64 = 0, handshake: Int64 = 0
    for line in dump.split(separator: "\n") {
      let kv = line.split(separator: "=", maxSplits: 1)
      guard kv.count == 2 else { continue }
      let value = String(kv[1])
      switch kv[0] {
      case "rx_bytes": rx += Int64(value) ?? 0
      case "tx_bytes": tx += Int64(value) ?? 0
      case "last_handshake_time_sec": handshake = max(handshake, Int64(value) ?? 0)
      default: break
      }
    }
    return ["rxBytes": rx, "txBytes": tx, "lastHandshake": handshake]
  }

  /// Locates the utun file descriptor the system handed this extension.
  /// Standard wireguard-apple technique: scan fds for the utun control socket.
  private var tunnelFileDescriptor: Int32? {
    var ctlInfo = ctl_info()
    withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
      $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
        _ = strcpy($0, "com.apple.net.utun_control")
      }
    }
    for fd: Int32 in 0...1024 {
      var addr = sockaddr_ctl()
      var len = socklen_t(MemoryLayout.size(ofValue: addr))
      let ret = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          getpeername(fd, $0, &len)
        }
      }
      if ret != 0 || addr.sc_family != AF_SYSTEM { continue }
      if ctlInfo.ctl_id == 0 {
        if ioctl(fd, CTLIOCGINFO, &ctlInfo) != 0 { continue }
      }
      if addr.sc_id == ctlInfo.ctl_id { return fd }
    }
    return nil
  }
}
