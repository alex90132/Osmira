import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A launchable application installed on the device, used to build the
/// split-tunnelling selection UI.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.isSystem = false,
    this.icon,
  });

  final String packageName;
  final String label;
  final bool isSystem;

  /// Small PNG-encoded launcher icon (may be null if unavailable).
  final Uint8List? icon;

  @override
  bool operator ==(Object other) =>
      other is InstalledApp && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}
