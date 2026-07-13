import 'package:meta/meta.dart';

/// A peer UDP endpoint (`host:port`). Host may be an IP literal or a DNS name;
/// name resolution is deliberately left to the native layer (it happens right
/// before the tunnel comes up, on the correct underlying network).
@immutable
class Endpoint {
  const Endpoint({required this.host, required this.port});

  final String host;
  final int port;

  @override
  String toString() {
    // IPv6 literals must be bracketed in host:port form.
    final h = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
    return '$h:$port';
  }

  @override
  bool operator ==(Object other) =>
      other is Endpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// AmneziaWG obfuscation parameters.
///
/// These are the knobs that make AmneziaWG traffic look like noise to DPI:
/// `Jc/Jmin/Jmax` (junk packets), `S1..S4` (junk sizes prepended to the four
/// packet kinds), `H1..H4` (magic headers, single value or `min-max` range in
/// AWG 2.0) and `I1..I5` (fully scripted "special junk" packets — a 2.0
/// feature, e.g. `<b 0x..><r 74><t>`). Everything is optional; a plain
/// WireGuard config simply leaves them all null.
@immutable
class AwgParameters {
  const AwgParameters({
    this.jc,
    this.jmin,
    this.jmax,
    this.s1,
    this.s2,
    this.s3,
    this.s4,
    this.h1,
    this.h2,
    this.h3,
    this.h4,
    this.i1,
    this.i2,
    this.i3,
    this.i4,
    this.i5,
  });

  final int? jc;
  final int? jmin;
  final int? jmax;
  final int? s1;
  final int? s2;
  final int? s3;
  final int? s4;
  final String? h1;
  final String? h2;
  final String? h3;
  final String? h4;
  final String? i1;
  final String? i2;
  final String? i3;
  final String? i4;
  final String? i5;

  bool get isEmpty =>
      jc == null &&
      jmin == null &&
      jmax == null &&
      s1 == null &&
      s2 == null &&
      s3 == null &&
      s4 == null &&
      h1 == null &&
      h2 == null &&
      h3 == null &&
      h4 == null &&
      i1 == null &&
      i2 == null &&
      i3 == null &&
      i4 == null &&
      i5 == null;

  /// True when 2.0-only knobs are present (S3/S4, header ranges, or I1..I5).
  bool get isV2 =>
      s3 != null ||
      s4 != null ||
      i1 != null ||
      i2 != null ||
      i3 != null ||
      i4 != null ||
      i5 != null ||
      _isRange(h1) ||
      _isRange(h2) ||
      _isRange(h3) ||
      _isRange(h4);

  static bool _isRange(String? v) => v != null && v.contains('-');
}

/// The `[Interface]` section of an AmneziaWG config.
@immutable
class AwgInterface {
  const AwgInterface({
    required this.privateKey,
    this.addresses = const [],
    this.dnsServers = const [],
    this.dnsSearchDomains = const [],
    this.mtu,
    this.parameters = const AwgParameters(),
  });

  /// Base64-encoded Curve25519 private key.
  final String privateKey;

  /// Interface addresses as `ip/prefix` strings (v4 and/or v6).
  final List<String> addresses;

  /// DNS server IPs.
  final List<String> dnsServers;

  /// DNS search domains (non-IP `DNS =` entries).
  final List<String> dnsSearchDomains;

  final int? mtu;
  final AwgParameters parameters;
}

/// A `[Peer]` section of an AmneziaWG config.
@immutable
class AwgPeer {
  const AwgPeer({
    required this.publicKey,
    this.presharedKey,
    this.endpoint,
    this.allowedIps = const [],
    this.persistentKeepalive,
  });

  /// Base64-encoded public key.
  final String publicKey;

  /// Base64-encoded pre-shared key, if any.
  final String? presharedKey;

  final Endpoint? endpoint;

  /// Allowed IPs as `ip/prefix` strings. These double as the OS routes.
  final List<String> allowedIps;

  final int? persistentKeepalive;
}

/// A complete AmneziaWG configuration (one interface + one or more peers).
///
/// This is the central business entity: everything else (import, storage,
/// uapi serialization, TUN setup) is expressed in terms of it.
@immutable
class AwgConfig {
  const AwgConfig({required this.interface, required this.peers});

  final AwgInterface interface;
  final List<AwgPeer> peers;

  /// The endpoint used for the primary (first) peer, if present.
  Endpoint? get primaryEndpoint =>
      peers.isEmpty ? null : peers.first.endpoint;

  /// True if any peer routes the default route (0.0.0.0/0 or ::/0).
  bool get isFullTunnel => peers.any(
        (p) => p.allowedIps.any((a) => a == '0.0.0.0/0' || a == '::/0'),
      );
}
