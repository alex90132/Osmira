import 'package:meta/meta.dart';

/// Lifecycle state of the VPN tunnel, reported by the native backend.
enum VpnConnectionState {
  disconnected,
  connecting,
  connected,

  /// Tunnel dropped / traffic stalled; the service is re-establishing it.
  reconnecting,
  error,
}

/// A snapshot of tunnel state + live counters, streamed from native.
@immutable
class VpnStatus {
  const VpnStatus({
    this.state = VpnConnectionState.disconnected,
    this.tunnelId,
    this.errorMessage,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastHandshakeEpochSeconds = 0,
  });

  static const VpnStatus disconnected = VpnStatus();

  final VpnConnectionState state;

  /// Id of the tunnel this status refers to (if any).
  final String? tunnelId;

  final String? errorMessage;
  final int rxBytes;
  final int txBytes;

  /// Unix time (seconds) of the last successful handshake, 0 if none yet.
  final int lastHandshakeEpochSeconds;

  bool get isActive =>
      state == VpnConnectionState.connected ||
      state == VpnConnectionState.connecting ||
      state == VpnConnectionState.reconnecting;

  @override
  bool operator ==(Object other) =>
      other is VpnStatus &&
      other.state == state &&
      other.tunnelId == tunnelId &&
      other.errorMessage == errorMessage &&
      other.rxBytes == rxBytes &&
      other.txBytes == txBytes &&
      other.lastHandshakeEpochSeconds == lastHandshakeEpochSeconds;

  @override
  int get hashCode => Object.hash(
        state,
        tunnelId,
        errorMessage,
        rxBytes,
        txBytes,
        lastHandshakeEpochSeconds,
      );
}
