import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/daos/pos_dao.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/services/transaction_export_service.dart';

void main() {
  late AppDatabase db;
  late PosDao posDao;

  setUp(() {
    // In-memory SQLite database for isolated, lightning-fast testing
    db = AppDatabase(NativeDatabase.memory());
    posDao = PosDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Tenancy and catalog insertion works with relational integrity', () async {
    const companyId = 'comp-100';
    const storeId = 'store-200';
    const registerId = 'reg-300';
    const catId = 'cat-400';
    const prodId = 'prod-500';

    // 1. Insert Company
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Acme Supermarket',
            taxId: const Value('123-456-789'),
            address: const Value('123 Main St'),
          ),
        );

    // 2. Insert Store
    await db.into(db.stores).insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            storeName: 'Downtown Branch',
          ),
        );

    // 3. Insert Cash Register
    await db.into(db.cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: registerId,
            companyId: companyId,
            storeId: storeId,
            registerName: 'Lane 1 POS',
          ),
        );

    // 4. Insert Category & Product
    await db.into(db.productTypes).insert(
          ProductTypesCompanion.insert(
            id: catId,
            companyId: companyId,
            typeName: 'Beverages',
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: prodId,
            companyId: companyId,
            productName: 'Bottled Spring Water 500ml',
            sku: const Value('BW-500'),
            barcode: const Value('4800012345678'),
            price: const Value(25.00),
            productTypeId: const Value(catId),
          ),
        );

    // 5. Initial Inventory Stock (100 pcs)
    await db.into(db.inventories).insert(
          InventoriesCompanion.insert(
            id: 'inv-1',
            companyId: companyId,
            storeId: storeId,
            productId: prodId,
            quantityOnHand: const Value(100.0),
            trackStock: const Value(true),
          ),
        );

    final products = await posDao.getActiveProducts(companyId);
    expect(products.length, 1);
    expect(products.first.productName, 'Bottled Spring Water 500ml');

    final inv = await posDao.getInventoryForProduct(storeId, prodId);
    expect(inv, isNotNull);
    expect(inv!.quantityOnHand, 100.0);
  });

  test('Offline Sales Transaction updates stock, saves tenders, and queues for sync', () async {
    const companyId = 'comp-100';
    const storeId = 'store-200';
    const registerId = 'reg-300';
    const prodId = 'prod-500';

    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Acme Supermarket',
          ),
        );
    await db.into(db.stores).insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            storeName: 'Downtown Branch',
          ),
        );
    await db.into(db.cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: registerId,
            companyId: companyId,
            storeId: storeId,
            registerName: 'Lane 1 POS',
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: prodId,
            companyId: companyId,
            productName: 'Bottled Spring Water 500ml',
            price: const Value(25.00),
          ),
        );
    await db.into(db.inventories).insert(
          InventoriesCompanion.insert(
            id: 'inv-1',
            companyId: companyId,
            storeId: storeId,
            productId: prodId,
            quantityOnHand: const Value(50.0),
            trackStock: const Value(true),
          ),
        );

    // Execute atomic offline sale: 2 bottles @ 25.00 = 50.00
    final saleId = await posDao.createSaleTransaction(
      companyId: companyId,
      storeId: storeId,
      registerId: registerId,
      invoiceNo: 'INV-STR01-REG01-0001',
      subtotal: 50.0,
      discountTotal: 0.0,
      taxTotal: 6.0,
      grandTotal: 56.0,
      items: [
        (
          productId: prodId,
          quantity: 2.0,
          unitPrice: 25.0,
          discountAmount: 0.0,
          taxAmount: 6.0,
        ),
      ],
      tenders: [
        (
          paymentMethod: 'cash',
          amount: 56.0,
          amountTendered: 100.0,
          changeAmount: 44.0,
          refNo: null,
        ),
      ],
    );

    expect(saleId, isNotEmpty);

    // Verify inventory reduced by 2
    final invAfter = await posDao.getInventoryForProduct(storeId, prodId);
    expect(invAfter!.quantityOnHand, 48.0);

    // Verify transaction records
    final sale = await (db.select(db.salesTransactions)..where((s) => s.id.equals(saleId))).getSingle();
    expect(sale.grandTotal, 56.0);
    expect(sale.invoiceNo, 'INV-STR01-REG01-0001');

    final items = await (db.select(db.transactionItems)..where((i) => i.salesTransactionId.equals(saleId))).get();
    expect(items.length, 1);
    expect(items.first.quantity, 2.0);

    final tenders = await (db.select(db.tenderPayments)..where((t) => t.salesTransactionId.equals(saleId))).get();
    expect(tenders.length, 1);
    expect(tenders.first.paymentMethod, 'cash');
    expect(tenders.first.changeAmount, 44.0);

    // Verify Sync Queue entry
    final queuedSync = await (db.select(db.syncQueue)..where((q) => q.recordId.equals(saleId))).getSingle();
    expect(queuedSync.targetTable, 'sales_transactions');
    expect(queuedSync.action, 'INSERT');
    expect(queuedSync.status, 'pending');
  });

  test('Cash shift opening and closing', () async {
    const companyId = 'comp-100';
    const storeId = 'store-200';
    const registerId = 'reg-300';

    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Acme Supermarket',
          ),
        );
    await db.into(db.stores).insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            storeName: 'Downtown Branch',
          ),
        );
    await db.into(db.cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: registerId,
            companyId: companyId,
            storeId: storeId,
            registerName: 'Lane 1 POS',
          ),
        );

    // Open Shift with 1,000 opening float
    final shiftId = await posDao.openCashShift(
      companyId: companyId,
      storeId: storeId,
      registerId: registerId,
      openingBalance: 1000.0,
    );

    var shift = await (db.select(db.cashManagements)..where((s) => s.id.equals(shiftId))).getSingle();
    expect(shift.status, 'open');
    expect(shift.openingBalance, 1000.0);
    expect(shift.closeTime, isNull);

    // Close Shift with 5,500 counted cash
    await posDao.closeCashShift(
      shiftId: shiftId,
      closingBalance: 5500.0,
      expectedBalance: 5500.0,
      notes: 'Shift balanced accurately',
    );

    shift = await (db.select(db.cashManagements)..where((s) => s.id.equals(shiftId))).getSingle();
    expect(shift.status, 'closed');
    expect(shift.closingBalance, 5500.0);
    expect(shift.closeTime, isNotNull);
  });

  test('Transaction detail fetching and multi-sheet Excel/CSV export generation', () async {
    await DatabaseSeeder.seedIfEmpty(db);

    final details = await posDao.getAllTransactionDetails();
    expect(details.isNotEmpty, true);
    expect(details.length, 5); // 5 seeded transactions

    final firstDetail = details.first;
    expect(firstDetail.items.isNotEmpty, true);
    expect(firstDetail.tenders.isNotEmpty, true);
    expect(firstDetail.primaryPaymentMethod.isNotEmpty, true);

    // Single transaction detail lookup
    final singleLookup = await posDao.getTransactionDetail(firstDetail.transaction.id);
    expect(singleLookup, isNotNull);
    expect(singleLookup!.transaction.invoiceNo, firstDetail.transaction.invoiceNo);
    expect(singleLookup.items.length, firstDetail.items.length);

    // Test Excel workbook generation (.xlsx)
    final excelBytes = TransactionExportService.generateExcelWorkbook(
      transactions: details,
      companyName: 'Apex Supermarket & POS',
      storeName: 'Main Retail Branch',
    );
    expect(excelBytes.isNotEmpty, true);
    expect(excelBytes.length > 500, true); // Valid non-trivial zip/xlsx binary

    // Test CSV report generation
    final csvContent = TransactionExportService.generateCsvReport(
      transactions: details,
      companyName: 'Apex Supermarket & POS',
      includeItemDetails: false,
    );
    expect(csvContent.startsWith('\uFEFF'), true);
    expect(csvContent.contains('INV-2026-'), true);
    expect(csvContent.contains('CASH'), true);

    // Test Itemized CSV
    final itemizedCsv = TransactionExportService.generateCsvReport(
      transactions: details,
      includeItemDetails: true,
    );
    expect(itemizedCsv.contains('Product Name'), true);
    expect(itemizedCsv.contains('Variant'), true);
  });

  test('Multi-Subitem (Variant) catalog insertion, independent stock tracking, and sales execution', () async {
    const companyId = 'comp-sub-001';
    const storeId = 'store-sub-001';
    const registerId = 'reg-sub-001';
    const catId = 'cat-apparel-001';

    // 1. Seed tenant structure
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Apparel Store Inc',
      ),
    );
    await db.into(db.stores).insert(
      StoresCompanion.insert(
        id: storeId,
        companyId: companyId,
        storeName: 'Main Mall Store',
      ),
    );
    await db.into(db.cashRegisters).insert(
      CashRegistersCompanion.insert(
        id: registerId,
        companyId: companyId,
        storeId: storeId,
        registerName: 'Checkout 1',
      ),
    );
    await db.into(db.productTypes).insert(
      ProductTypesCompanion.insert(
        id: catId,
        companyId: companyId,
        typeName: 'Apparel',
      ),
    );

    // 2. Insert 3 Subitems under "Cotton T-Shirt": Small (₱200), Medium (₱220), Large (₱250)
    final subitems = [
      (id: 'prod-tshirt-s', variant: 'Small', price: 200.0, sku: 'TS-S', stock: 15.0),
      (id: 'prod-tshirt-m', variant: 'Medium', price: 220.0, sku: 'TS-M', stock: 20.0),
      (id: 'prod-tshirt-l', variant: 'Large', price: 250.0, sku: 'TS-L', stock: 10.0),
    ];

    await db.transaction(() async {
      for (final sub in subitems) {
        await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: sub.id,
            companyId: companyId,
            productTypeId: const Value(catId),
            productName: 'Cotton T-Shirt',
            variantName: Value(sub.variant),
            price: Value(sub.price),
            sku: Value(sub.sku),
            sellBy: const Value('unit'),
            unit: const Value('pcs'),
          ),
        );
        await db.into(db.inventories).insert(
          InventoriesCompanion.insert(
            id: 'inv-${sub.id}',
            companyId: companyId,
            storeId: storeId,
            productId: sub.id,
            quantityOnHand: Value(sub.stock),
            trackStock: const Value(true),
          ),
        );
      }
    });

    // Verify all 3 subitems exist in database
    final catalog = await posDao.getActiveProducts(companyId);
    expect(catalog.length, 3);
    for (final item in catalog) {
      expect(item.productName, 'Cotton T-Shirt');
      expect(item.variantName, isNotNull);
    }

    // 3. Perform a sale: 2 pcs of Small (₱200 each = ₱400) and 1 pc of Large (₱250 = ₱250)
    final saleId = await posDao.createSaleTransaction(
      companyId: companyId,
      storeId: storeId,
      registerId: registerId,
      invoiceNo: 'INV-SUB-001',
      subtotal: 650.0,
      discountTotal: 0.0,
      taxTotal: 0.0,
      grandTotal: 650.0,
      items: [
        (productId: 'prod-tshirt-s', quantity: 2.0, unitPrice: 200.0, discountAmount: 0.0, taxAmount: 0.0),
        (productId: 'prod-tshirt-l', quantity: 1.0, unitPrice: 250.0, discountAmount: 0.0, taxAmount: 0.0),
      ],
      tenders: [
        (paymentMethod: 'cash', amount: 650.0, amountTendered: 1000.0, changeAmount: 350.0, refNo: null),
      ],
    );

    expect(saleId, isNotNull);

    // 4. Verify stock decrement:
    // Small: 15 - 2 = 13
    final invSmall = await posDao.getInventoryForProduct(storeId, 'prod-tshirt-s');
    expect(invSmall!.quantityOnHand, 13.0);

    // Medium: 20 untouched
    final invMedium = await posDao.getInventoryForProduct(storeId, 'prod-tshirt-m');
    expect(invMedium!.quantityOnHand, 20.0);

    // Large: 10 - 1 = 9
    final invLarge = await posDao.getInventoryForProduct(storeId, 'prod-tshirt-l');
    expect(invLarge!.quantityOnHand, 9.0);

    // 5. Verify transaction detail query joins variant names accurately
    final detail = await posDao.getTransactionDetail(saleId);
    expect(detail, isNotNull);
    expect(detail!.items.length, 2);

    final itemSmall = detail.items.firstWhere((i) => i.product.variantName == 'Small');
    expect(itemSmall.item.quantity, 2.0);
    expect(itemSmall.item.unitPrice, 200.0);
    expect(itemSmall.product.productName, 'Cotton T-Shirt');

    final itemLarge = detail.items.firstWhere((i) => i.product.variantName == 'Large');
    expect(itemLarge.item.quantity, 1.0);
    expect(itemLarge.item.unitPrice, 250.0);
    expect(itemLarge.product.productName, 'Cotton T-Shirt');
  });

  test('Sales Report calculations, expenses tracking, and multi-sheet financial export', () async {
    await DatabaseSeeder.seedIfEmpty(db);

    // Clear previous seeded transactions for an isolated mathematical verification
    await db.delete(db.tenderPayments).go();
    await db.delete(db.transactionItems).go();
    await db.delete(db.salesTransactions).go();
    await db.delete(db.expenses).go();

    // Initial empty state check
    final initialReport = await posDao.getSalesReportData();
    expect(initialReport.totalReceipts, 0);
    expect(initialReport.netSales, 0.0);
    expect(initialReport.totalExpenses, 0.0);

    // 1. Create a customer
    final customer = await posDao.addCustomer(
      companyId: 'default-company-001',
      fullName: 'Juan Luna',
      phone: '0917-000-1111',
    );

    // Fetch products
    final prods = await db.select(db.products).get();
    final p1 = prods.firstWhere((p) => p.sku == 'BEV-001'); // price 110, cost 45
    final p2 = prods.firstWhere((p) => p.sku == 'RCE-001'); // price 52, cost 38

    // 2. Perform a transaction
    // p1: 2 pcs @ 110 = 220, disc 10, tax 26 => line subtotal 236. cost = 2*45 = 90
    // p2: 1 pc @ 52 = 52, disc 2, tax 6 => line subtotal 56. cost = 1*38 = 38
    // Total subtotal: 272, disc: 12, tax: 32, grandTotal: 292
    final saleId = await posDao.createSaleTransaction(
      companyId: 'default-company-001',
      storeId: 'default-store-001',
      registerId: 'default-reg-001',
      customerId: customer.id,
      invoiceNo: 'INV-REP-001',
      subtotal: 272.0,
      discountTotal: 12.0,
      taxTotal: 32.0,
      grandTotal: 292.0,
      items: [
        (productId: p1.id, quantity: 2.0, unitPrice: 110.0, discountAmount: 10.0, taxAmount: 26.0),
        (productId: p2.id, quantity: 1.0, unitPrice: 52.0, discountAmount: 2.0, taxAmount: 6.0),
      ],
      tenders: [
        (paymentMethod: 'gcash', amount: 292.0, amountTendered: 292.0, changeAmount: 0.0, refNo: 'GCASH-12345'),
      ],
    );
    expect(saleId, isNotEmpty);

    // 3. Add an Operating Expense (e.g. Electric Bill ₱100)
    final expense = await posDao.addExpense(
      companyId: 'default-company-001',
      storeId: 'default-store-001',
      category: 'Utilities',
      amount: 100.0,
      description: 'Store Electricity Bill - Meralco',
    );
    expect(expense.id, isNotEmpty);

    // 4. Query SalesReportData
    final report = await posDao.getSalesReportData();
    expect(report.totalReceipts, 1);
    expect(report.netSales, 292.0);
    expect(report.grossSales, 272.0);
    expect(report.taxTotal, 32.0);
    expect(report.discountTotal, 12.0);
    expect(report.avgSalesValue, 292.0);

    // COGS = 2*45 + 1*38 = 90 + 38 = 128
    expect(report.totalCogs, 128.0);
    // Gross Profit = Net Sales (292) - COGS (128) = 164
    expect(report.grossProfit, 164.0);
    // Operating Expenses = 100
    expect(report.totalExpenses, 100.0);
    // Net Profit = Gross Profit (164) - Operating Expenses (100) = 64
    expect(report.netProfit, 64.0);

    // Top Stocks
    expect(report.topProducts.length, 2);
    expect(report.topProducts.first.productName, contains('Americano'));
    expect(report.topProducts.first.quantitySold, 2.0);

    // Top Categories
    expect(report.topCategories.isNotEmpty, true);

    // Payment Modes
    expect(report.paymentModes.length, 1);
    expect(report.paymentModes.first.method, 'gcash');
    expect(report.paymentModes.first.totalAmount, 292.0);

    // Top Customers
    expect(report.topCustomers.length, 1);
    expect(report.topCustomers.first.customerName, 'Juan Luna');
    expect(report.topCustomers.first.totalSpend, 292.0);

    // Sold By (Staff)
    expect(report.soldBy.length, 1);
    expect(report.soldBy.first.employeeName, contains('Cashier'));

    // 5. Test Excel Export generation
    final excelBytes = TransactionExportService.generateSalesReportWorkbook(reportData: report);
    expect(excelBytes, isNotNull);
    expect(excelBytes.length, greaterThan(100));

    // 6. Delete Expense and verify reactivity
    await posDao.deleteExpense(expense.id);
    final reportAfterDelete = await posDao.getSalesReportData();
    expect(reportAfterDelete.totalExpenses, 0.0);
    expect(reportAfterDelete.netProfit, 164.0);
  });

  test('Database foreign keys and schema migration strategy integrity', () async {
    // 1. Verify schemaVersion
    expect(db.schemaVersion, 7);

    // 2. Verify PRAGMA foreign_keys is ON
    final result = await db.customSelect('PRAGMA foreign_keys;').getSingle();
    expect(result.data['foreign_keys'], 1);
  });

  test('Realtime and cloud upsert parses Postgres String numeric fields safely into SQLite', () async {
    const companyId = 'comp-rt-001';
    const storeId = 'store-rt-001';

    await db.into(db.companies).insert(
      CompaniesCompanion.insert(id: companyId, name: 'Realtime Retail'),
    );
    await db.into(db.stores).insert(
      StoresCompanion.insert(id: storeId, companyId: companyId, storeName: 'Main'),
    );

    // Simulate raw Supabase payloads where Postgres numeric columns are formatted as Strings
    await posDao.upsertFromCloud(
      products: [
        {
          'id': 'prod-rt-001',
          'company_id': companyId,
          'product_name': 'Iced Caramel Macchiato',
          'price': '145.50',
          'cost_price': '60.00',
          'tax_percent': '12.00',
          'unit': 'cup',
          'sell_by': 'unit',
          'is_active': true,
        },
      ],
      inventories: [
        {
          'id': 'inv-rt-001',
          'company_id': companyId,
          'store_id': storeId,
          'product_id': 'prod-rt-001',
          'quantity_on_hand': '35.00',
          'reorder_level': '10.00',
          'track_stock': true,
        },
      ],
      salesTransactions: [
        {
          'id': 'sale-rt-001',
          'company_id': companyId,
          'store_id': storeId,
          'invoice_no': 'INV-RT-900',
          'transaction_datetime': DateTime.now().toIso8601String(),
          'subtotal': '145.50',
          'discount_total': '0.00',
          'tax_total': '15.59',
          'grand_total': '145.50',
          'status': 'completed',
        },
      ],
      transactionItems: [
        {
          'id': 'item-rt-001',
          'company_id': companyId,
          'sales_transaction_id': 'sale-rt-001',
          'product_id': 'prod-rt-001',
          'product_name': 'Iced Caramel Macchiato',
          'quantity': '1.00',
          'unit_price': '145.50',
          'discount_amount': '0.00',
          'tax_amount': '15.59',
          'subtotal': '145.50',
        },
      ],
      tenderPayments: [
        {
          'id': 'tender-rt-001',
          'company_id': companyId,
          'sales_transaction_id': 'sale-rt-001',
          'payment_method': 'cash',
          'amount': '145.50',
          'amount_tendered': '200.00',
          'change_amount': '54.50',
        },
      ],
    );

    // Verify SQLite Product
    final prod = await (db.select(db.products)..where((p) => p.id.equals('prod-rt-001'))).getSingle();
    expect(prod.productName, 'Iced Caramel Macchiato');
    expect(prod.price, 145.50);
    expect(prod.costPrice, 60.00);
    expect(prod.taxPercent, 12.00);

    // Verify SQLite Inventory
    final inv = await (db.select(db.inventories)..where((i) => i.id.equals('inv-rt-001'))).getSingle();
    expect(inv.quantityOnHand, 35.0);
    expect(inv.reorderLevel, 10.0);

    // Verify SQLite Sale & Tender
    final sale = await (db.select(db.salesTransactions)..where((s) => s.id.equals('sale-rt-001'))).getSingle();
    expect(sale.grandTotal, 145.50);

    final tender = await (db.select(db.tenderPayments)..where((t) => t.id.equals('tender-rt-001'))).getSingle();
    expect(tender.amountTendered, 200.0);
    expect(tender.changeAmount, 54.50);
  });

  test('Customer offline insertion queues sync, and cloud upsert populates customers and customer payments', () async {
    const companyId = 'comp-sync-cust';
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Sync Test Company',
      ),
    );

    // 1. Add customer via posDao
    final newCustomer = await posDao.addCustomer(
      companyId: companyId,
      fullName: 'Alice Walker',
      phone: '09123456789',
      email: 'alice@example.com',
      address: '742 Evergreen Terrace',
      loyaltyTier: 'Gold',
      pointsBalance: 150.0,
      creditLimit: 10000.0,
    );

    expect(newCustomer.fullName, 'Alice Walker');
    expect(newCustomer.loyaltyTier, 'Gold');
    expect(newCustomer.isDeleted, false);

    // Verify syncQueue item was created for INSERT
    final pendingInserts = await (db.select(db.syncQueue)
          ..where((s) => s.targetTable.equals('customers') & s.action.equals('INSERT')))
        .get();
    expect(pendingInserts.length, 1);
    expect(pendingInserts.first.recordId, newCustomer.id);
    expect(pendingInserts.first.payload.contains('Alice Walker'), isTrue);

    // 2. Update customer via posDao
    await posDao.updateCustomer(
      id: newCustomer.id,
      fullName: 'Alice W. Johnson',
      phone: '09987654321',
      loyaltyTier: 'Platinum',
      pointsBalance: 250.0,
    );

    final updatedCust = await (db.select(db.customers)..where((c) => c.id.equals(newCustomer.id))).getSingle();
    expect(updatedCust.fullName, 'Alice W. Johnson');
    expect(updatedCust.loyaltyTier, 'Platinum');

    // Verify syncQueue item for UPDATE
    final pendingUpdates = await (db.select(db.syncQueue)
          ..where((s) => s.targetTable.equals('customers') & s.action.equals('UPDATE')))
        .get();
    expect(pendingUpdates.length, 1);
    expect(pendingUpdates.first.recordId, newCustomer.id);
    expect(pendingUpdates.first.payload.contains('Alice W. Johnson'), isTrue);

    // 3. Delete (archive) customer via posDao
    await posDao.deleteCustomer(newCustomer.id);
    final deletedCust = await (db.select(db.customers)..where((c) => c.id.equals(newCustomer.id))).getSingle();
    expect(deletedCust.isDeleted, isTrue);

    // 4. Test upsertFromCloud for customers and customer payments
    const cloudCustId = 'cust-cloud-001';
    const cloudPayId = 'pay-cloud-001';
    await posDao.upsertFromCloud(
      customers: [
        {
          'id': cloudCustId,
          'company_id': companyId,
          'full_name': 'Bob Ross',
          'phone': '09112223344',
          'email': 'bob@rossart.com',
          'loyalty_tier': 'Silver',
          'points_balance': '75.50',
          'due_amount': '0.00',
          'credit_limit': '5000.00',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'is_deleted': false,
        },
      ],
      customerPayments: [
        {
          'id': cloudPayId,
          'company_id': companyId,
          'customer_id': cloudCustId,
          'amount': '500.00',
          'payment_method': 'cash',
          'notes': 'Initial credit balance payment',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      ],
    );

    final fetchedCloudCust = await (db.select(db.customers)..where((c) => c.id.equals(cloudCustId))).getSingle();
    expect(fetchedCloudCust.fullName, 'Bob Ross');
    expect(fetchedCloudCust.loyaltyTier, 'Silver');
    expect(fetchedCloudCust.pointsBalance, 75.50);

    final fetchedCloudPay = await (db.select(db.customerPayments)..where((p) => p.id.equals(cloudPayId))).getSingle();
    expect(fetchedCloudPay.amount, 500.00);
    expect(fetchedCloudPay.paymentMethod, 'cash');
  });

  test('Store credit sales increment dueAmount and award points; debt settlements decrease dueAmount', () async {
    const companyId = 'comp-credit-001';
    const storeId = 'store-credit-001';
    const registerId = 'reg-credit-001';
    const productId = 'prod-credit-001';

    // 1. Seed tenant, product, and customer
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(id: companyId, name: 'Credit Test Co'),
    );
    await db.into(db.stores).insert(
      StoresCompanion.insert(id: storeId, companyId: companyId, storeName: 'Credit Branch'),
    );
    await db.into(db.cashRegisters).insert(
      CashRegistersCompanion.insert(id: registerId, companyId: companyId, storeId: storeId, registerName: 'Reg 1'),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: productId,
        companyId: companyId,
        productName: 'Cement 50kg',
        price: const Value(350.0),
        costPrice: const Value(280.0),
      ),
    );
    await db.into(db.inventories).insert(
      InventoriesCompanion.insert(
        id: 'inv-credit-001',
        companyId: companyId,
        storeId: storeId,
        productId: productId,
        quantityOnHand: const Value(100.0),
      ),
    );

    // Add customer with 0 due amount, 5000 limit
    await posDao.addCustomer(
      companyId: companyId,
      fullName: 'Carlos Mendoza',
      phone: '09223334444',
      creditLimit: 5000.0,
      pointsBalance: 10.0,
    );
    final custInitial = await (db.select(db.customers)..where((c) => c.fullName.equals('Carlos Mendoza'))).getSingle();
    expect(custInitial.dueAmount, 0.0);
    expect(custInitial.pointsBalance, 10.0);

    // 2. Perform checkout using 'credit' tender (grandTotal: ₱700.00 for 2 bags)
    final saleId = await posDao.createSaleTransaction(
      companyId: companyId,
      storeId: storeId,
      registerId: registerId,
      customerId: custInitial.id,
      invoiceNo: 'INV-CREDIT-001',
      subtotal: 700.0,
      discountTotal: 0.0,
      taxTotal: 0.0,
      grandTotal: 700.0,
      items: [
        (productId: productId, quantity: 2.0, unitPrice: 350.0, discountAmount: 0.0, taxAmount: 0.0),
      ],
      tenders: [
        (paymentMethod: 'credit', amount: 700.0, amountTendered: 700.0, changeAmount: 0.0, refNo: 'PO-9912'),
      ],
    );
    expect(saleId.isNotEmpty, true);

    // Verify customer's dueAmount increased by 700 and earned points (700 / 100 = 7 pts => 10 + 7 = 17)
    final custAfterSale = await (db.select(db.customers)..where((c) => c.id.equals(custInitial.id))).getSingle();
    expect(custAfterSale.dueAmount, 700.0);
    expect(custAfterSale.pointsBalance, 17.0);

    // 3. Record partial customer payment of ₱300.00 via GCash
    final payment1 = await posDao.recordCustomerPayment(
      companyId: companyId,
      storeId: storeId,
      customerId: custInitial.id,
      amount: 300.0,
      paymentMethod: 'gcash',
      notes: 'Partial settlement via GCash ref 99402',
    );
    expect(payment1.amount, 300.0);
    expect(payment1.paymentMethod, 'gcash');

    final custAfterPay1 = await (db.select(db.customers)..where((c) => c.id.equals(custInitial.id))).getSingle();
    expect(custAfterPay1.dueAmount, 400.0); // 700 - 300 = 400

    // 4. Record remaining payment of ₱400.00 in Cash
    await posDao.recordCustomerPayment(
      companyId: companyId,
      storeId: storeId,
      customerId: custInitial.id,
      amount: 400.0,
      paymentMethod: 'cash',
    );
    final custAfterPay2 = await (db.select(db.customers)..where((c) => c.id.equals(custInitial.id))).getSingle();
    expect(custAfterPay2.dueAmount, 0.0); // 400 - 400 = 0

    // 5. Verify payment ledger history
    final payments = await posDao.getCustomerPayments(custInitial.id);
    expect(payments.length, 2);
    expect(payments.map((p) => p.amount).toList(), containsAll([300.0, 400.0]));

    // Verify sync queue has entries for payments
    final paymentSyncs = await (db.select(db.syncQueue)
          ..where((s) => s.targetTable.equals('customer_payments') & s.action.equals('INSERT')))
        .get();
    expect(paymentSyncs.length, 2);
  });

  test('hydrateFromCloud and clearAllData do not fail foreign key constraints when shifts and employees exist', () async {
    final companyId = 'comp-fk-001';
    final storeId = 'store-fk-001';
    final regId = 'reg-fk-001';
    final cashierId = 'emp-cashier-001';
    final adminId = 'emp-admin-001';

    // 1. Setup company, store, register, employee, and active shift
    await posDao.upsertFromCloud(
      company: {'id': companyId, 'name': 'FK Test Retail'},
      stores: [{'id': storeId, 'company_id': companyId, 'store_name': 'Store 1'}],
      registers: [{'id': regId, 'company_id': companyId, 'store_id': storeId, 'register_name': 'POS 1'}],
      employees: [
        {'id': cashierId, 'company_id': companyId, 'store_id': storeId, 'first_name': 'Cashier', 'last_name': 'One', 'position': 'Cashier'},
      ],
      cashManagements: [
        {
          'id': 'shift-001',
          'company_id': companyId,
          'store_id': storeId,
          'cash_register_id': regId,
          'employee_id': cashierId,
          'open_time': DateTime.now().toIso8601String(),
          'opening_balance': 1000.0,
          'status': 'open',
        }
      ],
    );

    // Verify shift exists referencing cashierId
    final shift = await posDao.getActiveShift(regId);
    expect(shift, isNotNull);
    expect(shift!.employeeId, cashierId);

    // 2. Hydrate from cloud when switching from Cashier to Admin (clearExisting: false)
    // Must NOT throw SqliteException(787) FOREIGN KEY constraint failed
    await posDao.hydrateFromCloud(
      company: {'id': companyId, 'name': 'FK Test Retail'},
      stores: [{'id': storeId, 'company_id': companyId, 'store_name': 'Store 1'}],
      registers: [{'id': regId, 'company_id': companyId, 'store_id': storeId, 'register_name': 'POS 1'}],
      employees: [
        {'id': cashierId, 'company_id': companyId, 'store_id': storeId, 'first_name': 'Cashier', 'last_name': 'One', 'position': 'Cashier'},
        {'id': adminId, 'company_id': companyId, 'store_id': storeId, 'first_name': 'Admin', 'last_name': 'Boss', 'position': 'Admin'},
      ],
      productTypes: [],
      products: [],
      inventories: [],
      clearExisting: false,
    );

    // Verify both employees exist and shift is still intact
    final employees = await (db.select(db.employees)..where((e) => e.companyId.equals(companyId))).get();
    expect(employees.length, 2);
    final preservedShift = await posDao.getActiveShift(regId);
    expect(preservedShift, isNotNull);
    expect(preservedShift!.id, 'shift-001');

    // 3. Clear all data (e.g. switching company tenant)
    // Must delete in proper reverse dependency order without FK error
    await posDao.clearAllData();

    final remainingEmployees = await db.select(db.employees).get();
    expect(remainingEmployees, isEmpty);
    final remainingShifts = await db.select(db.cashManagements).get();
    expect(remainingShifts, isEmpty);
    final remainingCompanies = await db.select(db.companies).get();
    expect(remainingCompanies, isEmpty);
  });

  test('Shifts are strictly employee-isolated: Cashier open shift does not show as active for Admin', () async {
    final companyId = 'comp-iso-001';
    final storeId = 'store-iso-001';
    final regId = 'reg-iso-001';
    final cashierId = 'emp-cashier-iso';
    final adminId = 'emp-admin-iso';

    // 1. Setup company, store, register, employees
    await posDao.upsertFromCloud(
      company: {'id': companyId, 'name': 'Isolation Test Store'},
      stores: [{'id': storeId, 'company_id': companyId, 'store_name': 'Store'}],
      registers: [{'id': regId, 'company_id': companyId, 'store_id': storeId, 'register_name': 'Reg 1'}],
      employees: [
        {'id': cashierId, 'company_id': companyId, 'store_id': storeId, 'first_name': 'Cashier', 'last_name': 'User', 'position': 'Cashier'},
        {'id': adminId, 'company_id': companyId, 'store_id': storeId, 'first_name': 'Admin', 'last_name': 'User', 'position': 'Admin'},
      ],
    );

    // Initially neither employee has an open shift
    expect(await posDao.getActiveShift(regId, employeeId: cashierId), isNull);
    expect(await posDao.getActiveShift(regId, employeeId: adminId), isNull);

    // 2. Cashier opens a shift
    final cashierShiftId = await posDao.openCashShift(
      companyId: companyId,
      storeId: storeId,
      registerId: regId,
      employeeId: cashierId,
      openingBalance: 1500.0,
      notes: 'Cashier morning shift',
    );

    // Cashier MUST see their active shift
    final cashierShift = await posDao.getActiveShift(regId, employeeId: cashierId);
    expect(cashierShift, isNotNull);
    expect(cashierShift!.id, cashierShiftId);
    expect(cashierShift.employeeId, cashierId);
    expect(cashierShift.openingBalance, 1500.0);

    // Admin MUST NOT see cashier shift (Admin has not opened a shift)
    final adminShift = await posDao.getActiveShift(regId, employeeId: adminId);
    expect(adminShift, isNull);

    // 3. Admin opens their own independent shift on the same register
    final adminShiftId = await posDao.openCashShift(
      companyId: companyId,
      storeId: storeId,
      registerId: regId,
      employeeId: adminId,
      openingBalance: 500.0,
      notes: 'Admin evening cover',
    );

    // Admin sees their own shift
    final currentAdminShift = await posDao.getActiveShift(regId, employeeId: adminId);
    expect(currentAdminShift, isNotNull);
    expect(currentAdminShift!.id, adminShiftId);
    expect(currentAdminShift.openingBalance, 500.0);

    // Cashier still sees their own shift
    final currentCashierShift = await posDao.getActiveShift(regId, employeeId: cashierId);
    expect(currentCashierShift, isNotNull);
    expect(currentCashierShift!.id, cashierShiftId);

    // 4. Admin closes their shift
    await posDao.closeCashShift(
      shiftId: adminShiftId,
      closingBalance: 500.0,
      expectedBalance: 500.0,
    );

    // Admin shift is now closed
    expect(await posDao.getActiveShift(regId, employeeId: adminId), isNull);

    // Cashier shift is STILL open
    expect(await posDao.getActiveShift(regId, employeeId: cashierId), isNotNull);
  });
}
