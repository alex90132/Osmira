import '../../../../core/failure.dart';
import '../../domain/entities/awg_config.dart';

/// Parses awg-quick / wg-quick configuration text into an [AwgConfig].
///
/// Understands the full AmneziaWG 2.0 key set (Jc/Jmin/Jmax, S1..S4,
/// H1..H4, I1..I5) and the 3.0 additions (HeaderProtectionKey,
/// ContentPaddingAddition and the timing knobs) in addition to standard
/// WireGuard keys. Critically, I1..I5 values (e.g. `<b 0x01><r 74><t>`)
/// contain spaces and are kept verbatim — only list-valued keys
/// (Address/DNS/AllowedIPs) are comma-split.
class WgQuickParser {
  const WgQuickParser();

  AwgConfig parse(String text) {
    final interfaceLines = <MapEntry<String, String>>[];
    final peerBlocks = <List<MapEntry<String, String>>>[];
    List<MapEntry<String, String>>? current;
    var section = _Section.none;

    for (var raw in text.split('\n')) {
      final hash = raw.indexOf('#');
      if (hash != -1) raw = raw.substring(0, hash);
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('[')) {
        final s = line.toLowerCase();
        if (s == '[interface]') {
          section = _Section.iface;
        } else if (s == '[peer]') {
          section = _Section.peer;
          current = <MapEntry<String, String>>[];
          peerBlocks.add(current);
        } else {
          throw ConfigParseFailure('Unknown section: $line');
        }
        continue;
      }

      final eq = line.indexOf('=');
      if (eq == -1) {
        throw ConfigParseFailure('Invalid line (no "="): $line');
      }
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      switch (section) {
        case _Section.iface:
          interfaceLines.add(MapEntry(key, value));
        case _Section.peer:
          current!.add(MapEntry(key, value));
        case _Section.none:
          throw ConfigParseFailure('Line before any section: $line');
      }
    }

    if (interfaceLines.isEmpty) {
      throw const ConfigParseFailure('Missing [Interface] section');
    }

    return AwgConfig(
      interface: _buildInterface(interfaceLines),
      peers: peerBlocks.map(_buildPeer).toList(growable: false),
    );
  }

  AwgInterface _buildInterface(List<MapEntry<String, String>> lines) {
    String? privateKey;
    final addresses = <String>[];
    final dns = <String>[];
    final search = <String>[];
    int? mtu;
    int? jc, jmin, jmax, s1, s2, s3, s4;
    String? h1, h2, h3, h4, i1, i2, i3, i4, i5;
    String? hpk, contentPadding, rekeyAfter, rekeyTimeout, rejectAfter;
    String? keepaliveTimeout, maxHandshakes;

    for (final e in lines) {
      switch (e.key) {
        case 'privatekey':
          privateKey = e.value;
        case 'address':
          addresses.addAll(_csv(e.value));
        case 'dns':
          for (final d in _csv(e.value)) {
            (_isIp(d) ? dns : search).add(d);
          }
        case 'mtu':
          mtu = int.tryParse(e.value);
        case 'listenport':
          break; // irrelevant on a client
        case 'jc':
          jc = int.tryParse(e.value);
        case 'jmin':
          jmin = int.tryParse(e.value);
        case 'jmax':
          jmax = int.tryParse(e.value);
        case 's1':
          s1 = int.tryParse(e.value);
        case 's2':
          s2 = int.tryParse(e.value);
        case 's3':
          s3 = int.tryParse(e.value);
        case 's4':
          s4 = int.tryParse(e.value);
        case 'h1':
          h1 = e.value;
        case 'h2':
          h2 = e.value;
        case 'h3':
          h3 = e.value;
        case 'h4':
          h4 = e.value;
        case 'i1':
          i1 = e.value;
        case 'i2':
          i2 = e.value;
        case 'i3':
          i3 = e.value;
        case 'i4':
          i4 = e.value;
        case 'i5':
          i5 = e.value;
        case 'headerprotectionkey':
          hpk = e.value;
        case 'contentpaddingaddition':
          contentPadding = e.value;
        case 'rekeyaftertime':
          rekeyAfter = e.value;
        case 'rekeytimeout':
          rekeyTimeout = e.value;
        case 'rejectaftertime':
          rejectAfter = e.value;
        case 'keepalivetimeout':
          keepaliveTimeout = e.value;
        case 'maxhandshakeattempts':
          maxHandshakes = e.value;
        default:
          // Ignore unknown/host-only keys (e.g. Table, PreUp) for robustness.
          break;
      }
    }

    if (privateKey == null || privateKey.isEmpty) {
      throw const ConfigParseFailure('[Interface] is missing PrivateKey');
    }

    return AwgInterface(
      privateKey: privateKey,
      addresses: addresses,
      dnsServers: dns,
      dnsSearchDomains: search,
      mtu: mtu,
      parameters: AwgParameters(
        jc: jc,
        jmin: jmin,
        jmax: jmax,
        s1: s1,
        s2: s2,
        s3: s3,
        s4: s4,
        h1: h1,
        h2: h2,
        h3: h3,
        h4: h4,
        i1: i1,
        i2: i2,
        i3: i3,
        i4: i4,
        i5: i5,
        headerProtectionKey: hpk,
        contentPaddingAddition: contentPadding,
        rekeyAfterTime: rekeyAfter,
        rekeyTimeout: rekeyTimeout,
        rejectAfterTime: rejectAfter,
        keepaliveTimeout: keepaliveTimeout,
        maxHandshakeAttempts: maxHandshakes,
      ),
    );
  }

  AwgPeer _buildPeer(List<MapEntry<String, String>> lines) {
    String? publicKey;
    String? psk;
    Endpoint? endpoint;
    final allowed = <String>[];
    String? keepalive;

    for (final e in lines) {
      switch (e.key) {
        case 'publickey':
          publicKey = e.value;
        case 'presharedkey':
          psk = e.value;
        case 'endpoint':
          endpoint = _parseEndpoint(e.value);
        case 'allowedips':
          allowed.addAll(_csv(e.value));
        case 'persistentkeepalive':
          keepalive = e.value;
        default:
          break;
      }
    }

    if (publicKey == null || publicKey.isEmpty) {
      throw const ConfigParseFailure('[Peer] is missing PublicKey');
    }

    return AwgPeer(
      publicKey: publicKey,
      presharedKey: psk,
      endpoint: endpoint,
      allowedIps: allowed,
      persistentKeepalive: keepalive,
    );
  }

  static List<String> _csv(String v) => v
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static Endpoint _parseEndpoint(String v) {
    final value = v.trim();
    // IPv6 bracketed form: [addr]:port
    if (value.startsWith('[')) {
      final close = value.indexOf(']');
      if (close == -1) throw ConfigParseFailure('Bad endpoint: $value');
      final host = value.substring(1, close);
      final rest = value.substring(close + 1);
      final port = int.tryParse(rest.replaceFirst(':', '').trim());
      if (port == null) throw ConfigParseFailure('Bad endpoint port: $value');
      return Endpoint(host: host, port: port);
    }
    final colon = value.lastIndexOf(':');
    if (colon == -1) throw ConfigParseFailure('Endpoint missing port: $value');
    final host = value.substring(0, colon);
    final port = int.tryParse(value.substring(colon + 1).trim());
    if (port == null) throw ConfigParseFailure('Bad endpoint port: $value');
    return Endpoint(host: host, port: port);
  }

  static bool _isIp(String s) {
    if (s.contains(':')) return true; // IPv6
    final parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }
}

enum _Section { none, iface, peer }
