import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/screens/counter_view.dart';
import 'package:pos/presentation/widgets/counter/sync_status_badge.dart';

void main() {
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({
      'company_id': 'comp-test-001',
      'store_id': 'store-test-001',
      'register_id': 'reg-test-001',
      'current_employee_id': 'emp-test-001',
      'current_employee_role': 'Admin',
      'employee_name': 'Test Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init();
  });

  group('Sync & Cloud Connectivity Indicator Tests', () {
    testWidgets('SyncStatusBadge renders Synced when syncQueue is empty', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SyncStatusBadge(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('counter_sync_status_badge')), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);

      await db.close();
    });

    testWidgets('SyncStatusBadge reactively updates to Pending when items queued in syncQueue', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SyncStatusBadge(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Synced'), findsOneWidget);

      // Queue an outbox sync transaction
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          targetTable: 'sales_transactions',
          recordId: 'sale-uuid-001',
          action: 'INSERT',
          payload: '{"id": "sale-uuid-001"}',
          status: const Value('pending'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Pending'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

      // Add a second sync item
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          targetTable: 'inventories',
          recordId: 'inv-uuid-002',
          action: 'UPDATE',
          payload: '{"id": "inv-uuid-002"}',
          status: const Value('pending'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 Pending'), findsOneWidget);

      await db.close();
    });

    testWidgets('SyncStatusBadge reactively updates to Failed when errors occur in syncQueue', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SyncStatusBadge(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Insert failed sync item
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          targetTable: 'tender_payments',
          recordId: 'pay-uuid-003',
          action: 'INSERT',
          payload: '{"id": "pay-uuid-003"}',
          status: const Value('failed'),
          errorMessage: const Value('SocketException: Connection refused'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Failed'), findsOneWidget);
      expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);

      await db.close();
    });

    testWidgets('Tapping SyncStatusBadge opens SyncDetailsDialog with queue details', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // Insert sample pending item
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          targetTable: 'sales_transactions',
          recordId: 'sale-uuid-999',
          action: 'INSERT',
          payload: '{"id": "sale-uuid-999"}',
          status: const Value('pending'),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SyncStatusBadge(db: db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap the badge
      await tester.tap(find.byKey(const Key('counter_sync_status_badge')));
      await tester.pumpAndSettle();

      // Verify SyncDetailsDialog opened
      expect(find.text('Cloud Sync & Connectivity'), findsOneWidget);
      expect(find.text('Outbox Queue Activity'), findsOneWidget);
      expect(find.text('Sale Transaction'), findsOneWidget);
      expect(find.text('INSERT'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.byKey(const Key('sync_now_action_button')), findsOneWidget);

      // Tap Sync Now
      await tester.tap(find.byKey(const Key('sync_now_action_button')));
      await tester.pumpAndSettle();

      // In tests without Supabase instance, it gracefully reports local-only mode
      expect(
        find.text('Cloud connection not configured (Local-only database mode)'),
        findsOneWidget,
      );

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Cloud Sync & Connectivity'), findsNothing);

      await db.close();
    });

    testWidgets('SyncStatusBadge integrated in CounterView header renders without overflow on 360x640 mobile', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CounterView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify SyncStatusBadge is present in CounterView header
      expect(find.byKey(const Key('counter_sync_status_badge')), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);

      await db.close();
    });
  });
}
