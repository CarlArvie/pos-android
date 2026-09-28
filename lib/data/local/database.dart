import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/tenancy_tables.dart';
import 'tables/employee_tables.dart';
import 'tables/catalog_tables.dart';
import 'tables/customer_tables.dart';
import 'tables/sales_tables.dart';
import 'tables/shift_tables.dart';
import 'tables/procurement_tables.dart';
import 'tables/sync_tables.dart';
import 'daos/pos_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Companies,
    Stores,
    CashRegisters,
    Employees,
    CashManagements,
    ProductTypes,
    Products,
    Inventories,
    Customers,
    CustomerPayments,
    SalesTransactions,
    TransactionItems,
    TenderPayments,
    Suppliers,
    PurchaseOrders,
    PurchaseOrderItems,
    Expenses,
    SyncQueue,
  ],
  daos: [
    PosDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.sellBy);
            await m.addColumn(products, products.variantName);
            await m.addColumn(products, products.trackExpiry);
            await m.addColumn(products, products.expiryDate);
            await m.addColumn(products, products.notes);
            await m.addColumn(products, products.tags);
          }
          if (from < 4) {
            await m.addColumn(transactionItems, transactionItems.productName);
            await m.addColumn(transactionItems, transactionItems.categoryName);
            await m.addColumn(transactionItems, transactionItems.sku);
          }
          if (from < 5) {
            await m.addColumn(employees, employees.email);
          }
          if (from < 7) {
            await m.addColumn(products, products.imageUrl);
          }
        },
        beforeOpen: (details) async {
          // Enforce foreign key constraints in SQLite
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'pos_offline.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
