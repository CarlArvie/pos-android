import 'package:drift/drift.dart';
import 'tenancy_tables.dart';

/// Product Types / Categories
class ProductTypes extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  TextColumn get typeName => text()();
  TextColumn get category => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Products catalog
class Products extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get productTypeId => text().nullable().references(ProductTypes, #id)();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  RealColumn get costPrice => real().withDefault(const Constant(0.0))();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  RealColumn get taxPercent => real().withDefault(const Constant(0.0))();
  IntColumn get piecesPerPack => integer().withDefault(const Constant(1))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get sellBy => text().withDefault(const Constant('unit'))(); // 'unit' or 'fraction'
  TextColumn get variantName => text().nullable()();
  BoolColumn get trackExpiry => boolean().withDefault(const Constant(false))();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get tags => text().nullable()();
  BoolColumn get isSerialized => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Inventories tracking stock levels per store
class Inventories extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantityOnHand => real().withDefault(const Constant(0.0))();
  RealColumn get reorderLevel => real().withDefault(const Constant(10.0))();
  RealColumn get unitCost => real().withDefault(const Constant(0.0))();
  BoolColumn get trackStock => boolean().withDefault(const Constant(true))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {storeId, productId},
      ];
}
