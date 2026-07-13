import 'dart:async';

import 'package:flutter/services.dart';

/// A file the user picked via the native document picker.
class PickedConfigFile {
  const PickedConfigFile({required this.name, required this.text});

  final String name;
  final String text;
}

/// Receives config payloads handed to the app from the OS — a tapped `.vpn`
/// file or a `vpn://` deep link — via the native `osmi.awg2/import` channel.
///
/// Emits the launch payload (if the app was started by opening a file) followed
/// by any payloads delivered while running. On platforms without the native
/// side (e.g. Windows for now) it simply stays silent instead of throwing.
class ImportLinkDataSource {
  ImportLinkDataSource({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_name) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _name = 'osmi.awg2/import';

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();
  bool _initialChecked = false;

  Stream<String> links() {
    if (!_initialChecked) {
      _initialChecked = true;
      unawaited(_emitInitial());
    }
    return _controller.stream;
  }

  Future<void> _emitInitial() async {
    try {
      final payload = await _channel.invokeMethod<String>('getInitial');
      _push(payload);
    } on MissingPluginException {
      // No native import bridge on this platform; ignore.
    } catch (_) {
      // Non-fatal: a bad launch intent shouldn't crash startup.
    }
  }

  /// Opens the OS document picker (Android SAF) and returns the selected
  /// file's name + UTF-8 text. Returns null if the user cancels or the native
  /// picker isn't available on this platform (e.g. desktop for now).
  Future<PickedConfigFile?> pickFile() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('pickFile');
      if (res == null) return null;
      final text = (res['text'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      return PickedConfigFile(
        name: (res['name'] as String?) ?? '',
        text: text,
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onImport') {
      _push(call.arguments as String?);
    }
    return null;
  }

  void _push(String? payload) {
    final value = payload?.trim();
    if (value != null && value.isNotEmpty) _controller.add(value);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
