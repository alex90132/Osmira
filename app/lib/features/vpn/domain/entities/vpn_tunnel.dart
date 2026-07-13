import 'package:meta/meta.dart';

import 'awg_config.dart';

/// A saved, named tunnel: the parsed [AwgConfig] plus user metadata (display
/// name) and the original source text so it can be re-exported or re-parsed
/// losslessly. Split-tunnel routing is stored globally in app settings, not
/// here, so it applies to whichever profile is active.
@immutable
class VpnTunnel {
  const VpnTunnel({
    required this.id,
    required this.name,
    required this.config,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String name;
  final AwgConfig config;

  /// Original `vpn://...` (or wg-quick) text this tunnel was imported from.
  final String source;

  final DateTime createdAt;

  VpnTunnel copyWith({String? name}) => VpnTunnel(
        id: id,
        name: name ?? this.name,
        config: config,
        source: source,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) => other is VpnTunnel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
