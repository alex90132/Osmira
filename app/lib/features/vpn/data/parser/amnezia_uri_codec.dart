import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import '../../../../core/failure.dart';

/// Encodes/decodes the Amnezia `vpn://` container format.
///
/// Wire format: `vpn://` + base64url( qCompress(json) ), where `qCompress`
/// (Qt's `qCompress`) is a 4-byte big-endian *uncompressed length* prefix
/// followed by a zlib stream. We decode by stripping the 4-byte prefix and
/// inflating the rest.
class AmneziaUriCodec {
  const AmneziaUriCodec();

  static const _scheme = 'vpn://';
  static final ZLibCodec _zlib = ZLibCodec();

  bool looksLikeUri(String input) =>
      input.trimLeft().toLowerCase().startsWith('vpn://');

  /// Decodes a `vpn://...` string into its decompressed JSON text.
  String decodeToJson(String uri) {
    final trimmed = uri.trim();
    if (!looksLikeUri(trimmed)) {
      throw const ConfigParseFailure('Not a vpn:// link');
    }
    final b64 = trimmed.substring(_scheme.length).trim();
    final Uint8List raw;
    try {
      raw = _base64UrlDecode(b64);
    } catch (e) {
      throw ConfigParseFailure('Malformed base64 in vpn:// link', e);
    }
    if (raw.length < 5) {
      throw const ConfigParseFailure('vpn:// payload too short');
    }
    try {
      // Skip the 4-byte qCompress length prefix, inflate the zlib body.
      final inflated = _zlib.decode(raw.sublist(4));
      return utf8.decode(inflated);
    } catch (e) {
      throw ConfigParseFailure('Failed to inflate vpn:// payload', e);
    }
  }

  /// Encodes JSON text back into a `vpn://...` string (used for export).
  String encodeFromJson(String json) {
    final data = utf8.encode(json);
    final compressed = _zlib.encode(data);
    final out = BytesBuilder();
    final len = data.length;
    out.add([
      (len >> 24) & 0xff,
      (len >> 16) & 0xff,
      (len >> 8) & 0xff,
      len & 0xff,
    ]);
    out.add(compressed);
    return '$_scheme${_base64UrlEncode(out.toBytes())}';
  }

  static Uint8List _base64UrlDecode(String input) {
    var s = input.replaceAll('\n', '').replaceAll('\r', '').trim();
    // Accept both url-safe and standard alphabets.
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad != 0) s = s.padRight(s.length + (4 - pad), '=');
    return base64.decode(s);
  }

  static String _base64UrlEncode(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
