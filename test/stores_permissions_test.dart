import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/stores/add_store_dialog.dart';
import 'package:pos/presentation/screens/stores/stores_management_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/auth/auth_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const testEmpId = 'staff-stores-001';

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': testEmpId,
      'current_employee_role': 'Staff',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('Stores & Terminal Permissions Enforcement', () {
    testWidgets('storesView: AuthGuard blocks access when revoked and allows when granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke storesView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, <String>{});

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.storesView,
            featureName: 'Stores & Registers',
            child: StoresManagementView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Return to POS Counter'), findsOneWidget);
      expect(find.byType(StoresManagementView), findsNothing);

      // 2. Grant storesView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.storesView,
            featureName: 'Stores & Registers',
            child: StoresManagementView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsNothing);
      expect(find.byType(StoresManagementView), findsOneWidget);
      expect(find.text('Active Locations & Terminals'), findsOneWidget);
      expect(find.text('Main Retail Branch'), findsOneWidget);
      expect(find.text('ACTIVE STORE'), findsOneWidget);
      expect(find.text('ACTIVE HERE'), findsOneWidget);

      await db.close();
    });

    testWidgets('storesManage: "Add Store" button visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant storesView and storesManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesView,
        PosPermissions.storesManage,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StoresManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_store_button')), findsOneWidget);
      expect(find.text('Add Store'), findsOneWidget);

      // 2. Revoke storesManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StoresManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_store_button')), findsNothing);
      expect(find.text('Add Store'), findsNothing);

      await db.close();
    });

    testWidgets('AddStoreDialog: Accessible when storesManage is granted, Access Denied when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Granted
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesManage,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: AddStoreDialog(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Add New Store'), findsOneWidget);
      expect(find.text('Access Denied'), findsNothing);

      // 2. Revoked
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, <String>{});

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: AddStoreDialog(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('You do not have permission to create or manage store branches.'), findsOneWidget);
      expect(find.text('Add New Store'), findsNothing);

      await db.close();
    });

    testWidgets('storesSwitch: Switch terminal buttons visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // Create a second store with register
      await db.posDao.createStoreWithDefaults(
        companyId: 'default-company-001',
        storeName: 'Branch 2 BGC',
        address: 'Bonifacio High Street',
        phone: '0917-123-4567',
      );

      // 1. Grant storesView and storesSwitch
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesView,
        PosPermissions.storesSwitch,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StoresManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Branch 2 BGC'), findsOneWidget);
      expect(find.text('Switch'), findsWidgets);

      // Tap Switch button to switch to Branch 2
      final switchBtn = find.text('Switch').first;
      await tester.tap(switchBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Switched to'), findsOneWidget);

      // 2. Revoke storesSwitch
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.storesView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StoresManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Switch'), findsNothing);

      await db.close();
    });
  });
}
