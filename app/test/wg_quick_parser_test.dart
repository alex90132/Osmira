import 'dart:convert';

import 'package:awg2_client/features/vpn/data/parser/wg_quick_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = WgQuickParser();
  final priv = base64.encode(List<int>.filled(32, 1));
  final pub = base64.encode(List<int>.filled(32, 2));

  test('parses interface, AWG params and peer', () {
    final cfg = parser.parse('''
[Interface]
PrivateKey = $priv
Address = 10.8.0.2/32, fd42::2/128
DNS = 1.1.1.1, example.local
MTU = 1280
Jc = 4
Jmin = 8
Jmax = 80
S1 = 30
S2 = 40
H1 = 1
I1 = <b 0xf1><r 74><t>

[Peer]
PublicKey = $pub
Endpoint = vpn.example.com:586
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''');

    final i = cfg.interface;
    expect(i.privateKey, priv);
    expect(i.addresses, ['10.8.0.2/32', 'fd42::2/128']);
    expect(i.dnsServers, ['1.1.1.1']);
    expect(i.dnsSearchDomains, ['example.local']);
    expect(i.mtu, 1280);
    expect(i.parameters.jc, 4);
    expect(i.parameters.s1, 30);
    expect(i.parameters.h1, '1');
    expect(i.parameters.i1, '<b 0xf1><r 74><t>');
    expect(i.parameters.isV2, isTrue); // I1 present

    expect(cfg.peers, hasLength(1));
    final p = cfg.peers.single;
    expect(p.publicKey, pub);
    expect(p.endpoint?.host, 'vpn.example.com');
    expect(p.endpoint?.port, 586);
    expect(p.allowedIps, ['0.0.0.0/0', '::/0']);
    expect(p.persistentKeepalive, '25');
    expect(i.parameters.isV3, isFalse);
    expect(cfg.isFullTunnel, isTrue);
  });

  test('parses AWG 3.0 header protection, padding and timings', () {
    final hpk = base64.encode(List<int>.filled(32, 3));
    final cfg = parser.parse('''
[Interface]
PrivateKey = $priv
Address = 10.8.0.2/32
S1 = 8
HeaderProtectionKey = $hpk
ContentPaddingAddition = 10-30
RekeyAfterTime = 120
RekeyTimeout = 5
RejectAfterTime = 180
KeepaliveTimeout = 10-15
MaxHandshakeAttempts = 18

[Peer]
PublicKey = $pub
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 22-30
''');

    final p = cfg.interface.parameters;
    expect(p.headerProtectionKey, hpk);
    expect(p.contentPaddingAddition, '10-30');
    expect(p.rekeyAfterTime, '120');
    expect(p.rekeyTimeout, '5');
    expect(p.rejectAfterTime, '180');
    expect(p.keepaliveTimeout, '10-15');
    expect(p.maxHandshakeAttempts, '18');
    expect(p.isV3, isTrue);
    expect(cfg.peers.single.persistentKeepalive, '22-30');
  });

  test('keeps scripted I-values with spaces verbatim', () {
    final cfg = parser.parse('''
[Interface]
PrivateKey = $priv
I2 = <c><b 0x00000000><t>

[Peer]
PublicKey = $pub
AllowedIPs = 10.0.0.0/24
''');
    expect(cfg.interface.parameters.i2, '<c><b 0x00000000><t>');
    expect(cfg.isFullTunnel, isFalse);
  });
}
