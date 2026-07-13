import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di.dart';
import '../state/import_controller.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.initialSource});

  /// Pre-fills the config field, e.g. when opened from a tapped `.vpn` file.
  final String? initialSource;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _source = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSource?.trim();
    if (initial != null && initial.isNotEmpty) _source.text = initial;
  }

  @override
  void dispose() {
    _source.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // .vpn / .conf payloads are UTF-8 text (a `vpn://` URI or wg-quick); the
    // native SAF picker reads and returns the text directly.
    final picked = await ref.read(importLinkDataSourceProvider).pickFile();
    if (picked == null || !mounted) return;
    setState(() {
      _source.text = picked.text;
      if (_name.text.isEmpty) {
        _name.text = picked.name.replaceAll(RegExp(r'\.(vpn|conf)$'), '');
      }
    });
  }

  Future<void> _import() async {
    final source = _source.text.trim();
    if (source.isEmpty) return;
    final name = _name.text.trim();
    final tunnel = await ref
        .read(importControllerProvider.notifier)
        .import(source, name: name.isEmpty ? null : name);
    if (tunnel != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final isBusy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Добавить профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // The native document picker is currently wired for Android only;
          // elsewhere users paste the config or open a .vpn file directly.
          if (Theme.of(context).platform == TargetPlatform.android) ...[
            OutlinedButton.icon(
              onPressed: isBusy ? null : _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Выбрать .vpn / .conf файл'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название (необязательно)',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _source,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: 'vpn:// … или текст wg-quick',
              alignLabelWithHint: true,
            ),
          ),
          if (state case AsyncError(:final error)) ...[
            const SizedBox(height: 12),
            Text(
              '$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isBusy ? null : _import,
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done),
            label: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }
}
