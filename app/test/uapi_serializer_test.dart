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
          persistentKeepalive: 25,
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
}
