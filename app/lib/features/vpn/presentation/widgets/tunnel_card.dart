import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/entities/app_routing.dart';
import '../../domain/entities/vpn_tunnel.dart';

/// A saved profile row. Tapping selects it as the target of the big power
/// button; the overflow menu holds rename and delete.
class TunnelCard extends StatelessWidget {
  const TunnelCard({
    super.key,
    required this.tunnel,
    required this.selected,
    required this.active,
    required this.routing,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final VpnTunnel tunnel;
  final bool selected;
  final bool active;

  /// Global split-tunnel policy, shown as a badge (count of apps).
  final AppRouting routing;

  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final endpoint = tunnel.config.primaryEndpoint;
    final borderColor = selected ? AppColors.accent : AppColors.hairline;

    // No InkWell/ripple: a plain gesture target keeps taps instant and avoids
    // the splash-animation jank on lower-end devices.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _Leading(active: active, selected: selected),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tunnel.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    endpoint?.toString() ?? 'нет endpoint',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (tunnel.config.interface.parameters.isV2)
                        const _Tag(label: 'AWG 2.0', highlight: true)
                      else if (!tunnel.config.interface.parameters.isEmpty)
                        const _Tag(label: 'AWG'),
                      if (tunnel.config.isFullTunnel)
                        const _Tag(label: 'Full tunnel')
                      else
                        const _Tag(label: 'Split'),
                      if (routing.isSplit)
                        _Tag(
                          label: routing.mode == AppRoutingMode.exclude
                              ? 'Кроме: ${routing.packages.length}'
                              : 'Только: ${routing.packages.length}',
                          highlight: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              color: AppColors.surface,
              onSelected: (value) => switch (value) {
                'rename' => onRename(),
                'delete' => onDelete(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Переименовать'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded,
                        color: AppColors.error),
                    title: Text(
                      'Удалить',
                      style: TextStyle(color: AppColors.error),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.active, required this.selected});

  final bool active;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.connected : AppColors.accent;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Icon(
        active ? Icons.shield_rounded : Icons.shield_outlined,
        color: color,
        size: 22,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? AppColors.accent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);
    final fg = highlight ? AppColors.accent : Colors.white.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
