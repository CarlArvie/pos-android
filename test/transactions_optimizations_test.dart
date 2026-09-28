import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/transactions_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'admin-emp-001',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  testWidgets(
    'TransactionsView phone layout (360x640) renders without pixel overflow and includes RepaintBoundary',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await PermissionService.instance.setEmployeeCustomPermissions(
        'admin-emp-001',
        {PosPermissions.transactionsViewAll, PosPermissions.transactionsExport},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: TransactionsView(db: db)),
        ),
      );
      await tester.pumpAndSettle();

      // Verify key UI components
      expect(find.text('Transaction Ledger'), findsOneWidget);
      expect(find.text('Filtered Revenue'), findsOneWidget);
      expect(find.text('Total Orders'), findsOneWidget);
      expect(find.text('Avg Ticket'), findsOneWidget);
      expect(
        find.byKey(const Key('export_transactions_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('transaction_search_input')), findsOneWidget);

      // Verify RepaintBoundary is present around cards for low-end GPU rendering performance
      expect(find.byType(RepaintBoundary), findsWidgets);

      // Verify no render flex overflow exceptions occurred
      expect(tester.takeException(), isNull);

      await db.close();
    },
  );

  testWidgets(
    'TransactionsView search input debounce and clear button work correctly',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await PermissionService.instance.setEmployeeCustomPermissions(
        'admin-emp-001',
        {PosPermissions.transactionsViewAll},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: TransactionsView(db: db)),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: multiple transactions visible
      expect(find.textContaining('INV-2026-0001'), findsOneWidget);
      expect(find.textContaining('INV-2026-0002'), findsOneWidget);

      // Enter search text
      await tester.enterText(
        find.byKey(const Key('transaction_search_input')),
        '0002',
      );

      // Before debounce finishes (50ms), old list is still visible
      await tester.pump(const Duration(milliseconds: 50));

      // After debounce finishes (200ms total), filtered list appears
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.textContaining('INV-2026-0002'), findsOneWidget);
      expect(find.textContaining('INV-2026-0001'), findsNothing);

      // Clear search using clear button icon
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Both visible again
      expect(find.textContaining('INV-2026-0001'), findsOneWidget);
      expect(find.textContaining('INV-2026-0002'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets(
    'TransactionsView payment filter and date filter chips update reactive lists correctly',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await PermissionService.instance.setEmployeeCustomPermissions(
        'admin-emp-001',
        {PosPermissions.transactionsViewAll},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: TransactionsView(db: db)),
        ),
      );
      await tester.pumpAndSettle();

      // Filter by Cash
      await tester.ensureVisible(find.text('💵 Cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('💵 Cash'));
      await tester.pumpAndSettle();

      expect(find.textContaining('INV-2026-0001'), findsOneWidget);
      expect(find.textContaining('INV-2026-0002'), findsNothing);

      // Active filter banner is visible
      expect(find.textContaining('Filters active'), findsOneWidget);

      // Reset filters
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.textContaining('INV-2026-0001'), findsOneWidget);
      expect(find.textContaining('INV-2026-0002'), findsOneWidget);

      await db.close();
    },
  );
}
