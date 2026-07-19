import '../entities/vpn_tunnel.dart';

/// Persists and retrieves saved [VpnTunnel]s and imports new ones from raw
/// config text. Implementations live in the data layer; the domain only
/// depends on this contract.
abstract interface class TunnelRepository {
  /// Emits the current list of saved tunnels and every subsequent change.
  Stream<List<VpnTunnel>> watchTunnels();

  Future<List<VpnTunnel>> getTunnels();

  /// Parses [source] (`vpn://...` or wg-quick text) into a tunnel *without*
  /// saving it. Throws a [Failure] on invalid input.
  Future<VpnTunnel> parse(String source, {String? name});

  Future<void> save(VpnTunnel tunnel);

  Future<void> delete(String id);

  /// Moves the tunnel with [id] to the top of the list so the most recently
  /// connected profile is always first. No-op if it's missing or already first.
  Future<void> markConnected(String id);
}
