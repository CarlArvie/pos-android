import 'package:drift/drift.dart';

/// Offline Outbox Sync Queue for bi-directional synchronization with Supabase
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()(); // e.g. 'sales_transactions', 'tender_payments'
  TextColumn get recordId => text()(); // UUID of the entity
  TextColumn get action => text()(); // 'INSERT', 'UPDATE', 'DELETE'
  TextColumn get payload => text()(); // JSON serialized representation
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // 'pending', 'syncing', 'failed'
  TextColumn get errorMessage => text().nullable()();
}
