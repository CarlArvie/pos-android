// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pos_dao.dart';

// ignore_for_file: type=lint
mixin _$PosDaoMixin on DatabaseAccessor<AppDatabase> {
  $CompaniesTable get companies => attachedDatabase.companies;
  $StoresTable get stores => attachedDatabase.stores;
  $CashRegistersTable get cashRegisters => attachedDatabase.cashRegisters;
  $EmployeesTable get employees => attachedDatabase.employees;
  $CashManagementsTable get cashManagements => attachedDatabase.cashManagements;
  $ProductTypesTable get productTypes => attachedDatabase.productTypes;
  $ProductsTable get products => attachedDatabase.products;
  $InventoriesTable get inventories => attachedDatabase.inventories;
  $CustomersTable get customers => attachedDatabase.customers;
  $CustomerPaymentsTable get customerPayments =>
      attachedDatabase.customerPayments;
  $SalesTransactionsTable get salesTransactions =>
      attachedDatabase.salesTransactions;
  $TransactionItemsTable get transactionItems =>
      attachedDatabase.transactionItems;
  $TenderPaymentsTable get tenderPayments => attachedDatabase.tenderPayments;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  PosDaoManager get managers => PosDaoManager(this);
}

class PosDaoManager {
  final _$PosDaoMixin _db;
  PosDaoManager(this._db);
  $$CompaniesTableTableManager get companies =>
      $$CompaniesTableTableManager(_db.attachedDatabase, _db.companies);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$CashRegistersTableTableManager get cashRegisters =>
      $$CashRegistersTableTableManager(_db.attachedDatabase, _db.cashRegisters);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db.attachedDatabase, _db.employees);
  $$CashManagementsTableTableManager get cashManagements =>
      $$CashManagementsTableTableManager(
        _db.attachedDatabase,
        _db.cashManagements,
      );
  $$ProductTypesTableTableManager get productTypes =>
      $$ProductTypesTableTableManager(_db.attachedDatabase, _db.productTypes);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$InventoriesTableTableManager get inventories =>
      $$InventoriesTableTableManager(_db.attachedDatabase, _db.inventories);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$CustomerPaymentsTableTableManager get customerPayments =>
      $$CustomerPaymentsTableTableManager(
        _db.attachedDatabase,
        _db.customerPayments,
      );
  $$SalesTransactionsTableTableManager get salesTransactions =>
      $$SalesTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.salesTransactions,
      );
  $$TransactionItemsTableTableManager get transactionItems =>
      $$TransactionItemsTableTableManager(
        _db.attachedDatabase,
        _db.transactionItems,
      );
  $$TenderPaymentsTableTableManager get tenderPayments =>
      $$TenderPaymentsTableTableManager(
        _db.attachedDatabase,
        _db.tenderPayments,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
