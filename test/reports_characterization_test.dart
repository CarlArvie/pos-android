import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/daos/pos_dao.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'default-emp-001',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('Reports Data Characterization Tests', () {
    test(
      'posDao.getSalesReportData aggregates seeded sales accurately',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await DatabaseSeeder.seedIfEmpty(db);
        final posDao = PosDao(db);

        // Record an expense
        await posDao.addExpense(
          companyId: 'default-company-001',
          storeId: 'default-store-001',
          category: 'Utilities',
          amount: 250.0,
          description: 'Test electric bill',
        );

        final report = await posDao.getSalesReportData(
          startDate: null,
          endDate: null,
        );

        expect(report.totalReceipts, greaterThanOrEqualTo(5));
        expect(report.grossSales, greaterThan(0));
        expect(report.netSales, greaterThan(0));
        expect(report.totalExpenses, 250.0);
        expect(report.paymentModes, isNotEmpty);
        expect(report.topProducts, isNotEmpty);
        expect(report.topCategories, isNotEmpty);

        await db.close();
      },
    );

    test(
      'posDao.getSalesReportData handles empty periods gracefully',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final posDao = PosDao(db);

        final pastDate = DateTime(2020, 1, 1);
        final report = await posDao.getSalesReportData(
          startDate: pastDate,
          endDate: pastDate.add(const Duration(days: 1)),
        );

        expect(report.totalReceipts, 0);
        expect(report.netSales, 0.0);
        expect(report.grossProfit, 0.0);
        expect(report.topProducts, isEmpty);
        expect(report.topCategories, isEmpty);

        await db.close();
      },
    );

    test(
      'posDao.getSalesReportData scales to > 1000 transactions without SQLite variable overflow [Verified]',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await DatabaseSeeder.seedIfEmpty(db);
        final posDao = PosDao(db);

        // Insert 1050 transactions into SQLite
        final now = DateTime.now();
        await db.batch((batch) {
          for (var i = 0; i < 1050; i++) {
            final saleId = 'bulk-sale-$i';
            batch.insert(
              db.salesTransactions,
              SalesTransactionsCompanion.insert(
                id: saleId,
                companyId: 'default-company-001',
                storeId: 'default-store-001',
                cashRegisterId: const Value('default-reg-001'),
                invoiceNo: 'INV-BULK-$i',
                transactionDatetime: Value(now),
                createdAt: Value(now),
                updatedAt: Value(now),
                subtotal: const Value(100.0),
                discountTotal: const Value(0.0),
                taxTotal: const Value(12.0),
                grandTotal: const Value(112.0),
                status: const Value('completed'),
              ),
            );
            batch.insert(
              db.transactionItems,
              TransactionItemsCompanion.insert(
                id: 'bulk-item-$i',
                companyId: 'default-company-001',
                salesTransactionId: saleId,
                quantity: const Value(1.0),
                unitPrice: const Value(100.0),
                subtotal: const Value(100.0),
              ),
            );
            batch.insert(
              db.tenderPayments,
              TenderPaymentsCompanion.insert(
                id: 'bulk-tender-$i',
                companyId: 'default-company-001',
                salesTransactionId: saleId,
                paymentMethod: 'cash',
                amount: const Value(112.0),
                amountTendered: const Value(112.0),
                changeAmount: const Value(0.0),
              ),
            );
          }
        });

        // Query across all 1050+ transactions
        final report = await posDao.getSalesReportData(
          startDate: now.subtract(const Duration(hours: 1)),
          endDate: now.add(const Duration(hours: 1)),
        );

        expect(report.totalReceipts, 1050);
        expect(report.grossSales, 1050 * 100.0);
        expect(report.netSales, 1050 * 112.0);

        await db.close();
      },
    );
  });
}
