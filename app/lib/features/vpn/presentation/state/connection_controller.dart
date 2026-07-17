import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../../../../core/log.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/vpn_tunnel.dart';
import 'vpn_providers.dart';

/// Drives connect/disconnect actions. The [state] is only the *action*
/// progress (busy / failed); the authoritative tunnel state comes from
/// [vpnStatusProvider] streamed by native.
class ConnectionController extends Notifier<AsyncValue<void>> {
  Timer? _watchdog;

  /// Platform-agnostic safety net: if a connect doesn't reach `connected`
  /// within this window, we tear it down and report an error instead of letting
  /// the UI spin forever. The native Android backend also enforces its own
  /// (shorter) timeout; this backs it up and covers other platforms.
  static const _connectTimeout = Duration(seconds: 30);

  @override
  AsyncValue<void> build() {
    ref.onDispose(() => _watchdog?.cancel());
    return const AsyncData(null);
  }

  Future<void> connect(VpnTunnel tunnel) async {
    _watchdog?.cancel();
    state = const AsyncLoading();
    try {
      final settings = ref.read(settingsProvider);
      AppLog.lazy(
        'Conn',
        () => 'connect "${tunnel.name}" mtuOverride=${settings.mtuOverride} '
            'routing=${settings.routing.mode.name}/${settings.routing.packages.length}',
      );
      await ref.read(connectTunnelProvider).call(
            tunnel,
            mtuOverride: settings.mtuOverride,
            routing: settings.routing,
          );
      state = const AsyncData(null);
      _armWatchdog();
    } catch (e, st) {
      AppLog.d('Conn', 'connect FAILED: $e');
      state = AsyncError(e, st);
    }
  }

  Future<void> disconnect() async {
    _watchdog?.cancel();
    state = const AsyncLoading();
    try {
      AppLog.d('Conn', 'disconnect requested');
      await ref.read(disconnectTunnelProvider).call();
      state = const AsyncData(null);
    } catch (e, st) {
      AppLog.d('Conn', 'disconnect FAILED: $e');
      state = AsyncError(e, st);
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_connectTimeout, () async {
      final st = ref.read(vpnStatusProvider).value?.state;
      // Only fire if we're still stuck mid-connect; a live tunnel or an
      // already-reported error/disconnect needs no action.
      final stuck = st == VpnConnectionState.connecting ||
          st == VpnConnectionState.reconnecting;
      if (!stuck) return;
      AppLog.d('Conn',
          'watchdog: no handshake in ${_connectTimeout.inSeconds}s — aborting');
      await ref.read(disconnectTunnelProvider).call();
      state = AsyncError(
        'Не удалось подключиться — сервер недоступен или не отвечает',
        StackTrace.current,
      );
    });
  }
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, AsyncValue<void>>(
  ConnectionController.new,
);
