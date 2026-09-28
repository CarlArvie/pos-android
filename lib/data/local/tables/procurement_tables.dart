import 'package:drift/drift.dart';
import 'tenancy_tables.dart';
import 'employee_tables.dart';
import 'catalog_tables.dart';

/// Suppliers for procurement
class Suppliers extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get supplierName => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Purchase Orders
class PurchaseOrders extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get employeeId => text().nullable().references(Employees, #id)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Purchase Order Items
class PurchaseOrderItems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get poId => text().references(PurchaseOrders, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real().withDefault(const Constant(0.0))();
  RealColumn get unitCost => real().withDefault(const Constant(0.0))();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get receivedQty => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Operating and Store Expenses
class Expenses extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get employeeId => text().nullable().references(Employees, #id)();
  TextColumn get poId => text().nullable().references(PurchaseOrders, #id)();
  TextColumn get category => text().withDefault(const Constant('General'))();
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
