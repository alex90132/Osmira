import 'dart:convert';

import '../../../../core/failure.dart';
import '../../domain/entities/awg_config.dart';
import 'amnezia_uri_codec.dart';
import 'wg_quick_parser.dart';

/// Result of parsing raw config text: the [config] plus a suggested display
/// [name] (taken from the container's description, when available).
class ParsedConfig {
  const ParsedConfig({required this.config, this.name});
  final AwgConfig config;
  final String? name;
}

/// Turns raw import text — an Amnezia `vpn://` link or plain awg-quick text —
/// into an [AwgConfig]. This is the top-level business entry point for import.
class AmneziaConfigParser {
  const AmneziaConfigParser({
    AmneziaUriCodec uriCodec = const AmneziaUriCodec(),
    WgQuickParser wgQuickParser = const WgQuickParser(),
  })  : _uri = uriCodec,
        _wg = wgQuickParser;

  final AmneziaUriCodec _uri;
  final WgQuickParser _wg;

  ParsedConfig parse(String source) {
    final input = source.trim();
    if (input.isEmpty) {
      throw const ConfigParseFailure('Empty configuration');
    }
    if (_uri.looksLikeUri(input)) {
      return _parseVpnUri(input);
    }
    // Fall back to treating the input as raw awg-quick text.
    if (input.contains('[Interface]')) {
      return ParsedConfig(config: _wg.parse(input));
    }
    throw const ConfigParseFailure(
      'Unrecognized config: expected a vpn:// link or [Interface] block',
    );
  }

  ParsedConfig _parseVpnUri(String uri) {
    final jsonText = _uri.decodeToJson(uri);
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (e) {
      throw ConfigParseFailure('vpn:// payload is not valid JSON', e);
    }

    final name = (root['description'] as String?)?.trim();
    final container = _selectContainer(root);
    final proto = _selectProtocol(container);

    // Prefer the embedded awg-quick `config` string: it carries every field
    // (including I1..I5) exactly as the server intends.
    final lastConfigRaw = proto['last_config'];
    if (lastConfigRaw is String && lastConfigRaw.trim().isNotEmpty) {
      Map<String, dynamic> lastConfig;
      try {
        lastConfig = jsonDecode(lastConfigRaw) as Map<String, dynamic>;
      } catch (e) {
        throw ConfigParseFailure('last_config is not valid JSON', e);
      }
      final wgQuick = lastConfig['config'];
      if (wgQuick is String && wgQuick.contains('[Interface]')) {
        return ParsedConfig(
          config: _wg.parse(wgQuick),
          name: (name != null && name.isNotEmpty) ? name : null,
        );
      }
      return ParsedConfig(
        config: _buildFromFields(lastConfig, proto, root),
        name: name,
      );
    }

    return ParsedConfig(config: _buildFromFields(proto, proto, root), name: name);
  }

  Map<String, dynamic> _selectContainer(Map<String, dynamic> root) {
    final containers = root['containers'];
    if (containers is! List || containers.isEmpty) {
      throw const ConfigParseFailure('No containers in vpn:// config');
    }
    final def = root['defaultContainer'] as String?;
    for (final c in containers) {
      if (c is Map<String, dynamic> && c['container'] == def) return c;
    }
    final first = containers.first;
    if (first is Map<String, dynamic>) return first;
    throw const ConfigParseFailure('Malformed container in vpn:// config');
  }

  Map<String, dynamic> _selectProtocol(Map<String, dynamic> container) {
    for (final key in const ['awg', 'wireguard']) {
      final v = container[key];
      if (v is Map<String, dynamic>) return v;
    }
    throw const UnsupportedConfigFailure(
      'Container is not AmneziaWG/WireGuard (only awg is supported)',
    );
  }

  /// Fallback: assemble an [AwgConfig] from structured JSON fields when no
  /// embedded awg-quick string is present.
  AwgConfig _buildFromFields(
    Map<String, dynamic> cfg,
    Map<String, dynamic> proto,
    Map<String, dynamic> root,
  ) {
    String? str(String k) {
      final v = cfg[k] ?? proto[k] ?? root[k];
      return v?.toString();
    }

    int? intOf(String k) {
      final v = cfg[k] ?? proto[k] ?? root[k];
      if (v == null) return null;
      return v is int ? v : int.tryParse(v.toString());
    }

    final privateKey = str('client_priv_key');
    final publicKey = str('server_pub_key');
    if (privateKey == null || publicKey == null) {
      throw const ConfigParseFailure(
        'vpn:// config is missing keys and has no embedded awg-quick config',
      );
    }

    final addresses = _split(str('client_ip'));
    final allowedIps = _asList(cfg['allowed_ips']) ??
        const ['0.0.0.0/0', '::/0'];
    final host = str('hostName') ?? root['hostName']?.toString();
    final port = intOf('port');
    final dns = <String>[];
    for (final k in const ['dns1', 'dns2']) {
      final d = root[k]?.toString();
      if (d != null && d.isNotEmpty) dns.add(d);
    }

    return AwgConfig(
      interface: AwgInterface(
        privateKey: privateKey,
        addresses: addresses,
        dnsServers: dns,
        mtu: intOf('mtu'),
        parameters: AwgParameters(
          jc: intOf('Jc'),
          jmin: intOf('Jmin'),
          jmax: intOf('Jmax'),
          s1: intOf('S1'),
          s2: intOf('S2'),
          s3: intOf('S3'),
          s4: intOf('S4'),
          h1: str('H1'),
          h2: str('H2'),
          h3: str('H3'),
          h4: str('H4'),
          i1: str('I1'),
          i2: str('I2'),
          i3: str('I3'),
          i4: str('I4'),
          i5: str('I5'),
          headerProtectionKey: str('HeaderProtectionKey'),
          contentPaddingAddition: str('ContentPaddingAddition'),
          rekeyAfterTime: str('RekeyAfterTime'),
          rekeyTimeout: str('RekeyTimeout'),
          rejectAfterTime: str('RejectAfterTime'),
          keepaliveTimeout: str('KeepaliveTimeout'),
          maxHandshakeAttempts: str('MaxHandshakeAttempts'),
        ),
      ),
      peers: [
        AwgPeer(
          publicKey: publicKey,
          presharedKey: str('psk_key'),
          endpoint: (host != null && port != null)
              ? Endpoint(host: host, port: port)
              : null,
          allowedIps: allowedIps,
          persistentKeepalive: str('persistent_keep_alive'),
        ),
      ],
    );
  }

  static List<String> _split(String? v) {
    if (v == null || v.isEmpty) return const [];
    return v
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static List<String>? _asList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).toList(growable: false);
    }
    return null;
  }
}
