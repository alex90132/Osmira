import '../../domain/entities/awg_config.dart';
import 'key_codec.dart';

/// Serializes an [AwgConfig] into the amneziawg-go userspace API ("uapi")
/// string consumed by `awgTurnOn(..)`.
///
/// The ordering matters: interface device keys first, then `replace_peers`,
/// then each peer beginning with `public_key`. Keys are emitted as hex.
///
/// Covers AmneziaWG 2.0 (Jc/S/H/I) and 3.0 (header protection, content padding,
/// timings). Optional knobs are omitted when absent rather than sent as zero,
/// because the backend fails the entire config on an unknown or invalid key.
class UapiSerializer {
  const UapiSerializer({KeyCodec keyCodec = const KeyCodec()})
      : _keys = keyCodec;

  final KeyCodec _keys;

  String serialize(AwgConfig config) {
    final sb = StringBuffer();
    final i = config.interface;
    final p = i.parameters;

    sb.writeln('private_key=${_keys.base64ToHex(i.privateKey)}');

    _int(sb, 'jc', p.jc);
    _int(sb, 'jmin', p.jmin);
    _int(sb, 'jmax', p.jmax);
    _int(sb, 's1', p.s1);
    _int(sb, 's2', p.s2);
    _int(sb, 's3', p.s3);
    _int(sb, 's4', p.s4);
    _str(sb, 'h1', p.h1);
    _str(sb, 'h2', p.h2);
    _str(sb, 'h3', p.h3);
    _str(sb, 'h4', p.h4);
    _str(sb, 'i1', p.i1);
    _str(sb, 'i2', p.i2);
    _str(sb, 'i3', p.i3);
    _str(sb, 'i4', p.i4);
    _str(sb, 'i5', p.i5);

    // AWG 3.0. Emitted only when the config actually carries them: an AWG 2.0
    // server never sends these, and the backend rejects the whole config on an
    // unknown device key, so silence is what keeps 2.0 profiles working.
    final hpk = p.headerProtectionKey?.trim();
    if (hpk != null && hpk.isNotEmpty) {
      sb.writeln('header_protection_key=${_keys.base64ToHex(hpk)}');
    }
    _str(sb, 'content_padding_addition', p.contentPaddingAddition);
    _str(sb, 'rekey_after_time', p.rekeyAfterTime);
    _str(sb, 'rekey_timeout', p.rekeyTimeout);
    _str(sb, 'reject_after_time', p.rejectAfterTime);
    _str(sb, 'keepalive_timeout', p.keepaliveTimeout);
    _str(sb, 'max_handshake_attempts', p.maxHandshakeAttempts);

    sb.writeln('replace_peers=true');

    for (final peer in config.peers) {
      sb.writeln('public_key=${_keys.base64ToHex(peer.publicKey)}');
      if (peer.presharedKey != null && peer.presharedKey!.isNotEmpty) {
        sb.writeln('preshared_key=${_keys.base64ToHex(peer.presharedKey!)}');
      }
      final ep = peer.endpoint;
      if (ep != null) {
        sb.writeln('endpoint=${ep.toString()}');
      }
      _str(sb, 'persistent_keepalive_interval', peer.persistentKeepalive);
      for (final ip in peer.allowedIps) {
        sb.writeln('allowed_ip=$ip');
      }
    }

    return sb.toString();
  }

  static void _int(StringBuffer sb, String key, int? value) {
    if (value != null) sb.writeln('$key=$value');
  }

  static void _str(StringBuffer sb, String key, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      sb.writeln('$key=${value.trim()}');
    }
  }
}
