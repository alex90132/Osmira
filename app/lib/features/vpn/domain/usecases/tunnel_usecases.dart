import '../entities/vpn_tunnel.dart';
import '../repositories/tunnel_repository.dart';

/// Parse raw config text into a tunnel and persist it.
class ImportTunnel {
  const ImportTunnel(this._repo);
  final TunnelRepository _repo;

  Future<VpnTunnel> call(String source, {String? name}) async {
    final tunnel = await _repo.parse(source, name: name);
    await _repo.save(tunnel);
    return tunnel;
  }
}

/// Parse without saving (used for preview/validation before import).
class ParseTunnel {
  const ParseTunnel(this._repo);
  final TunnelRepository _repo;

  Future<VpnTunnel> call(String source, {String? name}) =>
      _repo.parse(source, name: name);
}

class WatchTunnels {
  const WatchTunnels(this._repo);
  final TunnelRepository _repo;

  Stream<List<VpnTunnel>> call() => _repo.watchTunnels();
}

class DeleteTunnel {
  const DeleteTunnel(this._repo);
  final TunnelRepository _repo;

  Future<void> call(String id) => _repo.delete(id);
}

/// Update a tunnel's display name.
class UpdateTunnel {
  const UpdateTunnel(this._repo);
  final TunnelRepository _repo;

  Future<VpnTunnel> call(VpnTunnel tunnel, {String? name}) {
    final updated = tunnel.copyWith(name: name);
    return _repo.save(updated).then((_) => updated);
  }
}
