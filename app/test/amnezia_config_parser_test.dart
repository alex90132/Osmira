import 'dart:convert';

import 'package:awg2_client/core/failure.dart';
import 'package:awg2_client/features/vpn/data/parser/amnezia_config_parser.dart';
import 'package:awg2_client/features/vpn/data/parser/amnezia_uri_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AmneziaConfigParser();
  const uri = AmneziaUriCodec();
  final priv = base64.encode(List<int>.filled(32, 3));
  final pub = base64.encode(List<int>.filled(32, 4));

  String buildVpnLink(String wgQuick) {
    final root = {
      'description': 'Osmi Test',
      'defaultContainer': 'amnezia-awg',
      'containers': [
        {
          'container': 'amnezia-awg',
          'awg': {
            'last_config': jsonEncode({'config': wgQuick}),
          },
        },
      ],
    };
    return uri.encodeFromJson(jsonEncode(root));
  }

  test('vpn:// round-trip decodes the embedded awg-quick config', () {
    final link = buildVpnLink('''
[Interface]
PrivateKey = $priv
Address = 10.8.0.2/32
DNS = 1.1.1.1
Jc = 3
S1 = 15

[Peer]
PublicKey = $pub
Endpoint = 193.23.218.105:586
AllowedIPs = 0.0.0.0/0, ::/0
''');

    final parsed = parser.parse(link);
    expect(parsed.name, 'Osmi Test');
    expect(parsed.config.interface.privateKey, priv);
    expect(parsed.config.interface.parameters.jc, 3);
    expect(parsed.config.primaryEndpoint?.host, '193.23.218.105');
    expect(parsed.config.primaryEndpoint?.port, 586);
    expect(parsed.config.isFullTunnel, isTrue);
  });

  test('raw wg-quick text is parsed directly', () {
    final parsed = parser.parse('''
[Interface]
PrivateKey = $priv

[Peer]
PublicKey = $pub
AllowedIPs = 0.0.0.0/0
''');
    expect(parsed.config.interface.privateKey, priv);
  });

  test('empty input throws ConfigParseFailure', () {
    expect(() => parser.parse('   '), throwsA(isA<ConfigParseFailure>()));
  });

  test('non-awg / unknown text throws', () {
    expect(
      () => parser.parse('just some random text'),
      throwsA(isA<Failure>()),
    );
  });
}
