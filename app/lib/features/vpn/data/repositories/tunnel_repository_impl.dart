import 'dart:async';
import 'dart:math';

import '../../domain/entities/vpn_tunnel.dart';
import '../../domain/repositories/tunnel_repository.dart';
import '../datasources/tunnel_store.dart';
import '../parser/amnezia_config_parser.dart';

/// [TunnelRepository] backed by [TunnelStore] (persistence) and
/// [AmneziaConfigParser] (import). Parsed configs are reconstructed from the
/// saved source text so storage stays a single source of truth.
class TunnelRepositoryImpl implements TunnelRepository {
  TunnelRepositoryImpl({
    required TunnelStore store,
    AmneziaConfigParser parser = const AmneziaConfigParser(),
  })  : _store = store,
        _parser = parser;

  final TunnelStore _store;
  final AmneziaConfigParser _parser;
  final _controller = StreamController<List<VpnTunnel>>.broadcast();
  final _rng = Random.secure();

  @override
  Stream<List<VpnTunnel>> watchTunnels() {
    // Prime new listeners with the current value.
    scheduleMicrotask(() async => _controller.add(await getTunnels()));
    return _controller.stream;
  }

  @override
  Future<List<VpnTunnel>> getTunnels() async {
    final records = await _store.read();
    final tunnels = <VpnTunnel>[];
    for (final r in records) {
      try {
        tunnels.add(_fromRecord(r));
      } catch (_) {
        // Drop unparseable records rather than blocking the whole list.
      }
    }
    return tunnels;
  }

  @override
  Future<VpnTunnel> parse(String source, {String? name}) async {
    final parsed = _parser.parse(source);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (parsed.name?.isNotEmpty == true ? parsed.name! : 'AWG tunnel');
    return VpnTunnel(
      id: _newId(),
      name: resolvedName,
      config: parsed.config,
      source: source.trim(),
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> save(VpnTunnel tunnel) async {
    final records = await _store.read();
    final record = _toRecord(tunnel);
    final idx = records.indexWhere((r) => r.id == tunnel.id);
    if (idx >= 0) {
      records[idx] = record;
    } else {
      records.add(record);
    }
    await _store.write(records);
    _controller.add(await getTunnels());
  }

  @override
  Future<void> delete(String id) async {
    final records = (await _store.read())..removeWhere((r) => r.id == id);
    await _store.write(records);
    _controller.add(await getTunnels());
  }

  @override
  Future<void> markConnected(String id) async {
    final records = await _store.read();
    final idx = records.indexWhere((r) => r.id == id);
    if (idx <= 0) return; // missing, or already at the top
    records.insert(0, records.removeAt(idx));
    await _store.write(records);
    _controller.add(await getTunnels());
  }

  void dispose() => _controller.close();

  VpnTunnel _fromRecord(TunnelRecord r) {
    final parsed = _parser.parse(r.source);
    return VpnTunnel(
      id: r.id,
      name: r.name,
      config: parsed.config,
      source: r.source,
      createdAt: DateTime.tryParse(r.createdAt) ?? DateTime.now(),
    );
  }

  TunnelRecord _toRecord(VpnTunnel t) => TunnelRecord(
        id: t.id,
        name: t.name,
        source: t.source,
        createdAt: t.createdAt.toIso8601String(),
      );

  String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rnd = _rng.nextInt(1 << 32).toRadixString(16);
    return '$ts-$rnd';
  }
}
