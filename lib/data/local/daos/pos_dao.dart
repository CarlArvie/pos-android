import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database.dart';
import '../tables/catalog_tables.dart';
import '../tables/customer_tables.dart';
import '../tables/employee_tables.dart';
import '../tables/sales_tables.dart';
import '../tables/shift_tables.dart';
import '../tables/tenancy_tables.dart';
import '../tables/sync_tables.dart';

part 'pos_dao.g.dart';

@DriftAccessor(tables: [
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
  SyncQueue,
])
class PosDao extends DatabaseAccessor<AppDatabase> with _$PosDaoMixin {
  PosDao(super.db);

  final _uuid = const Uuid();

  // --- CATALOG QUERIES ---
  Stream<List<Product>> watchActiveProducts(String companyId) {
    return (select(products)
          ..where((p) => p.companyId.equals(companyId) & p.isActive.equals(true) & p.isDeleted.equals(false)))
        .watch();
  }

  Future<List<Product>> getActiveProducts(String companyId) {
    return (select(products)
          ..where((p) => p.companyId.equals(companyId) & p.isActive.equals(true) & p.isDeleted.equals(false)))
        .get();
  }

  Stream<List<ProductType>> watchCategories(String companyId) {
    return (select(productTypes)
          ..where((c) => c.companyId.equals(companyId) & c.isDeleted.equals(false)))
        .watch();
  }

  // --- INVENTORY QUERIES ---
  Future<Inventory?> getInventoryForProduct(String storeId, String productId) {
    return (select(inventories)
          ..where((i) => i.storeId.equals(storeId) & i.productId.equals(productId)))
        .getSingleOrNull();
  }

  // --- CUSTOMER QUERIES ---
  Stream<List<Customer>> watchCustomers(String companyId) {
    return (select(customers)
          ..where((c) => c.companyId.equals(companyId) & c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.fullName)]))
        .watch();
  }

  Future<List<Customer>> getCustomers(String companyId) {
    return (select(customers)
          ..where((c) => c.companyId.equals(companyId) & c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.fullName)]))
        .get();
  }

  Future<Customer> addCustomer({
    required String companyId,
    required String fullName,
    String? phone,
    String? email,
    String? address,
    String loyaltyTier = 'Bronze',
    double pointsBalance = 0.0,
    double creditLimit = 5000.0,
  }) async {
    final customerId = _uuid.v4();
    final now = DateTime.now();
    final companion = CustomersCompanion.insert(
      id: customerId,
      companyId: companyId,
      fullName: fullName,
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      loyaltyTier: Value(loyaltyTier),
      pointsBalance: Value(pointsBalance),
      dueAmount: const Value(0.0),
      creditLimit: Value(creditLimit),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    await into(customers).insert(companion);
    final inserted = await (select(customers)..where((c) => c.id.equals(customerId))).getSingle();

    final payload = {
      'id': inserted.id,
      'company_id': inserted.companyId,
      'full_name': inserted.fullName,
      'phone': inserted.phone,
      'email': inserted.email,
      'address': inserted.address,
      'loyalty_tier': inserted.loyaltyTier,
      'points_balance': inserted.pointsBalance,
      'due_amount': inserted.dueAmount,
      'credit_limit': inserted.creditLimit,
      'created_at': inserted.createdAt.toIso8601String(),
      'updated_at': inserted.updatedAt.toIso8601String(),
      'is_deleted': inserted.isDeleted,
    };

    // Queue for sync
    await queueSync('customers', inserted.id, 'INSERT', payload);

    // Immediate cloud push if Supabase is initialized
    try {
      if (Supabase.instance.isInitialized) {
        await Supabase.instance.client.from('customers').upsert(payload);
      }
    } catch (_) {}

    return inserted;
  }

  Future<void> updateCustomer({
    required String id,
    required String fullName,
    String? phone,
    String? email,
    String? address,
    String? loyaltyTier,
    double? pointsBalance,
    double? creditLimit,
    double? dueAmount,
  }) async {
    final now = DateTime.now();
    await (update(customers)..where((c) => c.id.equals(id))).write(
      CustomersCompanion(
        fullName: Value(fullName),
        phone: Value(phone),
        email: Value(email),
        address: Value(address),
        loyaltyTier: loyaltyTier != null ? Value(loyaltyTier) : const Value.absent(),
        pointsBalance: pointsBalance != null ? Value(pointsBalance) : const Value.absent(),
        creditLimit: creditLimit != null ? Value(creditLimit) : const Value.absent(),
        dueAmount: dueAmount != null ? Value(dueAmount) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );

    final updated = await (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();
    if (updated != null) {
      final payload = {
        'id': updated.id,
        'company_id': updated.companyId,
        'full_name': updated.fullName,
        'phone': updated.phone,
        'email': updated.email,
        'address': updated.address,
        'loyalty_tier': updated.loyaltyTier,
        'points_balance': updated.pointsBalance,
        'due_amount': updated.dueAmount,
        'credit_limit': updated.creditLimit,
        'updated_at': updated.updatedAt.toIso8601String(),
        'is_deleted': updated.isDeleted,
      };

      await queueSync('customers', id, 'UPDATE', payload);

      try {
        if (Supabase.instance.isInitialized) {
          await Supabase.instance.client.from('customers').upsert(payload);
        }
      } catch (_) {}
    }
  }

  Future<void> deleteCustomer(String id) async {
    final now = DateTime.now();
    await (update(customers)..where((c) => c.id.equals(id))).write(
      CustomersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
      ),
    );

    final customer = await (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();
    if (customer != null) {
      final payload = {
        'id': customer.id,
        'company_id': customer.companyId,
        'is_deleted': true,
        'updated_at': now.toIso8601String(),
      };

      await queueSync('customers', id, 'UPDATE', payload);

      try {
        if (Supabase.instance.isInitialized) {
          await Supabase.instance.client.from('customers').upsert(payload);
        }
      } catch (_) {}
    }
  }

  // --- CUSTOMER CREDIT & DEBT SETTLEMENT ---
  Future<CustomerPayment> recordCustomerPayment({
    required String companyId,
    String? storeId,
    required String customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    final paymentId = _uuid.v4();
    final now = DateTime.now();

    return transaction(() async {
      // 1. Insert customer payment
      final companion = CustomerPaymentsCompanion.insert(
        id: paymentId,
        companyId: companyId,
        storeId: Value(storeId),
        customerId: customerId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      await into(customerPayments).insert(companion);

      final insertedPayment = await (select(customerPayments)..where((p) => p.id.equals(paymentId))).getSingle();

      // 2. Reduce customer due amount
      final cust = await (select(customers)..where((c) => c.id.equals(customerId))).getSingleOrNull();
      if (cust != null) {
        final newDue = (cust.dueAmount - amount).clamp(0.0, double.infinity);
        await (update(customers)..where((c) => c.id.equals(customerId))).write(
          CustomersCompanion(
            dueAmount: Value(newDue),
            updatedAt: Value(now),
          ),
        );

        final custPayload = {
          'id': cust.id,
          'company_id': cust.companyId,
          'full_name': cust.fullName,
          'phone': cust.phone,
          'email': cust.email,
          'address': cust.address,
          'loyalty_tier': cust.loyaltyTier,
          'points_balance': cust.pointsBalance,
          'due_amount': newDue,
          'credit_limit': cust.creditLimit,
          'updated_at': now.toIso8601String(),
          'is_deleted': cust.isDeleted,
        };
        await queueSync('customers', cust.id, 'UPDATE', custPayload);

        try {
          if (Supabase.instance.isInitialized) {
            await Supabase.instance.client.from('customers').upsert(custPayload);
          }
        } catch (_) {}
      }

      // 3. Queue payment sync and immediate push
      final paymentPayload = {
        'id': insertedPayment.id,
        'company_id': insertedPayment.companyId,
        'store_id': insertedPayment.storeId,
        'customer_id': insertedPayment.customerId,
        'amount': insertedPayment.amount,
        'payment_method': insertedPayment.paymentMethod,
        'notes': insertedPayment.notes,
        'created_at': insertedPayment.createdAt.toIso8601String(),
        'updated_at': insertedPayment.updatedAt.toIso8601String(),
      };
      await queueSync('customer_payments', insertedPayment.id, 'INSERT', paymentPayload);

      try {
        if (Supabase.instance.isInitialized) {
          await Supabase.instance.client.from('customer_payments').upsert(paymentPayload);
        }
      } catch (_) {}

      return insertedPayment;
    });
  }

  Stream<List<CustomerPayment>> watchCustomerPayments(String customerId) {
    return (select(customerPayments)
          ..where((p) => p.customerId.equals(customerId))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .watch();
  }

  Future<List<CustomerPayment>> getCustomerPayments(String customerId) {
    return (select(customerPayments)
          ..where((p) => p.customerId.equals(customerId))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  // --- ATOMIC SALES TRANSACTION ---
  /// Creates a complete sales order with line items, tender payments, and updates local stock within an ACID transaction.
  Future<String> createSaleTransaction({
    required String companyId,
    required String storeId,
    String? registerId,
    String? employeeId,
    String? customerId,
    String? cashManagementId,
    required String invoiceNo,
    required double subtotal,
    required double discountTotal,
    required double taxTotal,
    required double grandTotal,
    required List<({String productId, double quantity, double unitPrice, double discountAmount, double taxAmount})> items,
    required List<({String paymentMethod, double amount, double amountTendered, double changeAmount, String? refNo})> tenders,
  }) async {
    final saleId = _uuid.v4();

    return transaction(() async {
      // 1. Insert Sales Transaction Header
      await into(salesTransactions).insert(
        SalesTransactionsCompanion.insert(
          id: saleId,
          companyId: companyId,
          storeId: storeId,
          invoiceNo: invoiceNo,
          cashRegisterId: Value(registerId),
          employeeId: Value(employeeId),
          customerId: Value(customerId),
          cashManagementId: Value(cashManagementId),
          subtotal: Value(subtotal),
          discountTotal: Value(discountTotal),
          taxTotal: Value(taxTotal),
          grandTotal: Value(grandTotal),
        ),
      );

      // 2. Insert Line Items & Decrement Stock
      for (final item in items) {
        final itemId = _uuid.v4();
        final lineSubtotal = (item.quantity * item.unitPrice) - item.discountAmount + item.taxAmount;

        // Fetch Snapshot Data
        final prodQuery = await (select(products)..where((p) => p.id.equals(item.productId))).getSingleOrNull();
        String? pName = prodQuery?.productName;
        String? pSku = prodQuery?.sku;
        String? cName;
        if (prodQuery?.productTypeId != null) {
          final catQuery = await (select(productTypes)..where((c) => c.id.equals(prodQuery!.productTypeId!))).getSingleOrNull();
          cName = catQuery?.typeName;
        }

        await into(transactionItems).insert(
          TransactionItemsCompanion.insert(
            id: itemId,
            companyId: companyId,
            salesTransactionId: saleId,
            productId: Value(item.productId),
            productName: Value(pName),
            categoryName: Value(cName),
            sku: Value(pSku),
            quantity: Value(item.quantity),
            unitPrice: Value(item.unitPrice),
            discountAmount: Value(item.discountAmount),
            taxAmount: Value(item.taxAmount),
            subtotal: Value(lineSubtotal),
          ),
        );

        await queueSync('transaction_items', itemId, 'INSERT', {
          'id': itemId,
          'company_id': companyId,
          'sales_transaction_id': saleId,
          'product_id': item.productId,
          'product_name': pName,
          'category_name': cName,
          'sku': pSku,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'discount_amount': item.discountAmount,
          'tax_amount': item.taxAmount,
          'subtotal': lineSubtotal,
        });

        // Update local inventory if present
        final inv = await getInventoryForProduct(storeId, item.productId);
        if (inv != null && inv.trackStock) {
          final newQty = inv.quantityOnHand - item.quantity;
          await (update(inventories)..where((i) => i.id.equals(inv.id))).write(
            InventoriesCompanion(
              quantityOnHand: Value(newQty),
              updatedAt: Value(DateTime.now()),
            ),
          );
          
          await queueSync('inventories', inv.id, 'UPDATE', {
            'company_id': inv.companyId,
            'store_id': inv.storeId,
            'product_id': inv.productId,
            'quantity_on_hand': newQty,
            'reorder_level': inv.reorderLevel,
            'unit_cost': inv.unitCost,
            'track_stock': inv.trackStock,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // 3. Insert Tender Payments
      double creditTenderTotal = 0.0;
      for (final tender in tenders) {
        if (tender.paymentMethod.toLowerCase() == 'credit') {
          creditTenderTotal += tender.amount;
        }
        final tenderId = _uuid.v4();
        await into(tenderPayments).insert(
          TenderPaymentsCompanion.insert(
            id: tenderId,
            companyId: companyId,
            salesTransactionId: saleId,
            paymentMethod: tender.paymentMethod,
            amount: Value(tender.amount),
            amountTendered: Value(tender.amountTendered),
            changeAmount: Value(tender.changeAmount),
            referenceNo: Value(tender.refNo),
          ),
        );
        // Queue Tender Payment Sync
        await queueSync('tender_payments', tenderId, 'INSERT', {
          'id': tenderId,
          'company_id': companyId,
          'sales_transaction_id': saleId,
          'payment_method': tender.paymentMethod,
          'amount': tender.amount,
          'amount_tendered': tender.amountTendered,
          'change_amount': tender.changeAmount,
          'reference_no': tender.refNo,
        });
      }

      // 4. Update Customer Credit Due & Loyalty Points
      if (customerId != null) {
        final cust = await (select(customers)..where((c) => c.id.equals(customerId))).getSingleOrNull();
        if (cust != null) {
          final earnedPoints = (subtotal / 100).floorToDouble(); // 1 pt per ₱100 spent
          final newDue = cust.dueAmount + creditTenderTotal;
          final newPoints = cust.pointsBalance + earnedPoints;
          final now = DateTime.now();

          await (update(customers)..where((c) => c.id.equals(customerId))).write(
            CustomersCompanion(
              dueAmount: Value(newDue),
              pointsBalance: Value(newPoints),
              updatedAt: Value(now),
            ),
          );

          final custPayload = {
            'id': cust.id,
            'company_id': cust.companyId,
            'full_name': cust.fullName,
            'phone': cust.phone,
            'email': cust.email,
            'address': cust.address,
            'loyalty_tier': cust.loyaltyTier,
            'points_balance': newPoints,
            'due_amount': newDue,
            'credit_limit': cust.creditLimit,
            'updated_at': now.toIso8601String(),
            'is_deleted': cust.isDeleted,
          };
          await queueSync('customers', cust.id, 'UPDATE', custPayload);

          try {
            if (Supabase.instance.isInitialized) {
              await Supabase.instance.client.from('customers').upsert(custPayload);
            }
          } catch (_) {}
        }
      }

      // 5. Push Sales Transaction Header to Sync Queue
      await queueSync('sales_transactions', saleId, 'INSERT', {
        'id': saleId,
        'company_id': companyId,
        'store_id': storeId,
        'cash_register_id': registerId,
        'employee_id': employeeId,
        'customer_id': customerId,
        'cash_management_id': cashManagementId,
        'invoice_no': invoiceNo,
        'transaction_datetime': DateTime.now().toIso8601String(),
        'subtotal': subtotal,
        'discount_total': discountTotal,
        'tax_total': taxTotal,
        'grand_total': grandTotal,
        'status': 'completed',
      });

      return saleId;
    });
  }

  // --- Sync Queue Helpers ---
  
  Future<void> queueSync(String targetTable, String recordId, String action, Map<String, dynamic> payload) {
    return into(syncQueue).insert(
      SyncQueueCompanion.insert(
        targetTable: targetTable,
        recordId: recordId,
        action: action,
        payload: jsonEncode(payload),
      ),
    );
  }

  Future<List<SyncQueueData>> getPendingSyncItems() {
    return (select(syncQueue)
          ..where((s) => s.status.equals('pending') | s.status.equals('failed'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(50))
        .get();
  }

  Future<void> deleteSyncItem(int id) {
    return (delete(syncQueue)..where((s) => s.id.equals(id))).go();
  }

  Future<void> markSyncItemFailed(int id, String error) async {
    final item = await (select(syncQueue)..where((s) => s.id.equals(id))).getSingle();
    final newRetryCount = item.retryCount + 1;
    
    // If it fails more than 5 times, mark as abandoned so it doesn't block the queue forever
    final newStatus = newRetryCount > 5 ? 'abandoned' : 'failed';
    
    await (update(syncQueue)..where((s) => s.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(newStatus),
        errorMessage: Value(error),
        retryCount: Value(newRetryCount),
      ),
    );
  }

  Stream<int> watchPendingSyncCount() {
    final pendingCount = countAll();
    final query = selectOnly(syncQueue)
      ..addColumns([pendingCount])
      ..where(syncQueue.status.equals('pending') | syncQueue.status.equals('failed'));
    return query.map((row) => row.read(pendingCount) ?? 0).watchSingle();
  }

  Stream<int> watchFailedSyncCount() {
    final failedCount = countAll();
    final query = selectOnly(syncQueue)
      ..addColumns([failedCount])
      ..where(syncQueue.status.equals('failed') | syncQueue.status.equals('abandoned'));
    return query.map((row) => row.read(failedCount) ?? 0).watchSingle();
  }

  Future<List<SyncQueueData>> getRecentSyncItems({int limit = 15}) {
    return (select(syncQueue)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<SyncQueueData>> watchRecentSyncItems({int limit = 15}) {
    return (select(syncQueue)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
          ..limit(limit))
        .watch();
  }

  // --- CASH DRAWER SHIFTS ---
  Stream<CashManagement?> watchActiveShift(String registerId, {String? employeeId}) {
    return (select(cashManagements)
          ..where((c) {
            final regMatch = c.cashRegisterId.equals(registerId);
            final statusMatch = c.status.equals('open');
            if (employeeId != null && employeeId.isNotEmpty) {
              return regMatch & statusMatch & c.employeeId.equals(employeeId);
            }
            return regMatch & statusMatch;
          })
          ..orderBy([(c) => OrderingTerm.desc(c.openTime)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<CashManagement?> getActiveShift(String registerId, {String? employeeId}) {
    return (select(cashManagements)
          ..where((c) {
            final regMatch = c.cashRegisterId.equals(registerId);
            final statusMatch = c.status.equals('open');
            if (employeeId != null && employeeId.isNotEmpty) {
              return regMatch & statusMatch & c.employeeId.equals(employeeId);
            }
            return regMatch & statusMatch;
          })
          ..orderBy([(c) => OrderingTerm.desc(c.openTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String> openCashShift({
    required String companyId,
    required String storeId,
    required String registerId,
    String? employeeId,
    required double openingBalance,
    String? notes,
  }) async {
    // Guard against duplicate active shifts for this employee on this register
    final existing = await getActiveShift(registerId, employeeId: employeeId);
    if (existing != null) {
      return existing.id;
    }

    final shiftId = _uuid.v4();
    final now = DateTime.now();
    await into(cashManagements).insert(
      CashManagementsCompanion.insert(
        id: shiftId,
        companyId: companyId,
        storeId: storeId,
        cashRegisterId: registerId,
        employeeId: Value(employeeId),
        openTime: Value(now),
        openingBalance: Value(openingBalance),
        status: const Value('open'),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final payload = {
      'id': shiftId,
      'company_id': companyId,
      'store_id': storeId,
      'cash_register_id': registerId,
      'employee_id': employeeId,
      'open_time': now.toIso8601String(),
      'opening_balance': openingBalance,
      'status': 'open',
      'notes': notes,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    await queueSync('cash_managements', shiftId, 'INSERT', payload);

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('cash_managements').upsert(payload);
    } catch (_) {
      // Offline or network error: successfully queued in syncQueue
    }

    return shiftId;
  }

  Future<ShiftSalesSummary> getShiftSalesSummary(String shiftId) async {
    final shift = await (select(cashManagements)..where((c) => c.id.equals(shiftId))).getSingleOrNull();
    final openingBalance = shift?.openingBalance ?? 0.0;

    final txs = await (select(salesTransactions)..where((s) => s.cashManagementId.equals(shiftId))).get();
    if (txs.isEmpty) {
      return ShiftSalesSummary(
        openingBalance: openingBalance,
        cashSales: 0.0,
        nonCashSales: 0.0,
        transactionCount: 0,
        expectedBalance: openingBalance,
      );
    }

    final txIds = txs.map((t) => t.id).toList();
    final tenders = await (select(tenderPayments)..where((t) => t.salesTransactionId.isIn(txIds))).get();

    double cashSales = 0.0;
    double nonCashSales = 0.0;

    for (final tender in tenders) {
      if (tender.paymentMethod == 'cash') {
        cashSales += tender.amount;
      } else {
        nonCashSales += tender.amount;
      }
    }

    return ShiftSalesSummary(
      openingBalance: openingBalance,
      cashSales: cashSales,
      nonCashSales: nonCashSales,
      transactionCount: txs.length,
      expectedBalance: openingBalance + cashSales,
    );
  }

  Future<void> closeCashShift({
    required String shiftId,
    required double closingBalance,
    required double expectedBalance,
    String? notes,
  }) async {
    final now = DateTime.now();
    await (update(cashManagements)..where((c) => c.id.equals(shiftId))).write(
      CashManagementsCompanion(
        closeTime: Value(now),
        closingBalance: Value(closingBalance),
        expectedBalance: Value(expectedBalance),
        status: const Value('closed'),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );

    final shift = await (select(cashManagements)..where((c) => c.id.equals(shiftId))).getSingleOrNull();

    final payload = {
      'close_time': now.toIso8601String(),
      'closing_balance': closingBalance,
      'expected_balance': expectedBalance,
      'status': 'closed',
      'notes': notes,
      'updated_at': now.toIso8601String(),
    };

    await queueSync('cash_managements', shiftId, 'UPDATE', {
      if (shift != null) ...{
        'company_id': shift.companyId,
        'store_id': shift.storeId,
        'cash_register_id': shift.cashRegisterId,
        'employee_id': shift.employeeId,
        'open_time': shift.openTime.toIso8601String(),
        'opening_balance': shift.openingBalance,
      },
      ...payload,
    });

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('cash_managements').update(payload).eq('id', shiftId);
    } catch (_) {
      // Offline or network error: successfully queued in syncQueue
    }
  }

  // --- TRANSACTION DETAIL & REPORTING QUERIES ---

  Future<TransactionDetail?> getTransactionDetail(String transactionId) async {
    final tx = await (select(salesTransactions)..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (tx == null) return null;

    final itemRows = await (select(transactionItems)..where((i) => i.salesTransactionId.equals(transactionId))).get();
    final tenderRows = await (select(tenderPayments)..where((t) => t.salesTransactionId.equals(transactionId))).get();

    String? customerName;
    if (tx.customerId != null) {
      final cust = await (select(customers)..where((c) => c.id.equals(tx.customerId!))).getSingleOrNull();
      customerName = cust?.fullName;
    }

    final List<TransactionLineItemDetail> detailedItems = [];
    for (final item in itemRows) {
      Product? prod;
      if (item.productId != null) {
        prod = await (select(products)..where((p) => p.id.equals(item.productId!))).getSingleOrNull();
      }
      prod ??= Product(
        id: item.productId ?? 'deleted',
        companyId: item.companyId,
        productName: item.productName ?? 'Unknown (Deleted)',
        price: item.unitPrice,
        costPrice: 0.0,
        unit: 'pcs',
        sellBy: 'unit',
        taxPercent: 0.0,
        trackExpiry: false,
        isActive: false,
        isDeleted: false,
        isSerialized: false,
        piecesPerPack: 1,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      );
      detailedItems.add(TransactionLineItemDetail(item: item, product: prod));
    }

    return TransactionDetail(
      transaction: tx,
      items: detailedItems,
      tenders: tenderRows,
      customerName: customerName,
    );
  }

  Future<List<TransactionDetail>> getAllTransactionDetails({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? status,
    String? employeeId,
  }) async {
    var query = select(salesTransactions);
    if (status != null && status.isNotEmpty && status != 'all') {
      query = query..where((t) => t.status.equals(status));
    }
    if (employeeId != null) {
      query = query..where((t) => t.employeeId.equals(employeeId));
    }
    if (startDate != null) {
      query = query..where((t) => t.transactionDatetime.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((t) => t.transactionDatetime.isSmallerOrEqualValue(endDate));
    }
    query = query..orderBy([(t) => OrderingTerm.desc(t.transactionDatetime)]);

    final txs = await query.get();
    if (txs.isEmpty) return [];

    final txIds = txs.map((t) => t.id).toList();
    final allItems = await (select(transactionItems)..where((i) => i.salesTransactionId.isIn(txIds))).get();
    final allTenders = await (select(tenderPayments)..where((t) => t.salesTransactionId.isIn(txIds))).get();

    final prodIds = allItems.map((i) => i.productId).where((id) => id != null).cast<String>().toSet().toList();
    final allProds = await (select(products)..where((p) => p.id.isIn(prodIds))).get();
    final prodMap = {for (final p in allProds) p.id: p};

    final itemsByTx = <String, List<TransactionLineItemDetail>>{};
    for (final item in allItems) {
      var prod = prodMap[item.productId];
      prod ??= Product(
        id: item.productId ?? 'deleted',
        companyId: item.companyId,
        productName: item.productName ?? 'Unknown (Deleted)',
        price: item.unitPrice,
        costPrice: 0.0,
        unit: 'pcs',
        sellBy: 'unit',
        taxPercent: 0.0,
        trackExpiry: false,
        isActive: false,
        isDeleted: false,
        isSerialized: false,
        piecesPerPack: 1,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      );
      itemsByTx.putIfAbsent(item.salesTransactionId, () => []).add(
        TransactionLineItemDetail(item: item, product: prod),
      );
    }

    final tendersByTx = <String, List<TenderPayment>>{};
    for (final tender in allTenders) {
      tendersByTx.putIfAbsent(tender.salesTransactionId, () => []).add(tender);
    }

    final List<TransactionDetail> results = [];
    for (final tx in txs) {
      final txTenders = tendersByTx[tx.id] ?? [];
      if (paymentMethod != null && paymentMethod.isNotEmpty && paymentMethod != 'all') {
        final hasMethod = txTenders.any((t) => t.paymentMethod.toLowerCase() == paymentMethod.toLowerCase());
        if (!hasMethod) continue;
      }

      results.add(
        TransactionDetail(
          transaction: tx,
          items: itemsByTx[tx.id] ?? [],
          tenders: txTenders,
        ),
      );
    }

    return results;
  }

  // --- EXPENSE QUERIES ---
  Stream<List<Expense>> watchExpenses(String companyId) {
    return (db.select(db.expenses)
          ..where((e) => e.companyId.equals(companyId))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  Future<List<Expense>> getExpenses({DateTime? startDate, DateTime? endDate}) {
    var query = db.select(db.expenses);
    if (startDate != null) {
      query = query..where((e) => e.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((e) => e.createdAt.isSmallerOrEqualValue(endDate));
    }
    return (query..orderBy([(e) => OrderingTerm.desc(e.createdAt)])).get();
  }

  Future<Expense> addExpense({
    required String companyId,
    required String storeId,
    String? employeeId,
    required String category,
    required double amount,
    String? description,
    DateTime? createdAt,
  }) async {
    final expId = _uuid.v4();
    final now = createdAt ?? DateTime.now();
    final companion = ExpensesCompanion.insert(
      id: expId,
      companyId: companyId,
      storeId: storeId,
      employeeId: Value(employeeId),
      category: Value(category),
      amount: Value(amount),
      description: Value(description),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    await db.into(db.expenses).insert(companion);
    return (db.select(db.expenses)..where((e) => e.id.equals(expId))).getSingle();
  }

  Future<void> deleteExpense(String id) async {
    await (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();
  }

  // --- SALES & FINANCIAL REPORT QUERY ---
  Future<SalesReportData> getSalesReportData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 1. Fetch completed transactions in range
    var txQuery = select(salesTransactions)
      ..where((t) => t.status.equals('completed') & t.isDeleted.equals(false));
    if (startDate != null) {
      txQuery = txQuery..where((t) => t.transactionDatetime.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      txQuery = txQuery..where((t) => t.transactionDatetime.isSmallerOrEqualValue(endDate));
    }
    final txs = await (txQuery..orderBy([(t) => OrderingTerm.desc(t.transactionDatetime)])).get();

    // 2. Fetch expenses in range
    final expList = await getExpenses(startDate: startDate, endDate: endDate);
    final totalExpenses = expList.fold(0.0, (sum, e) => sum + e.amount);

    if (txs.isEmpty) {
      return SalesReportData(
        startDate: startDate,
        endDate: endDate,
        grossSales: 0.0,
        discountTotal: 0.0,
        taxTotal: 0.0,
        netSales: 0.0,
        totalCogs: 0.0,
        grossProfit: 0.0,
        grossMarginPercent: 0.0,
        totalExpenses: totalExpenses,
        netProfit: -totalExpenses,
        netMarginPercent: 0.0,
        totalReceipts: 0,
        avgSalesValue: 0.0,
        topProducts: [],
        topCategories: [],
        paymentModes: [],
        topCustomers: [],
        soldBy: [],
        recentExpenses: expList,
      );
    }

    final txIds = txs.map((t) => t.id).toList();
    final allItems = await (select(transactionItems)..where((i) => i.salesTransactionId.isIn(txIds))).get();
    final allTenders = await (select(tenderPayments)..where((t) => t.salesTransactionId.isIn(txIds))).get();

    final allProducts = await select(products).get();
    final prodMap = {for (final p in allProducts) p.id: p};

    final allTypes = await select(productTypes).get();
    final catMap = {for (final c in allTypes) c.id: c.typeName};

    final allCustomers = await select(customers).get();
    final custMap = {for (final c in allCustomers) c.id: c};

    final allEmployees = await select(employees).get();
    final empMap = {for (final e in allEmployees) e.id: e};

    // Aggregate overall metrics
    double grossSales = 0.0;
    double discountTotal = 0.0;
    double taxTotal = 0.0;
    double netSales = 0.0;

    for (final tx in txs) {
      grossSales += tx.subtotal;
      discountTotal += tx.discountTotal;
      taxTotal += tx.taxTotal;
      netSales += tx.grandTotal;
    }

    // Aggregate Product & Category Sales
    double totalCogs = 0.0;
    final Map<String, ({
      String productId,
      String productName,
      String? variantName,
      String? categoryName,
      double qty,
      double revenue,
      double cost,
    })> productAgg = {};

    final Map<String, ({
      String categoryId,
      String categoryName,
      double qty,
      double revenue,
    })> categoryAgg = {};

    for (final item in allItems) {
      final prod = prodMap[item.productId];
      final unitCost = prod?.costPrice ?? 0.0;
      final lineCost = unitCost * item.quantity;
      totalCogs += lineCost;

      final pId = item.productId ?? 'deleted_${item.id}';
      final pName = item.productName ?? prod?.productName ?? 'Unknown (Deleted)';
      final vName = prod?.variantName;
      final cId = prod?.productTypeId ?? 'uncategorized';
      final cName = item.categoryName ?? catMap[cId] ?? 'General';

      // Product Aggregation
      if (productAgg.containsKey(pId)) {
        final current = productAgg[pId]!;
        productAgg[pId] = (
          productId: pId,
          productName: pName,
          variantName: vName,
          categoryName: cName,
          qty: current.qty + item.quantity,
          revenue: current.revenue + item.subtotal,
          cost: current.cost + lineCost,
        );
      } else {
        productAgg[pId] = (
          productId: pId,
          productName: pName,
          variantName: vName,
          categoryName: cName,
          qty: item.quantity,
          revenue: item.subtotal,
          cost: lineCost,
        );
      }

      // Category Aggregation
      if (categoryAgg.containsKey(cId)) {
        final existing = categoryAgg[cId]!;
        categoryAgg[cId] = (
          categoryId: cId,
          categoryName: cName,
          qty: existing.qty + item.quantity,
          revenue: existing.revenue + item.subtotal,
        );
      } else {
        categoryAgg[cId] = (
          categoryId: cId,
          categoryName: cName,
          qty: item.quantity,
          revenue: item.subtotal,
        );
      }
    }

    final topProducts = productAgg.values.map((p) {
      final profit = p.revenue - p.cost;
      return ProductSalesStat(
        productId: p.productId,
        productName: p.productName,
        variantName: p.variantName,
        categoryName: p.categoryName,
        quantitySold: p.qty,
        totalRevenue: p.revenue,
        totalCost: p.cost,
        profit: profit,
      );
    }).toList()
      ..sort((a, b) => b.quantitySold.compareTo(a.quantitySold));

    final topCategories = categoryAgg.values.map((c) {
      final share = netSales > 0 ? (c.revenue / netSales) * 100 : 0.0;
      return CategorySalesStat(
        categoryId: c.categoryId,
        categoryName: c.categoryName,
        quantitySold: c.qty,
        totalRevenue: c.revenue,
        sharePercentage: share,
      );
    }).toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    // Aggregate Payment Modes
    final Map<String, ({int count, double total})> tenderAgg = {};
    double totalTendered = 0.0;
    for (final tender in allTenders) {
      final method = tender.paymentMethod.toLowerCase();
      totalTendered += tender.amount;
      if (tenderAgg.containsKey(method)) {
        final existing = tenderAgg[method]!;
        tenderAgg[method] = (count: existing.count + 1, total: existing.total + tender.amount);
      } else {
        tenderAgg[method] = (count: 1, total: tender.amount);
      }
    }

    final paymentModes = tenderAgg.entries.map((e) {
      final share = totalTendered > 0 ? (e.value.total / totalTendered) * 100 : 0.0;
      return PaymentModeStat(
        method: e.key,
        count: e.value.count,
        totalAmount: e.value.total,
        sharePercentage: share,
      );
    }).toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    // Aggregate Top Customers
    final Map<String, ({String? customerId, String name, String tier, int orders, double spend})> customerAgg = {};
    for (final tx in txs) {
      final cId = tx.customerId;
      if (cId != null && custMap.containsKey(cId)) {
        final c = custMap[cId]!;
        if (customerAgg.containsKey(cId)) {
          final existing = customerAgg[cId]!;
          customerAgg[cId] = (
            customerId: cId,
            name: c.fullName,
            tier: c.loyaltyTier,
            orders: existing.orders + 1,
            spend: existing.spend + tx.grandTotal,
          );
        } else {
          customerAgg[cId] = (
            customerId: cId,
            name: c.fullName,
            tier: c.loyaltyTier,
            orders: 1,
            spend: tx.grandTotal,
          );
        }
      } else {
        // Walk-in guests
        const walkInKey = '__walkin__';
        if (customerAgg.containsKey(walkInKey)) {
          final existing = customerAgg[walkInKey]!;
          customerAgg[walkInKey] = (
            customerId: null,
            name: 'Walk-in / Guest',
            tier: 'Standard',
            orders: existing.orders + 1,
            spend: existing.spend + tx.grandTotal,
          );
        } else {
          customerAgg[walkInKey] = (
            customerId: null,
            name: 'Walk-in / Guest',
            tier: 'Standard',
            orders: 1,
            spend: tx.grandTotal,
          );
        }
      }
    }

    final topCustomers = customerAgg.values.map((c) => CustomerSalesStat(
      customerId: c.customerId,
      customerName: c.name,
      loyaltyTier: c.tier,
      ordersCount: c.orders,
      totalSpend: c.spend,
    )).toList()
      ..sort((a, b) => b.totalSpend.compareTo(a.totalSpend));

    // Aggregate Staff / Sold By
    final Map<String, ({String? empId, String name, String position, int count, double sales})> staffAgg = {};
    for (final tx in txs) {
      final eId = tx.employeeId;
      if (eId != null && empMap.containsKey(eId)) {
        final e = empMap[eId]!;
        final fullName = '${e.firstName} ${e.lastName}'.trim();
        if (staffAgg.containsKey(eId)) {
          final existing = staffAgg[eId]!;
          staffAgg[eId] = (
            empId: eId,
            name: fullName,
            position: e.position,
            count: existing.count + 1,
            sales: existing.sales + tx.grandTotal,
          );
        } else {
          staffAgg[eId] = (
            empId: eId,
            name: fullName,
            position: e.position,
            count: 1,
            sales: tx.grandTotal,
          );
        }
      } else {
        // Default register cashier
        const defaultStaffKey = '__main_cashier__';
        if (staffAgg.containsKey(defaultStaffKey)) {
          final existing = staffAgg[defaultStaffKey]!;
          staffAgg[defaultStaffKey] = (
            empId: null,
            name: 'Main Cashier / Register #1',
            position: 'Cashier',
            count: existing.count + 1,
            sales: existing.sales + tx.grandTotal,
          );
        } else {
          staffAgg[defaultStaffKey] = (
            empId: null,
            name: 'Main Cashier / Register #1',
            position: 'Cashier',
            count: 1,
            sales: tx.grandTotal,
          );
        }
      }
    }

    final soldBy = staffAgg.values.map((s) => StaffSalesStat(
      employeeId: s.empId,
      employeeName: s.name,
      position: s.position,
      receiptCount: s.count,
      totalSales: s.sales,
    )).toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    final grossProfit = netSales - totalCogs;
    final grossMarginPercent = netSales > 0 ? (grossProfit / netSales) * 100 : 0.0;
    final netProfit = grossProfit - totalExpenses;
    final netMarginPercent = netSales > 0 ? (netProfit / netSales) * 100 : 0.0;
    final totalReceipts = txs.length;
    final avgSalesValue = totalReceipts > 0 ? netSales / totalReceipts : 0.0;

    return SalesReportData(
      startDate: startDate,
      endDate: endDate,
      grossSales: grossSales,
      discountTotal: discountTotal,
      taxTotal: taxTotal,
      netSales: netSales,
      totalCogs: totalCogs,
      grossProfit: grossProfit,
      grossMarginPercent: grossMarginPercent,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
      netMarginPercent: netMarginPercent,
      totalReceipts: totalReceipts,
      avgSalesValue: avgSalesValue,
      topProducts: topProducts,
      topCategories: topCategories,
      paymentModes: paymentModes,
      topCustomers: topCustomers,
      soldBy: soldBy,
      recentExpenses: expList,
    );
  }

  // --- AUTH & DEVICE PROVISIONING QUERIES ---
  Future<Employee?> getEmployeeByPin(String storeId, String pinCode) {
    return (select(employees)
          ..where((e) => e.storeId.equals(storeId) & e.pinCode.equals(pinCode) & e.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<List<Employee>> getEmployeesForStore(String storeId) {
    return (select(employees)
          ..where((e) => e.storeId.equals(storeId) & e.isActive.equals(true))
          ..orderBy([(e) => OrderingTerm.asc(e.firstName)]))
        .get();
  }

  Future<void> addEmployee(EmployeesCompanion employee) async {
    final inserted = await into(employees).insertReturning(employee);
    
    // Queue sync for the new employee
    await queueSync('employees', inserted.id, 'INSERT', {
      'id': inserted.id,
      'company_id': inserted.companyId,
      'store_id': inserted.storeId,
      'profile_id': inserted.profileId,
      'email': inserted.email,
      'first_name': inserted.firstName,
      'last_name': inserted.lastName,
      'position': inserted.position,
      'pin_code': inserted.pinCode,
      'is_active': inserted.isActive,
    });
  }

  Future<void> updateEmployeePin(String employeeId, String newPin) async {
    await (update(employees)..where((e) => e.id.equals(employeeId)))
        .write(EmployeesCompanion(pinCode: Value(newPin)));
        
    await queueSync('employees', employeeId, 'UPDATE', {
      'pin_code': newPin,
    });
  }

  Future<void> updateEmployeeRole(String employeeId, String newPosition) async {
    await (update(employees)..where((e) => e.id.equals(employeeId)))
        .write(EmployeesCompanion(position: Value(newPosition)));
        
    await queueSync('employees', employeeId, 'UPDATE', {
      'position': newPosition,
    });
  }

  Future<void> updateEmployeeActive(String employeeId, bool isActive) async {
    await (update(employees)..where((e) => e.id.equals(employeeId)))
        .write(EmployeesCompanion(isActive: Value(isActive)));
        
    await queueSync('employees', employeeId, 'UPDATE', {
      'is_active': isActive,
    });
  }

  Future<Company?> getCompany(String companyId) {
    return (select(companies)..where((c) => c.id.equals(companyId))).getSingleOrNull();
  }

  Future<Store?> getStore(String storeId) {
    return (select(stores)..where((s) => s.id.equals(storeId))).getSingleOrNull();
  }

  Future<CashRegister?> getRegister(String registerId) {
    return (select(cashRegisters)..where((r) => r.id.equals(registerId))).getSingleOrNull();
  }

  Future<void> updateCompany(CompaniesCompanion company) async {
    await transaction(() async {
      await (update(companies)..where((c) => c.id.equals(company.id.value))).write(company);
      
      final updated = await getCompany(company.id.value);
      if (updated != null) {
        await queueSync('companies', updated.id, 'UPDATE', updated.toJson());
      }
    });
  }

  Future<void> updateStore(StoresCompanion store) async {
    await transaction(() async {
      await (update(stores)..where((s) => s.id.equals(store.id.value))).write(store);

      final updated = await getStore(store.id.value);
      if (updated != null) {
        await queueSync('stores', updated.id, 'UPDATE', updated.toJson());
      }
    });
  }

  Future<List<CashRegister>> getRegistersForStore(String storeId) {
    return (select(cashRegisters)..where((r) => r.storeId.equals(storeId))).get();
  }

  Future<List<Store>> getStores(String companyId) {
    return (select(stores)..where((s) => s.companyId.equals(companyId))).get();
  }


  Future<void> createStoreWithDefaults({
    required String companyId,
    required String storeName,
    String? address,
    String? phone,
  }) async {
    final storeId = _uuid.v4();
    final registerId = _uuid.v4();

    await transaction(() async {
      // 1. Create Store
      await into(stores).insert(
        StoresCompanion.insert(
          id: storeId,
          companyId: companyId,
          storeName: storeName,
          address: Value(address),
          phone: Value(phone),
        ),
      );

      // 2. Auto-create Register 1
      await into(cashRegisters).insert(
        CashRegistersCompanion.insert(
          id: registerId,
          companyId: companyId,
          storeId: storeId,
          registerName: 'Main Register 1',
        ),
      );

      // 3. Initialize Inventory for all products
      final allProducts = await (select(products)..where((p) => p.companyId.equals(companyId))).get();
      for (final p in allProducts) {
        await into(inventories).insert(
          InventoriesCompanion.insert(
            id: _uuid.v4(),
            companyId: companyId,
            storeId: storeId,
            productId: p.id,
            quantityOnHand: const Value(0),
            trackStock: const Value(true),
          ),
        );
      }
    });
  }
  Future<bool> hasAnyCompany() async {
    final countExp = companies.id.count();
    final query = selectOnly(companies)..addColumns([countExp]);
    final result = await query.map((row) => row.read(countExp)).getSingle();
    return (result ?? 0) > 0;
  }

  double _toDouble(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(attachedDatabase.syncQueue).go();
      await delete(attachedDatabase.tenderPayments).go();
      await delete(attachedDatabase.transactionItems).go();
      await delete(attachedDatabase.salesTransactions).go();
      await delete(attachedDatabase.customerPayments).go();
      await delete(attachedDatabase.customers).go();
      await delete(attachedDatabase.purchaseOrderItems).go();
      await delete(attachedDatabase.purchaseOrders).go();
      await delete(attachedDatabase.expenses).go();
      await delete(attachedDatabase.cashManagements).go();
      await delete(attachedDatabase.inventories).go();
      await delete(attachedDatabase.products).go();
      await delete(attachedDatabase.productTypes).go();
      await delete(attachedDatabase.employees).go();
      await delete(attachedDatabase.cashRegisters).go();
      await delete(attachedDatabase.stores).go();
      await delete(attachedDatabase.suppliers).go();
      await delete(attachedDatabase.companies).go();
    });
  }

  Future<void> cleanOrphanedInventories(String activeStoreId) async {
    if (activeStoreId.isNotEmpty && activeStoreId != 'default-store-001') {
      await (delete(attachedDatabase.inventories)
            ..where((i) => i.storeId.equals('default-store-001')))
          .go();
    }
  }

  Future<void> hydrateFromCloud({
    required Map<String, dynamic> company,
    required List<Map<String, dynamic>> stores,
    required List<Map<String, dynamic>> registers,
    required List<Map<String, dynamic>> employees,
    required List<Map<String, dynamic>> productTypes,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> inventories,
    List<Map<String, dynamic>> customers = const [],
    List<Map<String, dynamic>> customerPayments = const [],
    List<Map<String, dynamic>> cashManagements = const [],
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await clearAllData();
    }
    await upsertFromCloud(
      company: company,
      stores: stores,
      registers: registers,
      employees: employees,
      productTypes: productTypes,
      products: products,
      inventories: inventories,
      customers: customers,
      customerPayments: customerPayments,
      cashManagements: cashManagements,
    );
  }

  Future<void> upsertFromCloud({
    Map<String, dynamic>? company,
    List<Map<String, dynamic>> stores = const [],
    List<Map<String, dynamic>> registers = const [],
    List<Map<String, dynamic>> employees = const [],
    List<Map<String, dynamic>> productTypes = const [],
    List<Map<String, dynamic>> products = const [],
    List<Map<String, dynamic>> inventories = const [],
    List<Map<String, dynamic>> customers = const [],
    List<Map<String, dynamic>> customerPayments = const [],
    List<Map<String, dynamic>> cashManagements = const [],
    List<Map<String, dynamic>> salesTransactions = const [],
    List<Map<String, dynamic>> transactionItems = const [],
    List<Map<String, dynamic>> tenderPayments = const [],
  }) async {
    await transaction(() async {
      // Upsert Company
      if (company != null) {
        await into(companies).insert(
          CompaniesCompanion.insert(
            id: company['id'],
            name: company['name'],
            taxId: Value(company['tax_id']),
            address: Value(company['address']),
            phone: Value(company['phone']),
            email: Value(company['email']),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Stores
      for (final s in stores) {
        await into(this.stores).insert(
          StoresCompanion.insert(
            id: s['id'],
            companyId: s['company_id'],
            storeName: s['store_name'],
            address: Value(s['address']),
            phone: Value(s['phone']),
            isActive: Value(s['is_active'] ?? true),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Registers
      for (final r in registers) {
        await into(cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: r['id'],
            companyId: r['company_id'],
            storeId: r['store_id'],
            registerName: r['register_name'],
            status: Value(r['status'] ?? 'active'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Employees
      for (final e in employees) {
        await into(this.employees).insert(
          EmployeesCompanion.insert(
            id: e['id'],
            companyId: e['company_id'],
            storeId: Value(e['store_id']),
            firstName: e['first_name'],
            lastName: e['last_name'],
            position: Value(e['position'] ?? 'Cashier'),
            pinCode: Value(e['pin_code']),
            email: Value(e['email']),
            profileId: Value(e['profile_id']),
            isActive: Value(e['is_active'] ?? true),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Product Types
      for (final pt in productTypes) {
        await into(this.productTypes).insert(
          ProductTypesCompanion.insert(
            id: pt['id'],
            companyId: pt['company_id'],
            typeName: pt['type_name'],
            category: Value(pt['category']),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Products
      for (final p in products) {
        final existing = await (select(this.products)..where((tbl) => tbl.id.equals(p['id']))).getSingleOrNull();
        await into(this.products).insert(
          ProductsCompanion.insert(
            id: p['id'],
            companyId: p['company_id'],
            productTypeId: Value(p['product_type_id']),
            productName: p['product_name'],
            price: Value(_toDouble(p['price'])),
            costPrice: Value(_toDouble(p['cost_price'])),
            unit: Value(p['unit'] ?? 'pcs'),
            sellBy: Value(p['sell_by'] ?? 'unit'),
            variantName: Value(p['variant_name']),
            sku: Value(p['sku']),
            barcode: Value(p['barcode']),
            taxPercent: Value(_toDouble(p['tax_percent'])),
            trackExpiry: Value(p['track_expiry'] ?? false),
            expiryDate: Value(p['expiry_date'] != null ? DateTime.tryParse(p['expiry_date']) : null),
            imagePath: Value(existing?.imagePath),
            imageUrl: Value(p['image_url']),
            notes: Value(p['notes']),
            tags: Value(p['tags']),
            isActive: Value(p['is_active'] ?? true),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Inventories
      for (final i in inventories) {
        await into(this.inventories).insert(
          InventoriesCompanion.insert(
            id: i['id'],
            companyId: i['company_id'],
            storeId: i['store_id'],
            productId: i['product_id'],
            quantityOnHand: Value(_toDouble(i['quantity_on_hand'])),
            trackStock: Value(i['track_stock'] ?? true),
            reorderLevel: Value(_toDouble(i['reorder_level'], 10.0)),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Customers
      for (final c in customers) {
        await into(this.customers).insert(
          CustomersCompanion.insert(
            id: c['id'],
            companyId: c['company_id'],
            fullName: c['full_name'],
            email: Value(c['email']),
            phone: Value(c['phone']),
            address: Value(c['address']),
            loyaltyTier: Value(c['loyalty_tier'] ?? 'Bronze'),
            pointsBalance: Value(_toDouble(c['points_balance'])),
            dueAmount: Value(_toDouble(c['due_amount'])),
            creditLimit: Value(_toDouble(c['credit_limit'], 5000.0)),
            createdAt: Value(c['created_at'] != null ? DateTime.parse(c['created_at']) : DateTime.now()),
            updatedAt: Value(c['updated_at'] != null ? DateTime.parse(c['updated_at']) : DateTime.now()),
            isDeleted: Value(c['is_deleted'] ?? false),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Customer Payments
      for (final cp in customerPayments) {
        await into(this.customerPayments).insert(
          CustomerPaymentsCompanion.insert(
            id: cp['id'],
            companyId: cp['company_id'],
            storeId: Value(cp['store_id']),
            customerId: cp['customer_id'],
            amount: _toDouble(cp['amount']),
            paymentMethod: cp['payment_method'],
            notes: Value(cp['notes']),
            createdAt: Value(cp['created_at'] != null ? DateTime.parse(cp['created_at']) : DateTime.now()),
            updatedAt: Value(cp['updated_at'] != null ? DateTime.parse(cp['updated_at']) : DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Cash Managements (Drawer Shifts)
      for (final cm in cashManagements) {
        await into(this.cashManagements).insert(
          CashManagementsCompanion.insert(
            id: cm['id'],
            companyId: cm['company_id'],
            storeId: cm['store_id'],
            cashRegisterId: cm['cash_register_id'],
            employeeId: Value(cm['employee_id']),
            openTime: Value(cm['open_time'] != null ? (DateTime.tryParse(cm['open_time']) ?? DateTime.now()) : DateTime.now()),
            closeTime: Value(cm['close_time'] != null ? DateTime.tryParse(cm['close_time']) : null),
            openingBalance: Value(_toDouble(cm['opening_balance'])),
            closingBalance: Value(cm['closing_balance'] != null ? _toDouble(cm['closing_balance']) : null),
            expectedBalance: Value(cm['expected_balance'] != null ? _toDouble(cm['expected_balance']) : null),
            status: Value(cm['status'] ?? 'open'),
            notes: Value(cm['notes']),
            createdAt: Value(cm['created_at'] != null ? (DateTime.tryParse(cm['created_at']) ?? DateTime.now()) : DateTime.now()),
            updatedAt: Value(cm['updated_at'] != null ? (DateTime.tryParse(cm['updated_at']) ?? DateTime.now()) : DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Sales Transactions
      for (final tx in salesTransactions) {
        await into(this.salesTransactions).insert(
          SalesTransactionsCompanion.insert(
            id: tx['id'],
            companyId: tx['company_id'],
            storeId: tx['store_id'],
            cashRegisterId: Value(tx['cash_register_id']),
            employeeId: Value(tx['employee_id']),
            customerId: Value(tx['customer_id']),
            invoiceNo: tx['invoice_no'],
            transactionDatetime: Value(DateTime.parse(tx['transaction_datetime'])),
            subtotal: Value(_toDouble(tx['subtotal'])),
            discountTotal: Value(_toDouble(tx['discount_total'])),
            taxTotal: Value(_toDouble(tx['tax_total'])),
            grandTotal: Value(_toDouble(tx['grand_total'])),
            status: Value(tx['status'] ?? 'completed'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Transaction Items
      for (final ti in transactionItems) {
        await into(this.transactionItems).insert(
          TransactionItemsCompanion.insert(
            id: ti['id'],
            companyId: ti['company_id'],
            salesTransactionId: ti['sales_transaction_id'],
            productId: Value(ti['product_id']),
            productName: Value(ti['product_name']),
            categoryName: Value(ti['category_name']),
            sku: Value(ti['sku']),
            quantity: Value(_toDouble(ti['quantity'], 1.0)),
            unitPrice: Value(_toDouble(ti['unit_price'])),
            discountAmount: Value(_toDouble(ti['discount_amount'])),
            taxAmount: Value(_toDouble(ti['tax_amount'])),
            subtotal: Value(_toDouble(ti['subtotal'])),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }

      // Upsert Tender Payments
      for (final tp in tenderPayments) {
        await into(this.tenderPayments).insert(
          TenderPaymentsCompanion.insert(
            id: tp['id'],
            companyId: tp['company_id'],
            salesTransactionId: tp['sales_transaction_id'],
            paymentMethod: tp['payment_method'],
            amount: Value(_toDouble(tp['amount'])),
            amountTendered: Value(_toDouble(tp['amount_tendered'])),
            changeAmount: Value(_toDouble(tp['change_amount'])),
            referenceNo: Value(tp['reference_no']),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
  Future<Map<String, String>> onboardNewCompany({
    required String companyName,
    required String storeName,
    required String firstName,
    required String lastName,
    String? pinCode,
    required String email,
    required String profileId,
  }) async {
    final companyId = _uuid.v4();
    final storeId = _uuid.v4();
    final registerId = _uuid.v4();
    final employeeId = _uuid.v4();

    // 1. Call Secure RPC to create company in cloud
    try {
      if (Supabase.instance.isInitialized) {
        final supabase = Supabase.instance.client;
        await supabase.rpc('create_new_company', params: {
          'c_id': companyId,
          'c_name': companyName,
          's_id': storeId,
          's_name': storeName,
          'r_id': registerId,
          'e_id': employeeId,
          'e_first': firstName,
          'e_last': lastName,
          'e_pin': pinCode ?? '',
          'e_email': email,
          'e_profile_id': profileId,
        });
      }
    } catch (e) {
      throw Exception('Failed to create business in the cloud: $e');
    }

    // 2. Save locally
    await transaction(() async {
      // Create Company
      await into(companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: companyName,
        ),
      );

      // 2. Create First Store
      await into(stores).insert(
        StoresCompanion.insert(
          id: storeId,
          companyId: companyId,
          storeName: storeName,
        ),
      );

      // 3. Create First Cash Register
      await into(cashRegisters).insert(
        CashRegistersCompanion.insert(
          id: registerId,
          companyId: companyId,
          storeId: storeId,
          registerName: 'Main Terminal',
        ),
      );

      // 4. Create Admin Employee
      await into(employees).insert(
        EmployeesCompanion.insert(
          id: employeeId,
          companyId: companyId,
          storeId: Value(storeId),
          firstName: firstName,
          lastName: lastName,
          position: const Value('Admin'),
          pinCode: Value(pinCode),
          email: Value(email),
          profileId: Value(profileId),
        ),
      );
    });

    return {
      'companyId': companyId,
      'storeId': storeId,
      'registerId': registerId,
      'employeeId': employeeId,
    };
  }
}


class ShiftSalesSummary {
  final double openingBalance;
  final double cashSales;
  final double nonCashSales;
  final int transactionCount;
  final double expectedBalance;

  ShiftSalesSummary({
    required this.openingBalance,
    required this.cashSales,
    required this.nonCashSales,
    required this.transactionCount,
    required this.expectedBalance,
  });
}

class TransactionLineItemDetail {
  final TransactionItem item;
  final Product product;

  TransactionLineItemDetail({required this.item, required this.product});
}

class TransactionDetail {
  final SalesTransaction transaction;
  final List<TransactionLineItemDetail> items;
  final List<TenderPayment> tenders;
  final String? customerName;

  TransactionDetail({
    required this.transaction,
    required this.items,
    required this.tenders,
    this.customerName,
  });

  String get primaryPaymentMethod {
    if (tenders.isEmpty) return 'cash';
    return tenders.first.paymentMethod;
  }

  int get totalItemCount {
    return items.length;
  }

  double get totalQuantity {
    return items.fold(0.0, (sum, i) => sum + i.item.quantity);
  }
}

class ProductSalesStat {
  final String productId;
  final String productName;
  final String? variantName;
  final String? categoryName;
  final double quantitySold;
  final double totalRevenue;
  final double totalCost;
  final double profit;

  ProductSalesStat({
    required this.productId,
    required this.productName,
    this.variantName,
    this.categoryName,
    required this.quantitySold,
    required this.totalRevenue,
    required this.totalCost,
    required this.profit,
  });

  double get profitMarginPercent => totalRevenue > 0 ? (profit / totalRevenue) * 100 : 0.0;
}

class CategorySalesStat {
  final String categoryId;
  final String categoryName;
  final double quantitySold;
  final double totalRevenue;
  final double sharePercentage;

  CategorySalesStat({
    required this.categoryId,
    required this.categoryName,
    required this.quantitySold,
    required this.totalRevenue,
    required this.sharePercentage,
  });
}

class PaymentModeStat {
  final String method;
  final int count;
  final double totalAmount;
  final double sharePercentage;

  PaymentModeStat({
    required this.method,
    required this.count,
    required this.totalAmount,
    required this.sharePercentage,
  });

  String get displayName {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'gcash':
        return 'GCash';
      case 'maya':
        return 'Maya';
      case 'card':
      case 'credit_card':
      case 'debit_card':
        return 'Card';
      default:
        return method.toUpperCase();
    }
  }
}

class CustomerSalesStat {
  final String? customerId;
  final String customerName;
  final String loyaltyTier;
  final int ordersCount;
  final double totalSpend;

  CustomerSalesStat({
    this.customerId,
    required this.customerName,
    required this.loyaltyTier,
    required this.ordersCount,
    required this.totalSpend,
  });
}

class StaffSalesStat {
  final String? employeeId;
  final String employeeName;
  final String position;
  final int receiptCount;
  final double totalSales;

  StaffSalesStat({
    this.employeeId,
    required this.employeeName,
    required this.position,
    required this.receiptCount,
    required this.totalSales,
  });

  double get averageTicket => receiptCount > 0 ? totalSales / receiptCount : 0.0;
}

class SalesReportData {
  final DateTime? startDate;
  final DateTime? endDate;
  final double grossSales;
  final double discountTotal;
  final double taxTotal;
  final double netSales;
  final double totalCogs;
  final double grossProfit;
  final double grossMarginPercent;
  final double totalExpenses;
  final double netProfit;
  final double netMarginPercent;
  final int totalReceipts;
  final double avgSalesValue;
  final List<ProductSalesStat> topProducts;
  final List<CategorySalesStat> topCategories;
  final List<PaymentModeStat> paymentModes;
  final List<CustomerSalesStat> topCustomers;
  final List<StaffSalesStat> soldBy;
  final List<Expense> recentExpenses;

  SalesReportData({
    this.startDate,
    this.endDate,
    required this.grossSales,
    required this.discountTotal,
    required this.taxTotal,
    required this.netSales,
    required this.totalCogs,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.totalExpenses,
    required this.netProfit,
    required this.netMarginPercent,
    required this.totalReceipts,
    required this.avgSalesValue,
    required this.topProducts,
    required this.topCategories,
    required this.paymentModes,
    required this.topCustomers,
    required this.soldBy,
    required this.recentExpenses,
  });
}
