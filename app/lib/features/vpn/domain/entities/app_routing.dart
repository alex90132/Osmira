import 'package:meta/meta.dart';

/// Split-tunnelling mode (per-app routing), mirroring the vk-bridge client.
enum AppRoutingMode {
  /// All traffic goes through the tunnel (default).
  all,

  /// Selected apps go *around* the tunnel; everything else is tunnelled
  /// (`addDisallowedApplication`).
  exclude,

  /// Only the selected apps are tunnelled; everything else goes direct
  /// (`addAllowedApplication`).
  include,
}

/// Per-app routing selection for a tunnel.
@immutable
class AppRouting {
  const AppRouting({
    this.mode = AppRoutingMode.all,
    this.packages = const <String>{},
  });

  final AppRoutingMode mode;

  /// Package names the [mode] applies to. Ignored when [mode] is `all`.
  final Set<String> packages;

  bool get isSplit => mode != AppRoutingMode.all;

  AppRouting copyWith({AppRoutingMode? mode, Set<String>? packages}) =>
      AppRouting(
        mode: mode ?? this.mode,
        packages: packages ?? this.packages,
      );

  AppRouting toggle(String package) {
    final next = Set<String>.of(packages);
    if (!next.add(package)) next.remove(package);
    return copyWith(packages: next);
  }

  @override
  bool operator ==(Object other) =>
      other is AppRouting &&
      other.mode == mode &&
      other.packages.length == packages.length &&
      other.packages.containsAll(packages);

  @override
  int get hashCode => Object.hash(mode, Object.hashAllUnordered(packages));
}
