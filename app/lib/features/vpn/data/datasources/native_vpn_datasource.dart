import 'package:flutter/services.dart';

import '../../../../core/failure.dart';
import '../../domain/entities/installed_app.dart';
import '../../domain/entities/vpn_status.dart';

/// Thin wrapper over the platform channels that talk to the native AWG VPN
/// service. All AmneziaWG runtime concerns (TUN setup, reconnect-on-stall,
/// foreground lifecycle) live natively; this just marshals commands and
/// decodes the status stream.
class NativeVpnDataSource {
  NativeVpnDataSource({
    MethodChannel? methodChannel,
    EventChannel? statusChannel,
  })  : _method = methodChannel ?? const MethodChannel(_methodName),
        _status = statusChannel ?? const EventChannel(_statusName);

  static const _methodName = 'osmi.awg2/vpn';
  static const _statusName = 'osmi.awg2/vpn_status';

  final MethodChannel _method;
  final EventChannel _status;

  Stream<VpnStatus>? _statusStream;

  /// Broadcast stream of status snapshots pushed by the service. Errors from
  /// the platform (e.g. no native backend on desktop yet) are swallowed so the
  /// UI just falls back to "disconnected".
  Stream<VpnStatus> statusStream() {
    return _statusStream ??= _status
        .receiveBroadcastStream()
        .map((e) => _mapStatus((e as Map).cast<String, dynamic>()))
        .handleError((_) {})
        .asBroadcastStream();
  }

  Future<VpnStatus> currentStatus() async {
    try {
      final res = await _method.invokeMapMethod<String, dynamic>('status');
      if (res == null) return VpnStatus.disconnected;
      return _mapStatus(res);
    } on MissingPluginException {
      return VpnStatus.disconnected;
    } on PlatformException {
      return VpnStatus.disconnected;
    }
  }

  /// Requests OS VPN consent if needed. Returns true when authorized.
  Future<bool> prepare() async {
    try {
      final ok = await _method.invokeMethod<bool>('prepare');
      return ok ?? false;
    } on MissingPluginException {
      throw const VpnBackendFailure(
        'VPN-бэкенд недоступен на этой платформе (пока)',
      );
    } on PlatformException catch (e) {
      throw VpnBackendFailure('Failed to prepare VPN', e);
    }
  }

  Future<void> connect(Map<String, dynamic> payload) async {
    try {
      await _method.invokeMethod<void>('connect', payload);
    } on MissingPluginException {
      throw const VpnBackendFailure(
        'VPN-бэкенд недоступен на этой платформе (пока)',
      );
    } on PlatformException catch (e) {
      throw VpnBackendFailure(e.message ?? 'Failed to start VPN', e);
    }
  }

  Future<void> disconnect() async {
    try {
      await _method.invokeMethod<void>('disconnect');
    } on MissingPluginException {
      // Nothing to stop if there's no backend.
    } on PlatformException catch (e) {
      throw VpnBackendFailure(e.message ?? 'Failed to stop VPN', e);
    }
  }

  Future<List<InstalledApp>> listApps({bool includeSystem = false}) async {
    final List<dynamic>? res;
    try {
      res = await _method.invokeListMethod<dynamic>(
        'listApps',
        {'includeSystem': includeSystem},
      );
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
    if (res == null) return const [];
    return res
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .map(
          (m) => InstalledApp(
            packageName: m['package'] as String? ?? '',
            label: m['label'] as String? ?? '',
            isSystem: m['system'] as bool? ?? false,
            icon: m['icon'] is Uint8List ? m['icon'] as Uint8List : null,
          ),
        )
        .where((a) => a.packageName.isNotEmpty)
        .toList(growable: false);
  }

  static VpnStatus _mapStatus(Map<String, dynamic> m) {
    return VpnStatus(
      state: _parseState(m['state'] as String?),
      tunnelId: m['id'] as String?,
      errorMessage: (m['error'] as String?)?.isNotEmpty == true
          ? m['error'] as String?
          : null,
      rxBytes: _asInt(m['rxBytes']),
      txBytes: _asInt(m['txBytes']),
      lastHandshakeEpochSeconds: _asInt(m['lastHandshake']),
    );
  }

  static int _asInt(dynamic v) =>
      v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);

  static VpnConnectionState _parseState(String? s) => switch (s) {
        'connecting' => VpnConnectionState.connecting,
        'connected' => VpnConnectionState.connected,
        'reconnecting' => VpnConnectionState.reconnecting,
        'error' => VpnConnectionState.error,
        _ => VpnConnectionState.disconnected,
      };
}
