import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/reports_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/auth/auth_guard.dart';
import 'package:pos/presentation/widgets/reports/add_expense_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const testEmpId = 'staff-reports-001';

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

  group('Reports & Analysis Permissions Enforcement', () {
    testWidgets('reportsView: AuthGuard blocks access when revoked and allows when granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Revoke reportsView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, <String>{});

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.reportsView,
            featureName: 'Reports & Analytics',
            child: ReportsView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Return to POS Counter'), findsOneWidget);
      expect(find.byType(ReportsView), findsNothing);

      // 2. Grant reportsView
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthGuard(
            db: db,
            requiredPermission: PosPermissions.reportsView,
            featureName: 'Reports & Analytics',
            child: ReportsView(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsNothing);
      expect(find.byType(ReportsView), findsOneWidget);

      await db.close();
    });

    testWidgets('reportsExport: "Export Excel" button visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant reportsView and reportsExport
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
        PosPermissions.reportsExport,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_report_button')), findsOneWidget);
      expect(find.text('Export Excel'), findsOneWidget);

      // 2. Revoke reportsExport
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_report_button')), findsNothing);
      expect(find.text('Export Excel'), findsNothing);

      await db.close();
    });

    testWidgets('reportsPlFinancials: COGS, margins, and Net Profit visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant reportsPlFinancials
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
        PosPermissions.reportsPlFinancials,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // P&L Header and tab
      expect(find.text('Profit & Loss (P&L) Statement'), findsOneWidget);
      expect(find.text('Sales & Profit'), findsOneWidget);

      // Sensitive metrics
      expect(find.text('COGS (Cost of Goods)'), findsOneWidget);
      expect(find.text('Gross Profit'), findsWidgets);
      expect(find.text('Net Profit'), findsOneWidget);
      expect(find.textContaining('Profit: ₱'), findsWidgets);

      // 2. Revoke reportsPlFinancials
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Title changed to Sales Revenue Overview
      expect(find.text('Sales Revenue Overview'), findsOneWidget);
      expect(find.text('Profit & Loss (P&L) Statement'), findsNothing);
      expect(find.text('Sales Overview'), findsOneWidget);

      // Sensitive financial metrics are completely hidden
      expect(find.text('COGS (Cost of Goods)'), findsNothing);
      expect(find.text('Gross Profit'), findsNothing);
      expect(find.text('Net Profit'), findsNothing);
      expect(find.textContaining('Profit: ₱'), findsNothing);

      // General sales totals remain visible
      expect(find.text('Total Sales (Net)'), findsOneWidget);
      expect(find.text('Gross Sales'), findsOneWidget);

      await db.close();
    });

    testWidgets('reportsExpenses: Expenses card & Add Expense button visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant reportsExpenses
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
        PosPermissions.reportsExpenses,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_expense_button')), findsOneWidget);
      expect(find.byKey(const Key('expenses_log_card')), findsOneWidget);

      // 2. Revoke reportsExpenses
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_expense_button')), findsNothing);
      expect(find.byKey(const Key('expenses_log_card')), findsNothing);

      await db.close();
    });

    testWidgets('AddExpenseDialog: Accessible when reportsExpenses is granted, Access Denied when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Granted
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsExpenses,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddExpenseDialog(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Record Store Expense'), findsOneWidget);
      expect(find.text('Access Denied'), findsNothing);

      // 2. Revoked
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, <String>{});

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddExpenseDialog(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('You do not have permission to record store expenses.'), findsOneWidget);
      expect(find.text('Record Store Expense'), findsNothing);

      await db.close();
    });

    testWidgets('reportsStaffAudit: "Sales by Staff" leaderboard card visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant reportsStaffAudit
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
        PosPermissions.reportsStaffAudit,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff_sales_card')), findsOneWidget);
      expect(find.text('Sales by Staff (Sold By)'), findsOneWidget);

      // 2. Revoke reportsStaffAudit
      await PermissionService.instance.setEmployeeCustomPermissions(testEmpId, {
        PosPermissions.reportsView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ReportsView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff_sales_card')), findsNothing);
      expect(find.text('Sales by Staff (Sold By)'), findsNothing);

      await db.close();
    });
  });
}
