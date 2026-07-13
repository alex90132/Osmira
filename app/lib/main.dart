import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/di.dart';
import 'app/theme.dart';
import 'features/vpn/data/datasources/native_vpn_datasource.dart';
import 'features/vpn/data/datasources/tunnel_store.dart';
import 'features/vpn/data/repositories/tunnel_repository_impl.dart';
import 'features/vpn/domain/entities/vpn_status.dart';
import 'features/vpn/domain/entities/vpn_tunnel.dart';
import 'features/vpn/presentation/screens/home_screen.dart';
import 'features/vpn/presentation/state/vpn_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  // Resolve everything the first frame needs *before* runApp so the cold-start
  // UI paints fully assembled (no spinner→content pop, no layout jump). All
  // reads run concurrently and are bounded so a slow/absent backend can't
  // stall the splash.
  final results = await Future.wait([
    SharedPreferences.getInstance(),
    _readInitialTunnels(),
    _readInitialStatus(),
  ]);
  final prefs = results[0] as SharedPreferences;
  final initialTunnels = results[1] as List<VpnTunnel>;
  final initialStatus = results[2] as VpnStatus;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialTunnelsProvider.overrideWithValue(initialTunnels),
        initialStatusProvider.overrideWithValue(initialStatus),
      ],
      child: const OsmiraApp(),
    ),
  );
}

Future<List<VpnTunnel>> _readInitialTunnels() async {
  final repo = TunnelRepositoryImpl(store: TunnelStore());
  try {
    return await repo
        .getTunnels()
        .timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    return const <VpnTunnel>[];
  } finally {
    repo.dispose();
  }
}

Future<VpnStatus> _readInitialStatus() async {
  try {
    return await NativeVpnDataSource()
        .currentStatus()
        .timeout(const Duration(milliseconds: 800));
  } catch (_) {
    return VpnStatus.disconnected;
  }
}

class OsmiraApp extends StatelessWidget {
  const OsmiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Osmira',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: const HomeScreen(),
      builder: (context, child) {
        final navH = MediaQuery.of(context).viewPadding.bottom;
        if (navH <= 0) return child ?? const SizedBox.shrink();
        // Solid black strip sitting *exactly* over the system navigation bar
        // (its height, nothing above it) so the bar blends into the black UI
        // without darkening the on-screen buttons just above it.
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: navH,
              child: const IgnorePointer(
                child: ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ],
        );
      },
    );
  }
}
