import '../../../../core/log.dart';
import '../../domain/entities/app_routing.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/vpn_tunnel.dart';
import '../../domain/repositories/vpn_connection_repository.dart';
import '../datasources/native_vpn_datasource.dart';
import '../parser/uapi_serializer.dart';

/// [VpnConnectionRepository] that maps a [VpnTunnel] into the native connect
/// payload (uapi string + TUN parameters + split-tunnel routing) and forwards
/// lifecycle commands to [NativeVpnDataSource].
class VpnConnectionRepositoryImpl implements VpnConnectionRepository {
  VpnConnectionRepositoryImpl({
    required NativeVpnDataSource native,
    UapiSerializer serializer = const UapiSerializer(),
  })  : _native = native,
        _serializer = serializer;

  final NativeVpnDataSource _native;
  final UapiSerializer _serializer;

  @override
  Stream<VpnStatus> watchStatus() => _native.statusStream();

  @override
  Future<VpnStatus> currentStatus() => _native.currentStatus();

  @override
  Future<bool> prepare() => _native.prepare();

  @override
  Future<void> connect(
    VpnTunnel tunnel, {
    int? mtuOverride,
    AppRouting routing = const AppRouting(),
  }) =>
      _native.connect(
        _buildPayload(tunnel, mtuOverride: mtuOverride, routing: routing),
      );

  @override
  Future<void> disconnect() => _native.disconnect();

  Map<String, dynamic> _buildPayload(
    VpnTunnel tunnel, {
    int? mtuOverride,
    required AppRouting routing,
  }) {
    final cfg = tunnel.config;
    final peer = cfg.peers.isNotEmpty ? cfg.peers.first : null;
    final routes = <String>{
      for (final p in cfg.peers) ...p.allowedIps,
    }.toList(growable: false);
    final mtu = mtuOverride ?? cfg.interface.mtu ?? 1280;

    // Never log the uapi string — it contains the WireGuard private key.
    AppLog.lazy(
      'Payload',
      () => 'mtu=$mtu dns=${cfg.interface.dnsServers} '
          'routes=${routes.length} peers=${cfg.peers.length} '
          'endpoint=${peer?.endpoint?.host}:${peer?.endpoint?.port} '
          'awg2=${cfg.interface.parameters.isV2} '
          'awg3=${cfg.interface.parameters.isV3}',
    );

    return {
      'id': tunnel.id,
      'name': tunnel.name,
      'uapi': _serializer.serialize(cfg),
      'mtu': mtu,
      'addresses': cfg.interface.addresses,
      'dns': cfg.interface.dnsServers,
      'searchDomains': cfg.interface.dnsSearchDomains,
      'routes': routes,
      'routingMode': routing.mode.name,
      'apps': routing.mode == AppRoutingMode.all
          ? const <String>[]
          : routing.packages.toList(growable: false),
      'endpointHost': peer?.endpoint?.host,
      'endpointPort': peer?.endpoint?.port,
    };
  }
}
