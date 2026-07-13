import '../entities/app_routing.dart';
import '../entities/vpn_status.dart';
import '../entities/vpn_tunnel.dart';

/// Drives the native VPN backend: brings tunnels up/down and exposes a live
/// status stream. The reconnect-on-stall and background lifecycle logic lives
/// natively; this is the domain-facing contract.
abstract interface class VpnConnectionRepository {
  /// Hot stream of the current [VpnStatus] (state + counters).
  Stream<VpnStatus> watchStatus();

  Future<VpnStatus> currentStatus();

  /// Ensures the OS VPN consent has been granted, prompting if needed.
  /// Returns true if permission is available.
  Future<bool> prepare();

  /// Brings [tunnel] up (requesting VPN permission if necessary).
  ///
  /// [mtuOverride] forces the TUN MTU (used by the stealth "normalize MTU to
  /// 1500" option to mask the WireGuard MSS/MTU-reduction fingerprint).
  /// [routing] is the global split-tunnel policy to apply.
  Future<void> connect(
    VpnTunnel tunnel, {
    int? mtuOverride,
    AppRouting routing = const AppRouting(),
  });

  Future<void> disconnect();
}
