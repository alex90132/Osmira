import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_controller.dart';

/// Displayed at the bottom of Settings, vk-bridge style. Keep in sync with the
/// `version:` field in pubspec.yaml.
const _appVersionLabel = 'Osmira 0.1.1';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
        ),
        children: [
          _SectionTitle('Маскировка'),
          SwitchListTile(
            value: settings.normalizeMtu,
            onChanged: controller.setNormalizeMtu,
            title: const Text('Нормализовать MTU (1500)'),
            subtitle: const Text(
              'Скрывает характерное для WireGuard снижение MTU/MSS. '
              'Может немного снизить надёжность на некоторых сетях.',
            ),
          ),
          SwitchListTile(
            value: settings.autoReconnect,
            onChanged: controller.setAutoReconnect,
            title: const Text('Автопереподключение'),
            subtitle: const Text(
              'Восстанавливать туннель при зависании или смене сети.',
            ),
          ),
          const Divider(height: 32),
          _SectionTitle('Список приложений'),
          SwitchListTile(
            value: settings.showSystemApps,
            onChanged: controller.setShowSystemApps,
            title: const Text('Показывать системные приложения'),
            subtitle: const Text('В выборе приложений для split-tunnel.'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _appVersionLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

