import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../../../../core/log.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../domain/entities/vpn_tunnel.dart';

/// Drives connect/disconnect actions. The [state] is only the *action*
/// progress (busy / failed); the authoritative tunnel state comes from
/// [vpnStatusProvider] streamed by native.
class ConnectionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> connect(VpnTunnel tunnel) async {
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
    } catch (e, st) {
      AppLog.d('Conn', 'connect FAILED: $e');
      state = AsyncError(e, st);
    }
  }

  Future<void> disconnect() async {
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
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, AsyncValue<void>>(
  ConnectionController.new,
);
