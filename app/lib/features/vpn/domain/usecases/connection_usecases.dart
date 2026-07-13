import '../entities/app_routing.dart';
import '../entities/vpn_status.dart';
import '../entities/vpn_tunnel.dart';
import '../repositories/vpn_connection_repository.dart';

/// Bring a tunnel up, requesting OS VPN consent first if needed.
class ConnectTunnel {
  const ConnectTunnel(this._repo);
  final VpnConnectionRepository _repo;

  Future<void> call(
    VpnTunnel tunnel, {
    int? mtuOverride,
    AppRouting routing = const AppRouting(),
  }) async {
    final ok = await _repo.prepare();
    if (!ok) return; // user declined the VPN consent dialog
    await _repo.connect(tunnel, mtuOverride: mtuOverride, routing: routing);
  }
}

class DisconnectTunnel {
  const DisconnectTunnel(this._repo);
  final VpnConnectionRepository _repo;

  Future<void> call() => _repo.disconnect();
}

class WatchVpnStatus {
  const WatchVpnStatus(this._repo);
  final VpnConnectionRepository _repo;

  Stream<VpnStatus> call() => _repo.watchStatus();
}
