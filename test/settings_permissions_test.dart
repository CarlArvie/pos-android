import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/settings/edit_company_dialog.dart';
import 'package:pos/presentation/screens/settings/edit_discount_rules_dialog.dart';
import 'package:pos/presentation/screens/settings/settings_view.dart';
import 'package:pos/presentation/screens/settings/switch_register_dialog.dart';
import 'package:pos/presentation/screens/settings/switch_store_dialog.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/admin_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'staff-settings-001',
      'current_employee_role': 'Store Manager',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('System Settings Permissions Enforcement', () {
    testWidgets('settingsCompanyProfile: Edit icons are visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant settingsView and settingsCompanyProfile
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsCompanyProfile,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Edit icons are visible
      expect(find.byIcon(Icons.edit_rounded), findsWidgets);

      // 2. Revoke settingsCompanyProfile
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Edit icons are completely hidden
      expect(find.byIcon(Icons.edit_rounded), findsNothing);

      await db.close();
    });

    testWidgets('settingsSecurityPolicy: Switch is enabled when granted, disabled when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant settingsSecurityPolicy
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsSecurityPolicy,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      final switchGranted = tester.widget<SwitchListTile>(find.byKey(const Key('settings_require_pin_switch')));
      expect(switchGranted.onChanged, isNotNull);
      expect(find.text('When locked, ask for a 4-digit PIN instead of the full password.'), findsOneWidget);

      // 2. Revoke settingsSecurityPolicy
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      final switchRevoked = tester.widget<SwitchListTile>(find.byKey(const Key('settings_require_pin_switch')));
      expect(switchRevoked.onChanged, isNull);
      expect(find.text('Security policy configuration is restricted.'), findsOneWidget);

      await db.close();
    });

    testWidgets('settingsSyncRepair: Supabase Cloud Sync tile is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant settingsSyncRepair
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsSyncRepair,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_cloud_sync_tile')), findsOneWidget);
      expect(find.text('Supabase Cloud Sync'), findsOneWidget);

      // 2. Revoke settingsSyncRepair
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_cloud_sync_tile')), findsNothing);
      expect(find.text('Supabase Cloud Sync'), findsNothing);

      await db.close();
    });

    testWidgets('settingsDiscounts: Discount Policies card is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant settingsDiscounts
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsDiscounts,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin_discount_policies_card')), findsOneWidget);
      expect(find.byKey(const Key('edit_discount_rules_button')), findsOneWidget);

      // 2. Revoke settingsDiscounts
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin_discount_policies_card')), findsNothing);
      expect(find.byKey(const Key('edit_discount_rules_button')), findsNothing);

      await db.close();
    });

    testWidgets('storesSwitch: Switch buttons on Branch and Register are visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant storesSwitch
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.storesSwitch,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('switch_store_button')), findsOneWidget);
      expect(find.byKey(const Key('switch_register_button')), findsOneWidget);

      // 2. Revoke storesSwitch
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('switch_store_button')), findsNothing);
      expect(find.byKey(const Key('switch_register_button')), findsNothing);

      await db.close();
    });

    testWidgets('EditCompanyDialog enforces settingsCompanyProfile permission', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final company = await db.posDao.getCompany('default-company-001');

      // 1. Without permission -> Access Denied
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EditCompanyDialog(db: db, company: company!)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Save'), findsNothing);

      // 2. With permission -> Edit form
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsCompanyProfile,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EditCompanyDialog(db: db, company: company)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edit Company Name'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      await db.close();
    });

    testWidgets('SwitchStoreDialog enforces storesSwitch permission', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Without permission -> Access Denied
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SwitchStoreDialog(db: db, companyId: 'default-company-001')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);

      // 2. With permission -> Stores list
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.storesSwitch,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SwitchStoreDialog(db: db, companyId: 'default-company-001')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Switch Store Branch'), findsOneWidget);

      await db.close();
    });

    testWidgets('SwitchRegisterDialog enforces storesSwitch permission', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Without permission -> Access Denied
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SwitchRegisterDialog(db: db, storeId: 'default-store-001')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);

      // 2. With permission -> Register list
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.storesSwitch,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SwitchRegisterDialog(db: db, storeId: 'default-store-001')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Switch POS Terminal'), findsOneWidget);

      await db.close();
    });

    testWidgets('EditDiscountRulesDialog enforces settingsDiscounts permission', (WidgetTester tester) async {
      // 1. Without permission -> Access Denied
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EditDiscountRulesDialog()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.byKey(const Key('save_discount_rules_button')), findsNothing);

      // 2. With permission -> Dialog form
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
        PosPermissions.settingsDiscounts,
      });

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EditDiscountRulesDialog()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Discount & Promotion Policies'), findsOneWidget);
      expect(find.byKey(const Key('save_discount_rules_button')), findsOneWidget);
    });

    testWidgets('settingsView controls Settings drawer item visibility', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());

      // 1. With settingsView -> Drawer shows Settings
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', {
        PosPermissions.settingsView,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminDrawer(db: db, currentIndex: 7),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // 2. Without settingsView -> Drawer hides Settings
      await PermissionService.instance.setEmployeeCustomPermissions('staff-settings-001', <String>{});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminDrawer(db: db, currentIndex: 0),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsNothing);

      await db.close();
    });
  });
}
