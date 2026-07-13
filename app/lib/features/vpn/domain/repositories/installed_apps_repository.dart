import '../entities/installed_app.dart';

/// Provides the list of launchable apps for the split-tunnelling picker.
abstract interface class InstalledAppsRepository {
  /// Returns launchable apps sorted by label. [includeSystem] controls whether
  /// pre-installed system apps are included.
  Future<List<InstalledApp>> getInstalledApps({bool includeSystem = false});
}
