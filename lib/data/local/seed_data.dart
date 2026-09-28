import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';

class DatabaseSeeder {
  static const _uuid = Uuid();

  static Future<void> seedIfEmpty(AppDatabase db) async {
    final existingCompanies = await db.select(db.companies).get();
    if (existingCompanies.isNotEmpty) return;

    const companyId = 'default-company-001';
    const storeId = 'default-store-001';
    const registerId = 'default-reg-001';

    // 1. Seed Company
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Apex Supermarket & POS',
            taxId: const Value('100-234-567'),
            address: const Value('100 Commercial Ave, Metro City'),
            phone: const Value('+63 912 345 6789'),
          ),
        );

    // 2. Seed Store
    await db.into(db.stores).insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            storeName: 'Main Retail Branch',
            address: const Value('100 Commercial Ave, Floor 1'),
          ),
        );

    // 3. Seed Cash Register
    await db.into(db.cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: registerId,
            companyId: companyId,
            storeId: storeId,
            registerName: 'Main Checkout #1',
            status: const Value('active'),
          ),
        );

    // 3.1 Seed Default Employees (Admin & Cashier)
    await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            id: 'default-emp-001',
            companyId: companyId,
            storeId: Value(storeId),
            firstName: 'System',
            lastName: 'Admin',
            position: const Value('Admin'),
            pinCode: const Value('1234'),
            isActive: const Value(true),
          ),
        );

    await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            id: 'cashier-emp-001',
            companyId: companyId,
            storeId: Value(storeId),
            firstName: 'Maria',
            lastName: 'Santos',
            position: const Value('Cashier'),
            pinCode: const Value('5678'),
            isActive: const Value(true),
          ),
        );

    // 4. Seed Categories
    final categories = [
      ('Fresh Produce & Meat', 'Weighed fruits, vegetables and meat'),
      ('Beverages', 'Cold drinks, juices & coffee'),
      ('Bakery & Pastries', 'Fresh bread & pastries'),
      ('Snacks & Chips', 'Chips, biscuits & crackers'),
      ('Grains & Bulk', 'Rice, beans and bulk ingredients'),
      ('Dairy & Eggs', 'Milk, butter, cheeses & eggs'),
    ];

    final categoryMap = <String, String>{};
    for (final (name, desc) in categories) {
      final catId = _uuid.v4();
      categoryMap[name] = catId;
      await db.into(db.productTypes).insert(
            ProductTypesCompanion.insert(
              id: catId,
              companyId: companyId,
              typeName: name,
              category: Value(desc),
            ),
          );
    }

    // 5. Seed Realistic Items (Units + Fractions 1:1000)
    final sampleItems = [
      // Fractional Items (Weighed 1:1000)
      (
        'Cavendish Bananas (kg)',
        'Fresh Produce & Meat',
        'BAN-001',
        '480001001',
        85.00,
        55.00,
        18.750, // 18kg 750g
        'kg',
        'fraction',
        'Fresh Harvest',
        'fresh, organic, fruit',
        'Scale barcode lookup #4011',
      ),
      (
        'Fresh Ground Lean Pork (kg)',
        'Fresh Produce & Meat',
        'PRK-001',
        '480001002',
        280.00,
        210.00,
        12.250, // 12kg 250g
        'kg',
        'fraction',
        'Grade A',
        'meat, fresh, chilled',
        'Local butcher cut daily',
      ),
      (
        'Jasmine White Rice (kg)',
        'Grains & Bulk',
        'RCE-001',
        '480001003',
        52.00,
        38.00,
        150.500, // 150kg 500g
        'kg',
        'fraction',
        'Bulk Grain',
        'grains, staple, bulk',
        'Sack ref: Bin 04',
      ),
      (
        'Sharp Cheddar Deli Cheese (kg)',
        'Dairy & Eggs',
        'CHS-001',
        '480001004',
        420.00,
        310.00,
        4.500, // 4kg 500g (Low stock)
        'kg',
        'fraction',
        'Block Cut',
        'dairy, deli, cheese',
        'Keep refrigerated at 4C',
      ),

      // Fixed Unit Items
      (
        'Brewed Iced Americano 500ml',
        'Beverages',
        'BEV-001',
        '480001005',
        110.00,
        45.00,
        45.0,
        'bottle',
        'unit',
        'Cold Brew',
        'coffee, chilled, ready-to-drink',
        'Store in chiller B',
      ),
      (
        'Fresh Whole Milk 1L',
        'Dairy & Eggs',
        'DAI-001',
        '480001006',
        95.00,
        70.00,
        18.0,
        'carton',
        'unit',
        '100% Pure',
        'dairy, milk, breakfast',
        'Expiry within 14 days',
      ),
      (
        'Artisan Sourdough Loaf',
        'Bakery & Pastries',
        'BAK-001',
        '480001007',
        150.00,
        80.00,
        8.0, // Low stock
        'loaf',
        'unit',
        'Whole Loaf',
        'bakery, artisan, bread',
        'Baked at 5:00 AM daily',
      ),
      (
        'Salted Caramel Potato Chips 120g',
        'Snacks & Chips',
        'SNK-001',
        '480001008',
        65.00,
        42.00,
        32.0,
        'pouch',
        'unit',
        'Snack Pack',
        'chips, salted, snack',
        'Aisle 3 top shelf',
      ),
      (
        'Sparkling Mineral Water 330ml',
        'Beverages',
        'BEV-002',
        '480001009',
        45.00,
        22.00,
        0.0, // Out of stock
        'can',
        'unit',
        'Single Can',
        'beverages, sparkling, water',
        'Reorder from Supplier Metro Beverages',
      ),
    ];

    final createdProductIds = <String>[];

    for (final (name, catName, sku, barcode, price, costPrice, qty, unit, sellBy, variant, tags, notes) in sampleItems) {
      final prodId = _uuid.v4();
      createdProductIds.add(prodId);
      final catId = categoryMap[catName];

      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: prodId,
              companyId: companyId,
              productTypeId: Value(catId),
              sku: Value(sku),
              barcode: Value(barcode),
              productName: name,
              price: Value(price),
              costPrice: Value(costPrice),
              unit: Value(unit),
              sellBy: Value(sellBy),
              variantName: Value(variant),
              tags: Value(tags),
              notes: Value(notes),
              isActive: const Value(true),
            ),
          );

      await db.into(db.inventories).insert(
            InventoriesCompanion.insert(
              id: _uuid.v4(),
              companyId: companyId,
              storeId: storeId,
              productId: prodId,
              quantityOnHand: Value(qty),
              trackStock: const Value(true),
              reorderLevel: const Value(10.0),
            ),
          );
    }

    // 6. Seed Initial Active Shift
    await db.into(db.cashManagements).insert(
          CashManagementsCompanion.insert(
            id: 'default-shift-001',
            companyId: companyId,
            storeId: storeId,
            cashRegisterId: registerId,
            employeeId: const Value('default-emp-001'),
            openingBalance: const Value(1000.0),
            status: const Value('open'),
            notes: const Value('Initial store opening float'),
          ),
        );

    // 7. Seed Sample Historical Sales Transactions
    final now = DateTime.now();
    final p0 = createdProductIds[0];
    final p1 = createdProductIds.length > 1 ? createdProductIds[1] : p0;
    final p2 = createdProductIds.length > 2 ? createdProductIds[2] : p0;
    final p3 = createdProductIds.length > 3 ? createdProductIds[3] : p0;

    final sampleSales = [
      (
        'INV-2026-0001',
        now.subtract(const Duration(hours: 1, minutes: 20)),
        212.50,
        212.50,
        0.0,
        0.0,
        'cash',
        250.00,
        37.50,
        null,
        [
          (p0, 1.500, 85.00, 127.50),
          (p2, 1.0, 85.00, 85.00),
        ],
      ),
      (
        'INV-2026-0002',
        now.subtract(const Duration(hours: 3, minutes: 45)),
        95.00,
        95.00,
        0.0,
        0.0,
        'gcash',
        95.00,
        0.0,
        'GCASH-882190',
        [
          (p2, 1.0, 95.00, 95.00),
        ],
      ),
      (
        'INV-2026-0003',
        now.subtract(const Duration(days: 1, hours: 2)),
        272.00,
        340.00,
        68.00,
        0.0,
        'maya',
        272.00,
        0.0,
        'MAYA-771239',
        [
          (p1, 1.0, 280.00, 280.00),
          (p3, 1.0, 60.00, 60.00),
        ],
      ),
      (
        'INV-2026-0004',
        now.subtract(const Duration(days: 2, hours: 5)),
        410.00,
        410.00,
        0.0,
        0.0,
        'card',
        410.00,
        0.0,
        'AUTH-66512',
        [
          (p0, 2.0, 85.00, 170.00),
          (p1, 0.850, 280.00, 240.00),
        ],
      ),
      (
        'INV-2026-0005',
        now.subtract(const Duration(days: 4, hours: 1)),
        190.00,
        190.00,
        0.0,
        0.0,
        'cash',
        200.00,
        10.00,
        null,
        [
          (p2, 2.0, 95.00, 190.00),
        ],
      ),
    ];

    for (final (inv, dt, grand, sub, disc, tax, method, tendered, change, ref, items) in sampleSales) {
      final saleId = _uuid.v4();
      await db.into(db.salesTransactions).insert(
            SalesTransactionsCompanion.insert(
              id: saleId,
              companyId: companyId,
              storeId: storeId,
              cashRegisterId: const Value(registerId),
              cashManagementId: const Value('default-shift-001'),
              invoiceNo: inv,
              transactionDatetime: Value(dt),
              createdAt: Value(dt),
              updatedAt: Value(dt),
              subtotal: Value(sub),
              discountTotal: Value(disc),
              taxTotal: Value(tax),
              grandTotal: Value(grand),
              status: const Value('completed'),
            ),
          );

      for (final (prodId, qty, price, lineSub) in items) {
        await db.into(db.transactionItems).insert(
              TransactionItemsCompanion.insert(
                id: _uuid.v4(),
                companyId: companyId,
                salesTransactionId: saleId,
                productId: Value(prodId),
                quantity: Value(qty),
                unitPrice: Value(price),
                subtotal: Value(lineSub),
              ),
            );
      }

      await db.into(db.tenderPayments).insert(
            TenderPaymentsCompanion.insert(
              id: _uuid.v4(),
              companyId: companyId,
              salesTransactionId: saleId,
              paymentMethod: method,
              amount: Value(grand),
              amountTendered: Value(tendered),
              changeAmount: Value(change),
              referenceNo: Value(ref),
            ),
          );
    }
  }
}
