/// Base type for domain-level errors surfaced to the UI.
///
/// Keeping a small sealed hierarchy (instead of leaking raw exceptions into the
/// presentation layer) is what lets the UI render friendly messages while the
/// business layer stays framework-agnostic.
sealed class Failure implements Exception {
  const Failure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The `vpn://` payload could not be decoded (bad base64/zlib/JSON).
class ConfigParseFailure extends Failure {
  const ConfigParseFailure(super.message, [super.cause]);
}

/// A valid container was decoded but it is not an AmneziaWG (`amnezia-awg`) one.
class UnsupportedConfigFailure extends Failure {
  const UnsupportedConfigFailure(super.message, [super.cause]);
}

/// Something went wrong while talking to the native VPN backend.
class VpnBackendFailure extends Failure {
  const VpnBackendFailure(super.message, [super.cause]);
}

/// Local persistence (shared_preferences) failed.
class StorageFailure extends Failure {
  const StorageFailure(super.message, [super.cause]);
}
