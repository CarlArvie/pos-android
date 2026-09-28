import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/staff/add_staff_dialog.dart';
import 'package:pos/presentation/screens/staff/edit_pin_dialog.dart';
import 'package:pos/presentation/screens/staff/staff_management_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/auth/auth_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const testEmpId = 'staff-tester-001';

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

  group('Staff & Cashier Permissions Enforcement', () {
    testWidgets('staffView: AuthGuard blocks access when revoked, allows access when granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke staffView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, <String>{});
      expect(PermissionService.instance.canAccessTab(6), isFalse);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.staffView,
            featureName: 'Staff & Cashier',
            child: StaffManagementView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Return to POS Counter'), findsOneWidget);
      expect(find.byType(StaffManagementView), findsNothing);

      // 2. Grant staffView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });
      expect(PermissionService.instance.canAccessTab(6), isTrue);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.staffView,
            featureName: 'Staff & Cashier',
            child: StaffManagementView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsNothing);
      expect(find.byType(StaffManagementView), findsOneWidget);
      expect(find.text('Staff & Permissions'), findsOneWidget);

      await db.close();
    });

    testWidgets('staffManage: "Add Staff" button and management controls visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant staffView and staffManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
        PosPermissions.staffManage,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Add Staff button must be visible
      expect(find.byKey(const Key('add_staff_button')), findsOneWidget);
      expect(find.text('Add Staff'), findsOneWidget);

      // Active switches and Change Role menus must be visible on non-admin staff
      expect(find.byKey(const Key('active_switch_cashier-emp-001')), findsOneWidget);
      expect(find.byKey(const Key('change_role_button_cashier-emp-001')), findsOneWidget);

      // 2. Revoke staffManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Add Staff button must be completely hidden
      expect(find.byKey(const Key('add_staff_button')), findsNothing);
      expect(find.text('Add Staff'), findsNothing);

      // Active switches and Change Role menus must be completely hidden
      expect(find.byKey(const Key('active_switch_cashier-emp-001')), findsNothing);
      expect(find.byKey(const Key('change_role_button_cashier-emp-001')), findsNothing);

      await db.close();
    });

    testWidgets('staffManage: AddStaffDialog checks permission properly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke staffManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: AddStaffDialog(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('You do not have permission to create staff accounts.'), findsOneWidget);

      // 2. Grant staffManage
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
        PosPermissions.staffManage,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: AddStaffDialog(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsNothing);
      expect(find.text('Add Staff Member'), findsOneWidget);
      expect(find.text('First Name'), findsOneWidget);

      await db.close();
    });

    testWidgets('staffPermissions: "Roles & Permissions" tab and employee overrides button visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke staffPermissions (only grant staffView)
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Golden Rule: Roles & Permissions tab and TabBar must be completely hidden!
      expect(find.byKey(const Key('staff_tabs_bar')), findsNothing);
      expect(find.byKey(const Key('roles_and_permissions_tab')), findsNothing);
      expect(find.textContaining('Roles & Permissions'), findsNothing);
      // No employee override buttons
      expect(find.byKey(const Key('permissions_button_cashier-emp-001')), findsNothing);

      // 2. Grant staffPermissions
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
        PosPermissions.staffPermissions,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // TabBar and Roles & Permissions tab must now be visible
      expect(find.byKey(const Key('staff_tabs_bar')), findsOneWidget);
      expect(find.byKey(const Key('roles_and_permissions_tab')), findsOneWidget);
      expect(find.textContaining('Roles & Permissions'), findsOneWidget);
      expect(find.byKey(const Key('permissions_button_cashier-emp-001')), findsOneWidget);

      await db.close();
    });

    testWidgets('staffResetPin: "Reset PIN" button visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke staffResetPin
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Reset PIN button must be completely hidden
      expect(find.byKey(const Key('reset_pin_button_cashier-emp-001')), findsNothing);
      expect(find.text('Reset PIN'), findsNothing);

      // 2. Grant staffResetPin
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
        PosPermissions.staffResetPin,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: StaffManagementView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Reset PIN button must now be visible
      expect(find.byKey(const Key('reset_pin_button_cashier-emp-001')), findsOneWidget);
      expect(find.text('Reset PIN'), findsWidgets);

      await db.close();
    });

    testWidgets('staffResetPin: EditPinDialog allows updating PIN when granted and blocks when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      final employees = await db.posDao.getEmployeesForStore('default-store-001');
      final cashier = employees.firstWhere((e) => e.position.toLowerCase() == 'cashier');

      // 1. Revoke staffResetPin
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: EditPinDialog(db: db, employee: cashier)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('You do not have permission to reset employee PINs.'), findsOneWidget);

      // 2. Grant staffResetPin
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.staffView,
        PosPermissions.staffResetPin,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: EditPinDialog(db: db, employee: cashier)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsNothing);
      expect(find.text('Reset PIN for ${cashier.firstName}'), findsOneWidget);

      // Enter new PIN and update
      await tester.enterText(find.byType(TextFormField), '9876');
      await tester.tap(find.text('Update PIN'));
      await tester.pumpAndSettle();

      // Verify PIN updated in database
      final updatedCashier = await (db.select(db.employees)..where((e) => e.id.equals(cashier.id))).getSingleOrNull();
      expect(updatedCashier?.pinCode, '9876');

      await db.close();
    });
  });
}
