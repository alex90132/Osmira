import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import 'settings_controller.dart';

/// Displayed at the bottom of Settings, vk-bridge style. Keep in sync with the
/// `version:` field in pubspec.yaml.
const _appVersionLabel = 'Osmira 0.1.4';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewPaddingOf(context).bottom + 24,
        ),
        children: [
          const _SectionTitle('Подключение'),
          _SettingsCard(
            children: [
              _SettingSwitch(
                value: settings.autoReconnect,
                onChanged: controller.setAutoReconnect,
                title: 'Автопереподключение',
                subtitle:
                    'Восстанавливать туннель при зависании или смене сети.',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Список приложений'),
          _SettingsCard(
            children: [
              _SettingSwitch(
                value: settings.showSystemApps,
                onChanged: controller.setShowSystemApps,
                title: 'Показывать системные приложения',
                subtitle: 'В выборе приложений для split-tunnel.',
              ),
            ],
          ),
          const SizedBox(height: 32),
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

/// Muted uppercase header, matching the "ПРОФИЛИ" label on the home screen.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// Card surface identical to the profile cards / stats strip on the home
/// screen, so Settings doesn't read as a different app.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A switch row with the app's single blue accent for the "on" state, instead
/// of the default Material seed colours that looked out of place.
class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.accent,
      inactiveThumbColor: Colors.white.withValues(alpha: 0.85),
      inactiveTrackColor: AppColors.surface,
      trackOutlineColor: WidgetStatePropertyAll(
        value ? AppColors.accent : AppColors.hairline,
      ),
    );
  }
}
