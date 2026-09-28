import 'package:drift/drift.dart';
import 'tenancy_tables.dart';
import 'employee_tables.dart';

/// Cash Managements table (Drawer Sessions / Register Shifts)
class CashManagements extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get cashRegisterId => text().references(CashRegisters, #id)();
  TextColumn get employeeId => text().nullable().references(Employees, #id)();
  DateTimeColumn get openTime => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closeTime => dateTime().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
  RealColumn get closingBalance => real().nullable()();
  RealColumn get expectedBalance => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
