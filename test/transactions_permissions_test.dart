import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/daos/pos_dao.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/models/cart_item.dart';
import 'package:pos/presentation/screens/transactions_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/auth/auth_guard.dart';
import 'package:pos/presentation/widgets/counter/checkout_dialog.dart';
import 'package:pos/presentation/widgets/transactions/export_transactions_dialog.dart';
import 'package:pos/presentation/widgets/transactions/transaction_detail_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'cashier-emp-001',
      'current_employee_role': 'Cashier',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  Future<void> seedMultiEmployeeTransactions(AppDatabase db) async {
    await DatabaseSeeder.seedIfEmpty(db);

    // Create a transaction for cashier-emp-001
    await db.into(db.salesTransactions).insert(
      SalesTransactionsCompanion(
        id: const drift.Value('tx-emp1-001'),
        companyId: const drift.Value('default-company-001'),
        storeId: const drift.Value('default-store-001'),
        cashRegisterId: const drift.Value('default-reg-001'),
        employeeId: const drift.Value('cashier-emp-001'),
        invoiceNo: const drift.Value('INV-EMP1-001'),
        subtotal: const drift.Value(100.0),
        discountTotal: const drift.Value(0.0),
        taxTotal: const drift.Value(12.0),
        grandTotal: const drift.Value(112.0),
        transactionDatetime: drift.Value(DateTime.now().subtract(const Duration(minutes: 10))),
        status: const drift.Value('completed'),
      ),
    );

    // Create a transaction for a different employee (default-emp-001)
    await db.into(db.salesTransactions).insert(
      SalesTransactionsCompanion(
        id: const drift.Value('tx-emp2-002'),
        companyId: const drift.Value('default-company-001'),
        storeId: const drift.Value('default-store-001'),
        cashRegisterId: const drift.Value('default-reg-001'),
        employeeId: const drift.Value('default-emp-001'),
        invoiceNo: const drift.Value('INV-OTHER-002'),
        subtotal: const drift.Value(200.0),
        discountTotal: const drift.Value(0.0),
        taxTotal: const drift.Value(24.0),
        grandTotal: const drift.Value(224.0),
        transactionDatetime: drift.Value(DateTime.now().subtract(const Duration(minutes: 5))),
        status: const drift.Value('completed'),
      ),
    );
  }

  group('Sales & Receipts Permissions Enforcement', () {
    testWidgets('transactionsViewOwn vs transactionsViewAll: Ledger filters correctly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await seedMultiEmployeeTransactions(db);

      // 1. Grant ONLY transactionsViewOwn
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TransactionsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Sees own transaction, but NOT other employee's transaction
      expect(find.text('INV-EMP1-001'), findsOneWidget);
      expect(find.text('INV-OTHER-002'), findsNothing);

      // 2. Grant transactionsViewAll
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
        PosPermissions.transactionsViewAll,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TransactionsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Sees both transactions
      expect(find.text('INV-EMP1-001'), findsOneWidget);
      expect(find.text('INV-OTHER-002'), findsOneWidget);

      await db.close();
    });

    testWidgets('Neither view permission: Ledger shows empty state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await seedMultiEmployeeTransactions(db);

      // Revoke all view permissions
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', <String>{});

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TransactionsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('INV-EMP1-001'), findsNothing);
      expect(find.text('INV-OTHER-002'), findsNothing);

      await db.close();
    });

    testWidgets('transactionsExport: Export button in header is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await seedMultiEmployeeTransactions(db);

      // 1. Grant transactionsExport
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
        PosPermissions.transactionsExport,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TransactionsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_transactions_button')), findsOneWidget);

      // 2. Revoke transactionsExport
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TransactionsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_transactions_button')), findsNothing);

      await db.close();
    });

    testWidgets('ExportTransactionsDialog enforces transactionsExport permission', (WidgetTester tester) async {
      // 1. Without permission -> Access Denied
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
      });

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ExportTransactionsDialog(
            filteredTransactions: [],
            allTransactions: [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);

      // 2. With permission -> Dialog form
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
        PosPermissions.transactionsExport,
      });

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ExportTransactionsDialog(
            filteredTransactions: [],
            allTransactions: [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Export Transactions'), findsOneWidget);
    });

    testWidgets('transactionsReceipt & transactionsRefund in TransactionDetailDialog', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedMultiEmployeeTransactions(db);

      final detail = TransactionDetail(
        transaction: SalesTransaction(
          id: 'tx-emp1-001',
          companyId: 'default-company-001',
          storeId: 'default-store-001',
          cashRegisterId: 'default-reg-001',
          invoiceNo: 'INV-EMP1-001',
          subtotal: 100.0,
          discountTotal: 0.0,
          taxTotal: 12.0,
          grandTotal: 112.0,
          transactionDatetime: DateTime.now(),
          status: 'completed',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDeleted: false,
        ),
        items: [],
        tenders: [],
      );

      // 1. Both permissions granted -> Both buttons visible
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
        PosPermissions.transactionsReceipt,
        PosPermissions.transactionsRefund,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TransactionDetailDialog(transactionDetail: detail, db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_share_receipt_button')), findsOneWidget);
      expect(find.byKey(const Key('transaction_refund_button')), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // 2. Revoke transactionsRefund -> Only Share Receipt is visible
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
        PosPermissions.transactionsReceipt,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TransactionDetailDialog(transactionDetail: detail, db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_share_receipt_button')), findsOneWidget);
      expect(find.byKey(const Key('transaction_refund_button')), findsNothing);

      // 3. Revoke both -> Both buttons hidden, Close expands
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TransactionDetailDialog(transactionDetail: detail, db: db),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_share_receipt_button')), findsNothing);
      expect(find.byKey(const Key('transaction_refund_button')), findsNothing);
      expect(find.text('Close'), findsOneWidget);

      await db.close();
    });

    testWidgets('transactionsReceipt in CheckoutDialog: Share Receipt visible when granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final products = await db.select(db.products).get();
      final product = products.first;

      final items = [
        CartItem(
          product: product,
          quantity: 1,
          unitPrice: 100.0,
        ),
      ];

      // Grant transactionsReceipt
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.posView,
        PosPermissions.posSell,
        PosPermissions.transactionsReceipt,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CheckoutDialog(
            db: db,
            items: items,
            subtotal: 100.0,
            discountTotal: 0.0,
            taxTotal: 12.0,
            grandTotal: 112.0,
            onSaleCompleted: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Enter payment and complete sale
      await tester.enterText(find.byKey(const Key('amount_tendered_input')), '200');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('share_receipt_button')), findsOneWidget);
      expect(find.byKey(const Key('next_sale_button')), findsOneWidget);

      await db.close();
    });

    testWidgets('transactionsReceipt in CheckoutDialog: Share Receipt hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final products = await db.select(db.products).get();
      final product = products.first;

      final items = [
        CartItem(
          product: product,
          quantity: 1,
          unitPrice: 100.0,
        ),
      ];

      // Revoke transactionsReceipt
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.posView,
        PosPermissions.posSell,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CheckoutDialog(
            db: db,
            items: items,
            subtotal: 100.0,
            discountTotal: 0.0,
            taxTotal: 12.0,
            grandTotal: 112.0,
            onSaleCompleted: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('amount_tendered_input')), '200');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('share_receipt_button')), findsNothing);
      expect(find.byKey(const Key('next_sale_button')), findsOneWidget);

      await db.close();
    });

    testWidgets('AuthGuard anyOfPermissions authorizes correctly for transactions view', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());

      // 1. With transactionsViewAll -> Authorized
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewAll,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AuthGuard(
            db: db,
            anyOfPermissions: const [
              PosPermissions.transactionsViewOwn,
              PosPermissions.transactionsViewAll,
            ],
            featureName: 'Sales & Receipts',
            child: const Text('Authorized Transactions Content'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Authorized Transactions Content'), findsOneWidget);

      // 2. With transactionsViewOwn -> Authorized
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', {
        PosPermissions.transactionsViewOwn,
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AuthGuard(
            db: db,
            anyOfPermissions: const [
              PosPermissions.transactionsViewOwn,
              PosPermissions.transactionsViewAll,
            ],
            featureName: 'Sales & Receipts',
            child: const Text('Authorized Transactions Content'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Authorized Transactions Content'), findsOneWidget);

      // 3. Without either -> Access Denied barrier
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-emp-001', <String>{});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AuthGuard(
            db: db,
            anyOfPermissions: const [
              PosPermissions.transactionsViewOwn,
              PosPermissions.transactionsViewAll,
            ],
            featureName: 'Sales & Receipts',
            child: const Text('Authorized Transactions Content'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Authorized Transactions Content'), findsNothing);
      expect(find.text('Access Denied'), findsOneWidget);

      await db.close();
    });
  });
}
