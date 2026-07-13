import '../../domain/entities/installed_app.dart';
import '../../domain/repositories/installed_apps_repository.dart';
import '../datasources/native_vpn_datasource.dart';

class InstalledAppsRepositoryImpl implements InstalledAppsRepository {
  InstalledAppsRepositoryImpl(this._native);

  final NativeVpnDataSource _native;

  @override
  Future<List<InstalledApp>> getInstalledApps({bool includeSystem = false}) =>
      _native.listApps(includeSystem: includeSystem);
}
