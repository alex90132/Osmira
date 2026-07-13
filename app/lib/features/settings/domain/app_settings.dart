import 'package:meta/meta.dart';

import '../../vpn/domain/entities/app_routing.dart';

/// User-tunable options, most of them stealth/anti-detection oriented.
///
/// [routing] is deliberately **global** (applies to every profile) rather than
/// per-tunnel, mirroring the vk-bridge client: the split-tunnel app list is a
/// device-wide policy, not something you re-pick for each config.
@immutable
class AppSettings {
  const AppSettings({
    this.normalizeMtu = false,
    this.showSystemApps = false,
    this.autoReconnect = true,
    this.routing = const AppRouting(),
  });

  /// Force the TUN MTU to 1500 instead of the config value. Masks the
  /// WireGuard MTU/MSS-reduction fingerprint that on-device detectors look for
  /// (at a small cost to large-packet reliability on some paths).
  final bool normalizeMtu;

  /// Include pre-installed system apps in the split-tunnel picker.
  final bool showSystemApps;

  /// Ask the native service to auto-reconnect when the tunnel stalls.
  final bool autoReconnect;

  /// Global per-app routing (split tunnel), applied to whichever profile is up.
  final AppRouting routing;

  int? get mtuOverride => normalizeMtu ? 1500 : null;

  AppSettings copyWith({
    bool? normalizeMtu,
    bool? showSystemApps,
    bool? autoReconnect,
    AppRouting? routing,
  }) =>
      AppSettings(
        normalizeMtu: normalizeMtu ?? this.normalizeMtu,
        showSystemApps: showSystemApps ?? this.showSystemApps,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        routing: routing ?? this.routing,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.normalizeMtu == normalizeMtu &&
      other.showSystemApps == showSystemApps &&
      other.autoReconnect == autoReconnect &&
      other.routing == routing;

  @override
  int get hashCode =>
      Object.hash(normalizeMtu, showSystemApps, autoReconnect, routing);
}
