import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/settings_controller.dart';
import '../../domain/entities/app_routing.dart';
import '../../domain/entities/installed_app.dart';
import '../state/vpn_providers.dart';

/// Global split-tunnel picker. The selection applies to every profile (it's a
/// device-wide policy), not to one config — matching the vk-bridge client.
class AppRoutingScreen extends ConsumerStatefulWidget {
  const AppRoutingScreen({super.key});

  @override
  ConsumerState<AppRoutingScreen> createState() => _AppRoutingScreenState();
}

class _AppRoutingScreenState extends ConsumerState<AppRoutingScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routing = ref.watch(settingsProvider).routing;
    final controller = ref.read(settingsProvider.notifier);
    final appsAsync = ref.watch(installedAppsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Приложения')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<AppRoutingMode>(
              segments: const [
                ButtonSegment(
                  value: AppRoutingMode.all,
                  label: Text('Все'),
                  icon: Icon(Icons.public_rounded),
                ),
                ButtonSegment(
                  value: AppRoutingMode.exclude,
                  label: Text('Кроме'),
                  icon: Icon(Icons.block_rounded),
                ),
                ButtonSegment(
                  value: AppRoutingMode.include,
                  label: Text('Только'),
                  icon: Icon(Icons.check_rounded),
                ),
              ],
              selected: {routing.mode},
              onSelectionChanged: (s) => controller.setRoutingMode(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              _hintForMode(routing.mode),
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (routing.mode == AppRoutingMode.all)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Весь трафик идёт через туннель.\n'
                    'Это наименее заметный режим для систем детекта.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              // No bottom padding: the list's fade band butts directly against
              // the field so rows dissolve right as they slide under it.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Поиск приложений',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            Expanded(
              child: _TopFade(
                child: appsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (apps) => _AppList(
                    apps: _filter(apps),
                    selected: routing.packages,
                    onToggle: controller.toggleRoutingApp,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<InstalledApp> _filter(List<InstalledApp> apps) {
    if (_query.isEmpty) return apps;
    return apps
        .where((a) =>
            a.label.toLowerCase().contains(_query) ||
            a.packageName.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  static String _hintForMode(AppRoutingMode mode) => switch (mode) {
        AppRoutingMode.all => 'Весь трафик через VPN.',
        AppRoutingMode.exclude =>
          'Выбранные приложения пойдут напрямую, минуя VPN.',
        AppRoutingMode.include =>
          'Только выбранные приложения пойдут через VPN.',
      };
}

/// Fades the top edge of its child to transparent over a fixed band, so the
/// scrolling app list dissolves into the black background under the search
/// field instead of being hard-clipped. Uses [BlendMode.dstIn] so only alpha
/// is affected (the gradient's colour is irrelevant, just its opacity).
class _TopFade extends StatelessWidget {
  const _TopFade({required this.child});

  static const _fadeHeight = 32.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frac = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? (_fadeHeight / constraints.maxHeight).clamp(0.0, 0.5)
            : 0.0;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.black],
            stops: [0.0, frac],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({
    required this.apps,
    required this.selected,
    required this.onToggle,
  });

  final List<InstalledApp> apps;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Flush to the search field above: rows dissolve into black right as they
      // slide up under the field (the fade band starts at the list's top edge).
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
      ),
      itemCount: apps.length,
      // Fixed extent lets the list skip per-item layout → smoother scrolling.
      itemExtent: 64,
      itemBuilder: (_, i) {
        final app = apps[i];
        return CheckboxListTile(
          value: selected.contains(app.packageName),
          onChanged: (_) => onToggle(app.packageName),
          secondary: SizedBox(
            width: 40,
            height: 40,
            child: app.icon != null
                ? Image.memory(
                    app.icon!,
                    width: 40,
                    height: 40,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  )
                : const Icon(Icons.android_rounded),
          ),
          title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            app.packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        );
      },
    );
  }
}
