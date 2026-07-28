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
      bytes = base64.decode(_normalize(base64Key));
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

  /// Accepts the key spellings that show up in the wild and returns padded,
  /// standard-alphabet base64.
  ///
  /// Amnezia 3.0 emits `HeaderProtectionKey` unpadded (43 chars for 32 bytes),
  /// unlike the 44-char padded WireGuard keys next to it, and Dart's decoder
  /// rejects both missing padding and the url-safe alphabet.
  static String _normalize(String key) {
    final cleaned = key.trim().replaceAll('-', '+').replaceAll('_', '/');
    final remainder = cleaned.length % 4;
    if (remainder == 0) return cleaned;
    return cleaned + '=' * (4 - remainder);
  }
}
