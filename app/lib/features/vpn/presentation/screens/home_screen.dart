import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../../../../app/theme.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../../settings/presentation/settings_screen.dart';
import '../../domain/entities/app_routing.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/vpn_tunnel.dart';
import '../state/connection_controller.dart';
import '../state/vpn_providers.dart';
import '../widgets/connection_panel.dart';
import '../widgets/tunnel_card.dart';
import 'app_routing_screen.dart';
import 'import_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tunnels = ref.watch(tunnelsProvider);
    // Seeded from a pre-first-frame read in main(), so the list is already
    // correct on cold start (no spinner→content pop).
    final List<VpnTunnel> initialTunnels = ref.watch(initialTunnelsProvider);
    final list = tunnels.value ?? initialTunnels;

    // Only watch the *derived* active id (stable) here, not the full status —
    // so this screen and the profile list don't rebuild on every 2s counter
    // tick. The live rx/tx panel subscribes to the full status on its own.
    final activeId = ref.watch(activeTunnelIdProvider);
    final selectedId = ref.watch(selectedTunnelIdProvider);
    final effectiveId = activeId ??
        (list.any((t) => t.id == selectedId) ? selectedId : null) ??
        (list.isNotEmpty ? list.first.id : null);
    final selected = _byId(list, effectiveId);
    final routing = ref.watch(settingsProvider.select((s) => s.routing));

    ref.listen(connectionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    });

    // A tapped .vpn file / vpn:// link opens the import screen pre-filled.
    ref.listen(incomingImportProvider, (_, next) {
      next.whenData((source) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImportScreen(initialSource: source),
          ),
        );
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Osmira'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Настройки',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        onApps: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AppRoutingScreen()),
        ),
        onAdd: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(tunnelsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const SizedBox(height: 16),
              _StatusPanel(
                selected: selected,
                onToggle: () => _toggle(context, ref, activeId != null, selected),
              ),
              const SizedBox(height: 36),
              if (tunnels case AsyncError(:final error) when list.isEmpty)
                _ErrorState(message: '$error')
              else if (list.isEmpty)
                const _EmptyState()
              else
                _ProfilesSection(
                  tunnels: list,
                  selectedId: effectiveId,
                  activeId: activeId,
                  routing: routing,
                  onSelect: (t) =>
                      ref.read(selectedTunnelIdProvider.notifier).select(t.id),
                  onRename: (t) => _rename(context, ref, t),
                  onDelete: (t) => _delete(ref, t),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static VpnTunnel? _byId(List<VpnTunnel> list, String? id) {
    if (id == null) return null;
    for (final t in list) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _toggle(
    BuildContext context,
    WidgetRef ref,
    bool isActive,
    VpnTunnel? selected,
  ) {
    final controller = ref.read(connectionControllerProvider.notifier);
    if (isActive) {
      controller.disconnect();
    } else if (selected != null) {
      controller.connect(selected);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
      );
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    VpnTunnel tunnel,
  ) async {
    final controller = TextEditingController(text: tunnel.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название профиля'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(updateTunnelProvider).call(tunnel, name: name);
    }
  }

  Future<void> _delete(WidgetRef ref, VpnTunnel tunnel) =>
      ref.read(deleteTunnelProvider).call(tunnel.id);
}

/// Isolates the live-status subscription (rx/tx/handshake tick every ~2s) to
/// just the connection panel, so the surrounding list/buttons don't rebuild.
class _StatusPanel extends ConsumerWidget {
  const _StatusPanel({required this.selected, required this.onToggle});

  final VpnTunnel? selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VpnStatus fallback = ref.watch(initialStatusProvider);
    final status = ref.watch(vpnStatusProvider).value ?? fallback;
    return ConnectionPanel(
      status: status,
      selected: selected,
      onToggle: onToggle,
    );
  }
}

class _ProfilesSection extends StatelessWidget {
  const _ProfilesSection({
    required this.tunnels,
    required this.selectedId,
    required this.activeId,
    required this.routing,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  final List<VpnTunnel> tunnels;
  final String? selectedId;
  final String? activeId;
  final AppRouting routing;
  final ValueChanged<VpnTunnel> onSelect;
  final ValueChanged<VpnTunnel> onRename;
  final ValueChanged<VpnTunnel> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'ПРОФИЛИ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final t in tunnels)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TunnelCard(
              tunnel: t,
              selected: t.id == selectedId,
              active: t.id == activeId,
              routing: routing,
              onTap: () => onSelect(t),
              onRename: () => onRename(t),
              onDelete: () => onDelete(t),
            ),
          ),
      ],
    );
  }
}

/// Bottom action bar: "Приложения" (global split-tunnel) on the left, opposite
/// "Добавить" (import) on the right — mirrors the vk-bridge layout.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onApps, required this.onAdd});

  final VoidCallback onApps;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onApps,
              icon: const Icon(Icons.apps_rounded, size: 20),
              label: const Text('Приложения'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Добавить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 52, color: AppColors.accent),
          const SizedBox(height: 16),
          const Text(
            'Пока нет профилей',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Добавь .vpn-конфиг или вставь vpn://-ссылку, чтобы начать.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(border: AppColors.error),
      child: Text(message, style: const TextStyle(color: AppColors.error)),
    );
  }
}
