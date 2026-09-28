import 'package:drift/drift.dart';
import 'tenancy_tables.dart';
import 'employee_tables.dart';
import 'customer_tables.dart';
import 'catalog_tables.dart';
import 'shift_tables.dart';

/// Sales Transactions Header (Orders & Invoices)
class SalesTransactions extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get cashRegisterId => text().nullable().references(CashRegisters, #id)();
  TextColumn get employeeId => text().nullable().references(Employees, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get cashManagementId => text().nullable().references(CashManagements, #id)();
  TextColumn get originalTransactionId => text().nullable()(); // Self-reference for refunds/returns
  TextColumn get invoiceNo => text()();
  DateTimeColumn get transactionDatetime => dateTime().withDefault(currentDateAndTime)();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get discountTotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxTotal => real().withDefault(const Constant(0.0))();
  RealColumn get grandTotal => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get returnReason => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Transaction Line Items
class TransactionItems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get salesTransactionId => text().references(SalesTransactions, #id)();
  TextColumn get productId => text().nullable().references(Products, #id, onDelete: KeyAction.setNull)();
  
  // Snapshot Data
  TextColumn get productName => text().nullable()();
  TextColumn get categoryName => text().nullable()();
  TextColumn get sku => text().nullable()();

  RealColumn get quantity => real().withDefault(const Constant(1.0))();
  RealColumn get unitPrice => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  TextColumn get serialNumber => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tender Payments split per transaction
class TenderPayments extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get salesTransactionId => text().references(SalesTransactions, #id)();
  TextColumn get paymentMethod => text()(); // cash, credit_card, debit_card, gcash, maya
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  RealColumn get amountTendered => real().withDefault(const Constant(0.0))();
  RealColumn get changeAmount => real().withDefault(const Constant(0.0))();
  TextColumn get cardLastFour => text().nullable()();
  TextColumn get authCode => text().nullable()();
  TextColumn get referenceNo => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get paymentNotes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
