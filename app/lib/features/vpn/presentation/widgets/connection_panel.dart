import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/formatters.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/vpn_tunnel.dart';

/// The centrepiece of the home screen: a big circular power toggle, the
/// connection status line and (when up) a compact stats strip — modelled on
/// the TBridge/vk-bridge client.
class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel({
    super.key,
    required this.status,
    required this.selected,
    required this.onToggle,
  });

  final VpnStatus status;

  /// Tunnel the power button will act on (the active one, or the user's pick).
  final VpnTunnel? selected;

  final VoidCallback onToggle;

  bool get _busy =>
      status.state == VpnConnectionState.connecting ||
      status.state == VpnConnectionState.reconnecting;

  Color get _ring => switch (status.state) {
        VpnConnectionState.connected => AppColors.connected,
        VpnConnectionState.connecting => AppColors.pending,
        VpnConnectionState.reconnecting => AppColors.pending,
        VpnConnectionState.error => AppColors.error,
        VpnConnectionState.disconnected => AppColors.idle,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PowerButton(ring: _ring, busy: _busy, onTap: onToggle),
        const SizedBox(height: 18),
        _StatusText(status: status, selected: selected),
        if (status.state == VpnConnectionState.connected) ...[
          const SizedBox(height: 18),
          _StatsStrip(status: status),
        ],
      ],
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.ring,
    required this.busy,
    required this.onTap,
  });

  final Color ring;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = ring == AppColors.connected;
    return Semantics(
      button: true,
      label: 'Переключить подключение',
      // Stays tappable while busy so the user can always cancel a connect /
      // reconnect that's spinning (e.g. an unreachable server).
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [ring.withValues(alpha: 0.22), Colors.transparent],
              radius: 0.85,
            ),
            border: Border.all(color: ring, width: 2.5),
            boxShadow: [
              if (on)
                BoxShadow(
                  color: ring.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: ring,
                    ),
                  )
                : Icon(Icons.power_settings_new_rounded, size: 60, color: ring),
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status, required this.selected});

  final VpnStatus status;
  final VpnTunnel? selected;

  @override
  Widget build(BuildContext context) {
    final (title, sub) = switch (status.state) {
      VpnConnectionState.connected => (
          'Подключено',
          selected != null
              ? '${selected!.name} · трафик защищён'
              : 'Трафик защищён',
        ),
      VpnConnectionState.connecting => ('Подключение…', 'Поднимаю туннель'),
      VpnConnectionState.reconnecting => (
          'Переподключение…',
          'Восстанавливаю связь',
        ),
      VpnConnectionState.error => (
          'Ошибка',
          status.errorMessage?.isNotEmpty == true
              ? status.errorMessage!
              : 'Не удалось подключиться',
        ),
      VpnConnectionState.disconnected => (
          'Отключено',
          selected != null
              ? '${selected!.name} · нажми, чтобы подключиться'
              : 'Добавь профиль, чтобы начать',
        ),
    };

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: cardDecoration(),
      child: Row(
        children: [
          _Metric(
            icon: Icons.south_rounded,
            label: 'Принято',
            value: formatBytes(status.rxBytes),
          ),
          _Divider(),
          _Metric(
            icon: Icons.north_rounded,
            label: 'Отправлено',
            value: formatBytes(status.txBytes),
          ),
          _Divider(),
          _Metric(
            icon: Icons.handshake_outlined,
            label: 'Рукопожатие',
            value: formatHandshakeAgo(status.lastHandshakeEpochSeconds),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.hairline);
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
