import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/local/database.dart';
import 'device_prefs.dart';
import 'permissions/permission_service.dart';
import 'services/product_image_service.dart';

class SyncEngine with ChangeNotifier {
  static SyncEngine? instance;

  final AppDatabase db;
  final SupabaseClient supabase;
  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _lastSyncError;
  RealtimeChannel? _realtimeChannel;
  String? _subscribedCompanyId;
  RealtimeSubscribeStatus? _realtimeStatus;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastSyncError => _lastSyncError;
  RealtimeSubscribeStatus? get realtimeStatus => _realtimeStatus;
  bool get isConnected =>
      _realtimeStatus == RealtimeSubscribeStatus.subscribed ||
      (_lastSyncError == null && _lastSyncTime != null);

  SyncEngine({required this.db, required this.supabase}) {
    instance = this;
  }

  void startSyncLoop() {
    _syncTimer?.cancel();
    int tick = 0;
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _processSyncQueue();
      _ensureRealtimeSubscribed();
      tick++;
      if (tick >= 30) { // Every 5 minutes background catch-up poll
        tick = 0;
        _executePullCycle();
      }
    });

    // Immediate initial push, pull, and realtime setup on launch
    _processSyncQueue();
    _executePullCycle();
    _ensureRealtimeSubscribed();
  }

  void stopSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _unsubscribeRealtime();
  }

  /// Restarts or initializes the realtime websocket subscription
  void restartRealtime() {
    _unsubscribeRealtime();
    _ensureRealtimeSubscribed();
  }

  void _unsubscribeRealtime() {
    if (_realtimeChannel != null) {
      try {
        supabase.removeChannel(_realtimeChannel!);
      } catch (e) {
        debugPrint('[SyncEngine] Error removing channel: $e');
      }
      _realtimeChannel = null;
      _subscribedCompanyId = null;
    }
  }

  void _ensureRealtimeSubscribed() {
    final companyId = DevicePrefs.companyId;
    if (companyId == null || companyId.isEmpty) {
      return;
    }

    // Already subscribed to this company's channel
    if (_realtimeChannel != null && _subscribedCompanyId == companyId) {
      return;
    }

    _unsubscribeRealtime();
    _subscribedCompanyId = companyId;

    try {
      final channelName = 'pos_company_realtime_$companyId';
      _realtimeChannel = supabase.channel(channelName);

      _realtimeChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) async {
            final table = payload.table;
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            debugPrint('[SyncEngine Realtime] Received $eventType on $table');

            // Handle DELETES
            if (eventType == PostgresChangeEvent.delete) {
              final recordId = oldRecord['id'] as String?;
              if (recordId != null) {
                await _handleRealtimeDelete(table, recordId);
              }
              return;
            }

            // Only process updates/inserts that have a payload
            if (newRecord.isEmpty) return;

            // Ensure the record belongs to our company (except companies table where id is the companyId)
            if (table != 'companies' && newRecord['company_id'] != companyId) return;

            try {
              await db.posDao.upsertFromCloud(
                company: table == 'companies' ? newRecord : null,
                stores: table == 'stores' ? [newRecord] : [],
                registers: table == 'cash_registers' ? [newRecord] : [],
                employees: table == 'employees' ? [newRecord] : [],
                productTypes: table == 'product_types' ? [newRecord] : [],
                products: table == 'products' ? [newRecord] : [],
                inventories: table == 'inventories' ? [newRecord] : [],
                customers: table == 'customers' ? [newRecord] : [],
                customerPayments: table == 'customer_payments' ? [newRecord] : [],
                cashManagements: table == 'cash_managements' ? [newRecord] : [],
                salesTransactions: table == 'sales_transactions' ? [newRecord] : [],
                transactionItems: table == 'transaction_items' ? [newRecord] : [],
                tenderPayments: table == 'tender_payments' ? [newRecord] : [],
              );

              // Realtime Permissions Sync
              if (table == 'companies' && newRecord['role_permissions'] != null) {
                await PermissionService.instance.applyCloudRolePermissions(newRecord['role_permissions']);
              } else if (table == 'employees') {
                final empId = newRecord['id'] as String?;
                if (empId != null && newRecord.containsKey('custom_permissions')) {
                  await PermissionService.instance.applyCloudEmployeePermissions(empId, newRecord['custom_permissions']);
                }
              }

              debugPrint('[SyncEngine Realtime] Successfully applied $eventType for $table into SQLite');
            } catch (e, stack) {
              debugPrint('[SyncEngine Realtime] Upsert error for $table: $e\n$stack');
              // Trigger pull cycle as fallback in case of foreign key or dependency issue
              await _executePullCycle();
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[SyncEngine Realtime] Subscription status: $status, error: $error');
          _realtimeStatus = status;
          notifyListeners();
          if (status == RealtimeSubscribeStatus.subscribed) {
            _executePullCycle();
          }
        });
    } catch (e) {
      debugPrint('[SyncEngine Realtime] Failed to subscribe: $e');
    }
  }

  Future<void> _handleRealtimeDelete(String table, String id) async {
    try {
      if (table == 'products') {
        await (db.update(db.products)..where((p) => p.id.equals(id))).write(
          const ProductsCompanion(isDeleted: Value(true), isActive: Value(false)),
        );
      } else if (table == 'inventories') {
        await (db.delete(db.inventories)..where((i) => i.id.equals(id))).go();
      } else if (table == 'product_types') {
        await (db.update(db.productTypes)..where((pt) => pt.id.equals(id))).write(
          const ProductTypesCompanion(isDeleted: Value(true)),
        );
      } else if (table == 'employees') {
        await (db.update(db.employees)..where((e) => e.id.equals(id))).write(
          const EmployeesCompanion(isActive: Value(false)),
        );
      } else if (table == 'customers') {
        await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          const CustomersCompanion(isDeleted: Value(true)),
        );
      } else if (table == 'stores') {
        await (db.update(db.stores)..where((s) => s.id.equals(id))).write(
          const StoresCompanion(isActive: Value(false)),
        );
      }
    } catch (e) {
      debugPrint('[SyncEngine Realtime] Error handling delete for $table/$id: $e');
    }
  }

  Future<void> _processSyncQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final pendingItems = await db.posDao.getPendingSyncItems();
      
      for (final item in pendingItems) {
        try {
          final payload = jsonDecode(item.payload) as Map<String, dynamic>;

          if (item.targetTable == 'products') {
            final localImagePath = payload['image_path'] as String?;
            final currentImageUrl = payload['image_url'] as String?;

            if (localImagePath != null && localImagePath.isNotEmpty && (currentImageUrl == null || currentImageUrl.isEmpty)) {
              try {
                final file = await ProductImageService.resolveLocalFile(localImagePath);
                if (file != null && await file.exists()) {
                  final bytes = await file.readAsBytes();
                  final companyId = payload['company_id'] as String? ?? DevicePrefs.companyId ?? 'default';
                  final storagePath = '$companyId/products/${item.recordId}.jpg';

                  await supabase.storage.from('product-images').uploadBinary(
                    storagePath,
                    bytes,
                    fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
                  );

                  final publicUrl = supabase.storage.from('product-images').getPublicUrl(storagePath);
                  payload['image_url'] = publicUrl;

                  await (db.update(db.products)..where((p) => p.id.equals(item.recordId))).write(
                    ProductsCompanion(imageUrl: Value(publicUrl)),
                  );
                }
              } catch (storageErr) {
                debugPrint('[SyncEngine] Storage upload error for ${item.recordId}: $storageErr');
              }
            }
          }
          
          if (item.action == 'INSERT') {
            await supabase.from(item.targetTable).upsert(payload);
          } else if (item.action == 'UPDATE') {
            // For updates, use SQL UPDATE with where id = recordId so Postgres
            // only updates modified columns without triggering NOT-NULL checks on unchanged columns
            final updatePayload = Map<String, dynamic>.from(payload)..remove('id');
            final res = await supabase.from(item.targetTable).update(updatePayload).eq('id', item.recordId).select();
            
            // If row does not exist in cloud yet, fetch complete record from local DB and upsert
            if (res.isEmpty) {
              final fullRecord = await _fetchFullLocalRecord(item.targetTable, item.recordId);
              if (fullRecord != null) {
                await supabase.from(item.targetTable).upsert(fullRecord);
              } else if (payload.containsKey('company_id')) {
                await supabase.from(item.targetTable).upsert({...payload, 'id': item.recordId});
              }
            }
          } else if (item.action == 'DELETE') {
            await supabase.from(item.targetTable).delete().eq('id', item.recordId);
          }

          // If successful, delete the item from the local queue
          await db.posDao.deleteSyncItem(item.id);
        } catch (e) {
          debugPrint('[SyncEngine] Sync failed for item ${item.id} on ${item.targetTable}: $e');
          // Update item as failed and increment retry count
          await db.posDao.markSyncItemFailed(item.id, e.toString());
        }
      }
      _lastSyncTime = DateTime.now();
      _lastSyncError = null;
    } catch (e) {
      _lastSyncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> _fetchFullLocalRecord(String table, String id) async {
    try {
      if (table == 'inventories') {
        final inv = await (db.select(db.inventories)..where((i) => i.id.equals(id))).getSingleOrNull();
        if (inv != null) {
          return {
            'id': inv.id,
            'company_id': inv.companyId,
            'store_id': inv.storeId,
            'product_id': inv.productId,
            'quantity_on_hand': inv.quantityOnHand,
            'reorder_level': inv.reorderLevel,
            'unit_cost': inv.unitCost,
            'track_stock': inv.trackStock,
            'created_at': inv.createdAt.toIso8601String(),
            'updated_at': inv.updatedAt.toIso8601String(),
          };
        }
      } else if (table == 'products') {
        final prod = await (db.select(db.products)..where((p) => p.id.equals(id))).getSingleOrNull();
        if (prod != null) {
          return {
            'id': prod.id,
            'company_id': prod.companyId,
            'product_name': prod.productName,
            'price': prod.price,
            'cost_price': prod.costPrice,
            'unit': prod.unit,
            'sell_by': prod.sellBy,
            'variant_name': prod.variantName,
            'image_path': prod.imagePath,
            'image_url': prod.imageUrl,
            'tax_percent': prod.taxPercent,
            'is_active': prod.isActive,
            'is_deleted': prod.isDeleted,
            'created_at': prod.createdAt.toIso8601String(),
            'updated_at': prod.updatedAt.toIso8601String(),
          };
        }
      } else if (table == 'customers') {
        final cust = await (db.select(db.customers)..where((c) => c.id.equals(id))).getSingleOrNull();
        if (cust != null) {
          return {
            'id': cust.id,
            'company_id': cust.companyId,
            'full_name': cust.fullName,
            'phone': cust.phone,
            'email': cust.email,
            'address': cust.address,
            'loyalty_tier': cust.loyaltyTier,
            'points_balance': cust.pointsBalance,
            'due_amount': cust.dueAmount,
            'credit_limit': cust.creditLimit,
            'is_deleted': cust.isDeleted,
            'created_at': cust.createdAt.toIso8601String(),
            'updated_at': cust.updatedAt.toIso8601String(),
          };
        }
      } else if (table == 'cash_managements') {
        final cm = await (db.select(db.cashManagements)..where((c) => c.id.equals(id))).getSingleOrNull();
        if (cm != null) {
          return {
            'id': cm.id,
            'company_id': cm.companyId,
            'store_id': cm.storeId,
            'cash_register_id': cm.cashRegisterId,
            'employee_id': cm.employeeId,
            'open_time': cm.openTime.toIso8601String(),
            'close_time': cm.closeTime?.toIso8601String(),
            'opening_balance': cm.openingBalance,
            'closing_balance': cm.closingBalance,
            'expected_balance': cm.expectedBalance,
            'status': cm.status,
            'notes': cm.notes,
            'created_at': cm.createdAt.toIso8601String(),
            'updated_at': cm.updatedAt.toIso8601String(),
          };
        }
      }
    } catch (e) {
      debugPrint('[SyncEngine] Fetch full local record error for $table/$id: $e');
    }
    return null;
  }

  Future<void> forcePull() async {
    await _executePullCycle();
  }

  /// Triggers an immediate push of the local outbox queue followed by a full pull cycle
  Future<void> syncNow() async {
    await _processSyncQueue();
    await _executePullCycle();
    notifyListeners();
  }

  Future<void> _executePullCycle() async {
    final companyId = DevicePrefs.companyId;
    if (companyId == null || companyId.isEmpty) return;

    try {
      final companyResp = await supabase.from('companies').select().eq('id', companyId).maybeSingle();
      final storesResp = await supabase.from('stores').select().eq('company_id', companyId);
      final registersResp = await supabase.from('cash_registers').select().eq('company_id', companyId);
      final employeesResp = await supabase.from('employees').select().eq('company_id', companyId);
      final productTypesResp = await supabase.from('product_types').select().eq('company_id', companyId);
      final productsResp = await supabase.from('products').select().eq('company_id', companyId);
      final inventoryResp = await supabase.from('inventories').select().eq('company_id', companyId);
      final customersResp = await supabase.from('customers').select().eq('company_id', companyId);
      final customerPaymentsResp = await supabase.from('customer_payments').select().eq('company_id', companyId);
      final shiftsResp = await supabase.from('cash_managements').select().eq('company_id', companyId);
      final salesResp = await supabase.from('sales_transactions').select().eq('company_id', companyId);
      final itemsResp = await supabase.from('transaction_items').select().eq('company_id', companyId);
      final tendersResp = await supabase.from('tender_payments').select().eq('company_id', companyId);

      await db.posDao.upsertFromCloud(
        company: companyResp,
        stores: storesResp,
        registers: registersResp,
        employees: employeesResp,
        productTypes: productTypesResp,
        products: productsResp,
        inventories: inventoryResp,
        customers: customersResp,
        customerPayments: customerPaymentsResp,
        cashManagements: shiftsResp,
        salesTransactions: salesResp,
        transactionItems: itemsResp,
        tenderPayments: tendersResp,
      );

      // Apply cloud permissions on pull cycle
      if (companyResp != null && companyResp['role_permissions'] != null) {
        await PermissionService.instance.applyCloudRolePermissions(companyResp['role_permissions']);
      }

      for (final emp in employeesResp) {
        final empId = emp['id'] as String?;
        final customPerms = emp['custom_permissions'];
        if (empId != null && customPerms != null) {
          await PermissionService.instance.applyCloudEmployeePermissions(empId, customPerms);
        }
      }

      // Self-healing push for local customers not yet in cloud
      await _reconcileLocalCustomers(companyId);

      _lastSyncTime = DateTime.now();
      _lastSyncError = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[SyncEngine] Pull cycle error: $e');
      _lastSyncError = e.toString();
      notifyListeners();
    }
  }

  /// Pushes any locally created customers that are not yet in Supabase cloud (e.g. created offline or before sync was enabled)
  Future<void> _reconcileLocalCustomers(String companyId) async {
    try {
      final localCustomers = await (db.select(db.customers)
            ..where((c) => c.companyId.equals(companyId)))
          .get();
      if (localCustomers.isEmpty) return;

      final cloudResp = await supabase
          .from('customers')
          .select('id')
          .eq('company_id', companyId);
      final Set<String> cloudIds = (cloudResp as List)
          .map((e) => e['id'] as String)
          .toSet();

      final unsynced = localCustomers.where((c) => !cloudIds.contains(c.id)).toList();
      if (unsynced.isNotEmpty) {
        debugPrint('[SyncEngine] Reconciling ${unsynced.length} local customer(s) to cloud...');
        for (final c in unsynced) {
          final payload = {
            'id': c.id,
            'company_id': c.companyId,
            'full_name': c.fullName,
            'phone': c.phone,
            'email': c.email,
            'address': c.address,
            'loyalty_tier': c.loyaltyTier,
            'points_balance': c.pointsBalance,
            'due_amount': c.dueAmount,
            'credit_limit': c.creditLimit,
            'created_at': c.createdAt.toIso8601String(),
            'updated_at': c.updatedAt.toIso8601String(),
            'is_deleted': c.isDeleted,
          };
          await supabase.from('customers').upsert(payload);
        }
        debugPrint('[SyncEngine] Successfully pushed ${unsynced.length} local customer(s) to cloud.');
      }
    } catch (e) {
      debugPrint('[SyncEngine] Reconcile local customers error: $e');
    }
  }
}
