import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../../domain/entities/vpn_tunnel.dart';

/// One-shot import action; [state] reflects the last attempt so the UI can
/// show a spinner / error inline.
class ImportController extends Notifier<AsyncValue<VpnTunnel?>> {
  @override
  AsyncValue<VpnTunnel?> build() => const AsyncData(null);

  Future<VpnTunnel?> import(String source, {String? name}) async {
    state = const AsyncLoading();
    try {
      final tunnel =
          await ref.read(importTunnelProvider).call(source, name: name);
      state = AsyncData(tunnel);
      return tunnel;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  void reset() => state = const AsyncData(null);
}

final importControllerProvider =
    NotifierProvider<ImportController, AsyncValue<VpnTunnel?>>(
  ImportController.new,
);
