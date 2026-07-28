import 'dart:convert';

import 'package:awg2_client/features/vpn/data/parser/uapi_serializer.dart';
import 'package:awg2_client/features/vpn/domain/entities/awg_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serializer = UapiSerializer();
  final priv = base64.encode(List<int>.filled(32, 5));
  final pub = base64.encode(List<int>.filled(32, 6));

  test('emits hex keys, AWG params, then peer block in order', () {
    final cfg = AwgConfig(
      interface: AwgInterface(
        privateKey: priv,
        addresses: const ['10.8.0.2/32'],
        mtu: 1280,
        parameters: const AwgParameters(
          jc: 4,
          s1: 30,
          h1: '1',
          i1: '<b 0x01><t>',
        ),
      ),
      peers: [
        AwgPeer(
          publicKey: pub,
          endpoint: const Endpoint(host: '1.2.3.4', port: 586),
          allowedIps: const ['0.0.0.0/0', '::/0'],
          persistentKeepalive: '25',
        ),
      ],
    );

    final uapi = serializer.serialize(cfg);
    final lines = const LineSplitter().convert(uapi);

    expect(lines.first, 'private_key=${'05' * 32}');
    expect(lines, contains('jc=4'));
    expect(lines, contains('s1=30'));
    expect(lines, contains('h1=1'));
    expect(lines, contains('i1=<b 0x01><t>'));
    expect(lines, contains('replace_peers=true'));
    expect(lines, contains('public_key=${'06' * 32}'));
    expect(lines, contains('endpoint=1.2.3.4:586'));
    expect(lines, contains('persistent_keepalive_interval=25'));
    expect(lines, contains('allowed_ip=0.0.0.0/0'));
    expect(lines, contains('allowed_ip=::/0'));

    // Device config must precede peers.
    expect(
      lines.indexOf('replace_peers=true') <
          lines.indexOf('public_key=${'06' * 32}'),
      isTrue,
    );
  });

  test('omits AWG 3.0 keys entirely for a 2.0 config', () {
    final cfg = AwgConfig(
      interface: AwgInterface(
        privateKey: priv,
        parameters: const AwgParameters(jc: 4, s3: 10, i1: '<t>'),
      ),
      peers: [AwgPeer(publicKey: pub)],
    );

    final uapi = serializer.serialize(cfg);

    // The backend rejects the whole config on an unknown/invalid device key, so
    // a 2.0 profile must not carry any 3.0 key at all.
    for (final key in const [
      'header_protection_key',
      'content_padding_addition',
      'rekey_after_time',
      'rekey_timeout',
      'reject_after_time',
      'keepalive_timeout',
      'max_handshake_attempts',
    ]) {
      expect(uapi, isNot(contains(key)), reason: '$key must not be emitted');
    }
  });

  test('emits AWG 3.0 knobs with a hex header protection key', () {
    final hpk = base64.encode(List<int>.filled(32, 7));
    final cfg = AwgConfig(
      interface: AwgInterface(
        privateKey: priv,
        parameters: AwgParameters(
          headerProtectionKey: hpk,
          contentPaddingAddition: '10-30',
          rekeyAfterTime: '120',
          rekeyTimeout: '5',
          rejectAfterTime: '180',
          keepaliveTimeout: '10-15',
          maxHandshakeAttempts: '18',
        ),
      ),
      peers: [AwgPeer(publicKey: pub, persistentKeepalive: '22-30')],
    );

    final lines = const LineSplitter().convert(serializer.serialize(cfg));

    expect(lines, contains('header_protection_key=${'07' * 32}'));
    expect(lines, contains('content_padding_addition=10-30'));
    expect(lines, contains('rekey_after_time=120'));
    expect(lines, contains('rekey_timeout=5'));
    expect(lines, contains('reject_after_time=180'));
    expect(lines, contains('keepalive_timeout=10-15'));
    expect(lines, contains('max_handshake_attempts=18'));
    // AWG 3.0 allows a randomized keepalive range, not just a fixed integer.
    expect(lines, contains('persistent_keepalive_interval=22-30'));

    // 3.0 device keys must still land before the peer block.
    expect(
      lines.indexOf('header_protection_key=${'07' * 32}') <
          lines.indexOf('replace_peers=true'),
      isTrue,
    );
  });

  test('accepts an unpadded HeaderProtectionKey', () {
    // Amnezia 3.0 ships this key unpadded (43 chars for 32 bytes) while the
    // WireGuard keys beside it stay padded at 44.
    final unpadded = base64.encode(List<int>.filled(32, 9)).replaceAll('=', '');
    expect(unpadded, hasLength(43));

    final cfg = AwgConfig(
      interface: AwgInterface(
        privateKey: priv,
        parameters: AwgParameters(headerProtectionKey: unpadded),
      ),
      peers: [AwgPeer(publicKey: pub)],
    );

    expect(
      const LineSplitter().convert(serializer.serialize(cfg)),
      contains('header_protection_key=${'09' * 32}'),
    );
  });
}
