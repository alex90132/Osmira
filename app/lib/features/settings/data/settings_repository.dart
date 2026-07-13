import 'package:shared_preferences/shared_preferences.dart';

import '../../vpn/domain/entities/app_routing.dart';
import '../domain/app_settings.dart';

/// Loads/persists [AppSettings] via shared_preferences.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kNormalizeMtu = 'settings_normalize_mtu';
  static const _kShowSystemApps = 'settings_show_system_apps';
  static const _kAutoReconnect = 'settings_auto_reconnect';
  static const _kRoutingMode = 'settings_routing_mode';
  static const _kRoutingApps = 'settings_routing_apps';

  AppSettings load() => AppSettings(
        normalizeMtu: _prefs.getBool(_kNormalizeMtu) ?? false,
        showSystemApps: _prefs.getBool(_kShowSystemApps) ?? false,
        autoReconnect: _prefs.getBool(_kAutoReconnect) ?? true,
        routing: AppRouting(
          mode: _modeFrom(_prefs.getString(_kRoutingMode)),
          packages: (_prefs.getStringList(_kRoutingApps) ?? const []).toSet(),
        ),
      );

  Future<void> save(AppSettings s) async {
    await _prefs.setBool(_kNormalizeMtu, s.normalizeMtu);
    await _prefs.setBool(_kShowSystemApps, s.showSystemApps);
    await _prefs.setBool(_kAutoReconnect, s.autoReconnect);
    await _prefs.setString(_kRoutingMode, s.routing.mode.name);
    await _prefs.setStringList(
      _kRoutingApps,
      s.routing.packages.toList(growable: false),
    );
  }

  static AppRoutingMode _modeFrom(String? s) => switch (s) {
        'exclude' => AppRoutingMode.exclude,
        'include' => AppRoutingMode.include,
        _ => AppRoutingMode.all,
      };
}
