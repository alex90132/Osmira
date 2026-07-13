import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/failure.dart';

/// Converts WireGuard keys between base64 (config form) and hex (uapi form).
///
/// The amneziawg-go userspace API expects 32-byte keys as 64 lowercase hex
/// chars, while `.vpn`/wg-quick configs carry them base64-encoded.
class KeyCodec {
  const KeyCodec();

  /// base64 (44 chars) -> 64-char lowercase hex.
  String base64ToHex(String base64Key) {
    final Uint8List bytes;
    try {
      bytes = base64.decode(base64Key.trim());
    } catch (e) {
      throw ConfigParseFailure('Invalid base64 key', e);
    }
    if (bytes.length != 32) {
      throw ConfigParseFailure('Key must be 32 bytes, got ${bytes.length}');
    }
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
