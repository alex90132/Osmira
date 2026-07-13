import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent record for a saved tunnel. Only lightweight metadata + the
/// original source text is stored; the parsed [AwgConfig] is rebuilt on load
/// from [source] to avoid a second, drift-prone serialization format.
class TunnelRecord {
  const TunnelRecord({
    required this.id,
    required this.name,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String source;
  final String createdAt; // ISO-8601

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'createdAt': createdAt,
      };

  factory TunnelRecord.fromJson(Map<String, dynamic> json) => TunnelRecord(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Tunnel',
        source: json['source'] as String? ?? '',
        createdAt: json['createdAt'] as String? ??
            DateTime.now().toIso8601String(),
      );
}

/// Encrypted store for the tunnel list.
///
/// Tunnel [source] text embeds the WireGuard **private key**, so it must not
/// sit in plaintext SharedPreferences. `flutter_secure_storage` keeps it in
/// Android's EncryptedSharedPreferences (AES via the Keystore), the iOS/macOS
/// Keychain, libsecret on Linux and DPAPI on Windows.
class TunnelStore {
  TunnelStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'tunnels_v1';

  Future<List<TunnelRecord>> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return <TunnelRecord>[];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => TunnelRecord.fromJson((e as Map).cast<String, dynamic>()))
          .toList(); // growable — callers mutate this list
    } catch (_) {
      // No secure-storage backend (e.g. under `flutter test`) or corrupt data:
      // degrade to an empty (growable) list instead of throwing.
      return <TunnelRecord>[];
    }
  }

  Future<void> write(List<TunnelRecord> records) async {
    final raw = jsonEncode(records.map((r) => r.toJson()).toList());
    await _storage.write(key: _key, value: raw);
  }
}
