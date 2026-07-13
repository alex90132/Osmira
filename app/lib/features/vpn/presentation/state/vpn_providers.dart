import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../domain/entities/installed_app.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/vpn_tunnel.dart';

/// Persisted tunnel list read *synchronously* in `main()` before the first
/// frame and injected via override. Lets the UI paint the final layout on the
/// cold-start frame instead of flashing a spinner then popping in the list.
final initialTunnelsProvider = Provider<List<VpnTunnel>>(
  (ref) => const <VpnTunnel>[],
);

/// Native tunnel status sampled once in `main()` (override), so a cold start
/// while the VPN is already up shows the active profile immediately.
final initialStatusProvider = Provider<VpnStatus>(
  (ref) => VpnStatus.disconnected,
);

/// Live list of saved tunnels.
final tunnelsProvider = StreamProvider<List<VpnTunnel>>(
  (ref) => ref.watch(watchTunnelsProvider).call(),
);

/// Id of the profile the big power button will act on. Null → fall back to the
/// active tunnel, then to the first profile in the list.
class SelectedTunnelId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedTunnelIdProvider =
    NotifierProvider<SelectedTunnelId, String?>(SelectedTunnelId.new);

/// Live tunnel status streamed from the native service.
final vpnStatusProvider = StreamProvider<VpnStatus>(
  (ref) => ref.watch(watchVpnStatusProvider).call(),
);

/// Id of the currently active (connecting/connected/reconnecting) tunnel, or
/// null. Derived so it only notifies listeners when the *identity* changes —
/// the profile list can watch this without rebuilding every 2s on each
/// rx/tx/handshake counter tick.
final activeTunnelIdProvider = Provider<String?>((ref) {
  final VpnStatus fallback = ref.watch(initialStatusProvider);
  final status = ref.watch(vpnStatusProvider).value ?? fallback;
  return status.isActive ? status.tunnelId : null;
});

/// Payloads handed to the app via a tapped `.vpn` file or `vpn://` deep link.
final incomingImportProvider = StreamProvider<String>(
  (ref) => ref.watch(importLinkDataSourceProvider).links(),
);

/// Installed apps for the split-tunnel picker. Rebuilds *only* when the
/// "show system apps" preference changes — `select` keeps toggling an app in
/// the routing list from re-fetching the whole (icon-heavy) app list.
final installedAppsProvider = FutureProvider.autoDispose<List<InstalledApp>>(
  (ref) {
    final showSystem =
        ref.watch(settingsProvider.select((s) => s.showSystemApps));
    // Keep the fetched list alive briefly so navigating back and forth to the
    // picker doesn't re-query the OS every time.
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 2), link.close);
    ref.onDispose(timer.cancel);
    return ref
        .watch(installedAppsRepositoryProvider)
        .getInstalledApps(includeSystem: showSystem);
  },
);
