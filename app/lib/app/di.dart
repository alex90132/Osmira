import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/data/settings_repository.dart';
import '../features/vpn/data/datasources/import_link_datasource.dart';
import '../features/vpn/data/datasources/native_vpn_datasource.dart';
import '../features/vpn/data/datasources/tunnel_store.dart';
import '../features/vpn/data/repositories/installed_apps_repository_impl.dart';
import '../features/vpn/data/repositories/tunnel_repository_impl.dart';
import '../features/vpn/data/repositories/vpn_connection_repository_impl.dart';
import '../features/vpn/domain/repositories/installed_apps_repository.dart';
import '../features/vpn/domain/repositories/tunnel_repository.dart';
import '../features/vpn/domain/repositories/vpn_connection_repository.dart';
import '../features/vpn/domain/usecases/connection_usecases.dart';
import '../features/vpn/domain/usecases/tunnel_usecases.dart';

/// Composition root: wires data sources, repositories and use cases so the
/// presentation layer only ever depends on abstractions. Overridden in
/// `main()` with the real [SharedPreferences] instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

// ── data sources ──────────────────────────────────────────────────────────
final tunnelStoreProvider = Provider<TunnelStore>(
  (ref) => TunnelStore(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final nativeVpnDataSourceProvider = Provider<NativeVpnDataSource>(
  (ref) => NativeVpnDataSource(),
);

final importLinkDataSourceProvider = Provider<ImportLinkDataSource>((ref) {
  final ds = ImportLinkDataSource();
  ref.onDispose(ds.dispose);
  return ds;
});

// ── repositories ──────────────────────────────────────────────────────────
final tunnelRepositoryProvider = Provider<TunnelRepository>((ref) {
  final repo = TunnelRepositoryImpl(store: ref.watch(tunnelStoreProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final vpnConnectionRepositoryProvider = Provider<VpnConnectionRepository>(
  (ref) => VpnConnectionRepositoryImpl(
    native: ref.watch(nativeVpnDataSourceProvider),
  ),
);

final installedAppsRepositoryProvider = Provider<InstalledAppsRepository>(
  (ref) => InstalledAppsRepositoryImpl(ref.watch(nativeVpnDataSourceProvider)),
);

// ── use cases ─────────────────────────────────────────────────────────────
final importTunnelProvider = Provider(
  (ref) => ImportTunnel(ref.watch(tunnelRepositoryProvider)),
);
final parseTunnelProvider = Provider(
  (ref) => ParseTunnel(ref.watch(tunnelRepositoryProvider)),
);
final watchTunnelsProvider = Provider(
  (ref) => WatchTunnels(ref.watch(tunnelRepositoryProvider)),
);
final deleteTunnelProvider = Provider(
  (ref) => DeleteTunnel(ref.watch(tunnelRepositoryProvider)),
);
final markTunnelConnectedProvider = Provider(
  (ref) => MarkTunnelConnected(ref.watch(tunnelRepositoryProvider)),
);
final updateTunnelProvider = Provider(
  (ref) => UpdateTunnel(ref.watch(tunnelRepositoryProvider)),
);
final connectTunnelProvider = Provider(
  (ref) => ConnectTunnel(ref.watch(vpnConnectionRepositoryProvider)),
);
final disconnectTunnelProvider = Provider(
  (ref) => DisconnectTunnel(ref.watch(vpnConnectionRepositoryProvider)),
);
final watchVpnStatusProvider = Provider(
  (ref) => WatchVpnStatus(ref.watch(vpnConnectionRepositoryProvider)),
);
