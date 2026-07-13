import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
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
      await ref.read(connectTunnelProvider).call(
            tunnel,
            mtuOverride: settings.mtuOverride,
            routing: settings.routing,
          );
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> disconnect() async {
    state = const AsyncLoading();
    try {
      await ref.read(disconnectTunnelProvider).call();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, AsyncValue<void>>(
  ConnectionController.new,
);
