import 'dart:convert';

import 'package:awg2_client/core/failure.dart';
import 'package:awg2_client/features/vpn/data/parser/key_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = KeyCodec();

  test('converts a 32-byte base64 key to 64 lowercase hex chars', () {
    final key = base64.encode(List<int>.generate(32, (i) => i));
    expect(
      codec.base64ToHex(key),
      '000102030405060708090a0b0c0d0e0f'
      '101112131415161718191a1b1c1d1e1f',
    );
  });

  test('all-zero key round-trips to 64 zeros', () {
    final key = base64.encode(List<int>.filled(32, 0));
    expect(codec.base64ToHex(key), '0' * 64);
  });

  test('rejects keys that are not 32 bytes', () {
    final short = base64.encode(List<int>.filled(16, 0));
    expect(
      () => codec.base64ToHex(short),
      throwsA(isA<ConfigParseFailure>()),
    );
  });
}
