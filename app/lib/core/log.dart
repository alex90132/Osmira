import 'package:flutter/foundation.dart';

/// Lightweight logging that is completely inert in release builds.
///
/// In debug ([kDebugMode]) each call prints a single `[Osmira/<tag>] …` line
/// via [debugPrint], which surfaces in `adb logcat` under the `flutter` tag —
/// the capture script (`scripts/capture-logs.sh`) greps for the `Osmira`
/// marker. In release every call short-circuits *before* building the message,
/// so there is zero string work and nothing is ever emitted or dispatched.
abstract final class AppLog {
  /// Log an eagerly-built [message]. Prefer [lazy] when the message needs any
  /// interpolation/allocation, so that work is skipped in release too.
  static void d(String tag, String message) {
    if (!kDebugMode) return;
    debugPrint('[Osmira/$tag] $message');
  }

  /// Log a lazily-built message: [build] only runs in debug builds.
  static void lazy(String tag, String Function() build) {
    if (!kDebugMode) return;
    debugPrint('[Osmira/$tag] ${build()}');
  }
}
