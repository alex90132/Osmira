import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di.dart';
import '../../vpn/domain/entities/app_routing.dart';
import '../domain/app_settings.dart';

/// Holds [AppSettings] in memory and writes changes through to persistence.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  void _update(AppSettings next) {
    state = next;
    // Fire-and-forget; persistence errors are non-fatal for the UI.
    ref.read(settingsRepositoryProvider).save(next);
  }

  void setNormalizeMtu(bool value) =>
      _update(state.copyWith(normalizeMtu: value));

  void setShowSystemApps(bool value) =>
      _update(state.copyWith(showSystemApps: value));

  void setAutoReconnect(bool value) =>
      _update(state.copyWith(autoReconnect: value));

  void setRoutingMode(AppRoutingMode mode) =>
      _update(state.copyWith(routing: state.routing.copyWith(mode: mode)));

  void toggleRoutingApp(String package) =>
      _update(state.copyWith(routing: state.routing.toggle(package)));

  void setRouting(AppRouting routing) =>
      _update(state.copyWith(routing: routing));
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
