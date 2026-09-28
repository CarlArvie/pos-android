import 'package:drift/drift.dart';
import 'tenancy_tables.dart';

/// Employees table for cashiers, managers, and staff
class Employees extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  TextColumn get profileId => text().nullable()(); // Supabase Auth Profiles UUID
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get position => text().withDefault(const Constant('Cashier'))();
  TextColumn get email => text().nullable()(); // Added for Auth
  TextColumn get pinCode => text().nullable()(); // Quick POS PIN for register unlock
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get startDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
