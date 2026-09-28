import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/local/database.dart';
import 'core/device_prefs.dart';
import 'core/permissions/permission_service.dart';
import 'core/constants/supabase_constants.dart';
import 'core/sync_engine.dart';
import 'presentation/screens/setup/welcome_screen.dart';
import 'presentation/screens/setup/setup_device_screen.dart';
import 'presentation/screens/setup/existing_business_login_screen.dart';
import 'presentation/screens/auth/pin_login_screen.dart';
import 'presentation/screens/main_shell_screen.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure libsqlite3.so is loaded on Android devices
  if (Platform.isAndroid) {
    try {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    } catch (e) {
      debugPrint('[Main] SQLite Android loader warning: $e');
    }
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.projectUrl,
    anonKey: SupabaseConstants.anonKey,
  );

  // Initialize shared preferences
  await DevicePrefs.init();

  // Initialize Permission Service
  await PermissionService.instance.init();

  // Initialize offline-first SQLite database via Drift
  final database = AppDatabase();

  final supabase = Supabase.instance.client;

  // Initialize Sync Engine
  final syncEngine = SyncEngine(db: database, supabase: supabase);
  syncEngine.startSyncLoop();


  // Self-heal: ensure currentEmployeeRole is populated if employee is logged in
  if (DevicePrefs.currentEmployeeId != null && DevicePrefs.currentEmployeeRole == null) {
    try {
      final emp = await (database.select(database.employees)
            ..where((e) => e.id.equals(DevicePrefs.currentEmployeeId!)))
          .getSingleOrNull();
      if (emp != null) {
        await DevicePrefs.setCurrentEmployeeRole(emp.position);
      }
    } catch (_) {}
  }

  final hasCompany = await database.posDao.hasAnyCompany();

  runApp(PosAdminApp(database: database, hasCompany: hasCompany));
}

class PosAdminApp extends StatelessWidget {
  final AppDatabase database;
  final bool hasCompany;

  const PosAdminApp({super.key, required this.database, required this.hasCompany});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final isLoggedIn = supabase.auth.currentSession != null &&
        !(supabase.auth.currentUser?.isAnonymous ?? false);

    Widget homeScreen;
    if (!hasCompany) {
      homeScreen = WelcomeScreen(db: database);
    } else if (!isLoggedIn) {
      homeScreen = ExistingBusinessLoginScreen(db: database);
    } else {
      homeScreen = DevicePrefs.isProvisioned 
          ? (DevicePrefs.requirePinForUnlock 
              ? PinLoginScreen(db: database)
              : (DevicePrefs.currentEmployeeId != null
                  ? MainShellScreen(database: database)
                  : ExistingBusinessLoginScreen(db: database)))
          : SetupDeviceScreen(db: database);
    }

    return MaterialApp(
      title: 'POS Admin Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: homeScreen,
    );
  }
}
