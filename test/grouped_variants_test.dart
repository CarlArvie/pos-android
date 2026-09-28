import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/presentation/models/grouped_product.dart';
import 'package:pos/presentation/models/cart_item.dart';
import 'package:pos/presentation/screens/counter_view.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/counter/variant_selection_dialog.dart';
import 'package:pos/presentation/widgets/inventory/product_variants_sheet.dart';
import 'package:pos/presentation/widgets/inventory/add_variant_dialog.dart';
import 'package:pos/presentation/widgets/edit_product_dialog.dart';
import 'package:pos/presentation/screens/inventory_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'default-emp-001',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  group('Grouped Product Models', () {
    test('GroupedInventoryItem computes minPrice, maxPrice, and totalStock correctly', () {
      final now = DateTime.now();
      final p1 = Product(
        id: 'p1',
        companyId: 'comp1',
        productName: 'Milk Tea',
        variantName: 'Small',
        price: 80.0,
        costPrice: 40.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final p2 = Product(
        id: 'p2',
        companyId: 'comp1',
        productName: 'Milk Tea',
        variantName: 'Large',
        price: 120.0,
        costPrice: 60.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final inv1 = Inventory(
        id: 'inv1',
        companyId: 'comp1',
        storeId: 'store1',
        productId: 'p1',
        quantityOnHand: 25.0,
        reorderLevel: 5.0,
        unitCost: 40.0,
        trackStock: true,
        isPinned: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final inv2 = Inventory(
        id: 'inv2',
        companyId: 'comp1',
        storeId: 'store1',
        productId: 'p2',
        quantityOnHand: 40.0,
        reorderLevel: 5.0,
        unitCost: 60.0,
        trackStock: true,
        isPinned: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = GroupedInventoryItem(
        productName: 'Milk Tea',
        categoryId: 'cat1',
        categoryName: 'Beverages',
        variants: [
          InventoryItemData(product: p1, inventory: inv1, categoryName: 'Beverages', categoryId: 'cat1'),
          InventoryItemData(product: p2, inventory: inv2, categoryName: 'Beverages', categoryId: 'cat1'),
        ],
      );

      expect(grouped.isMultiVariant, isTrue);
      expect(grouped.minPrice, 80.0);
      expect(grouped.maxPrice, 120.0);
      expect(grouped.totalStock, 65.0);
      expect(grouped.unit, 'cup');
    });

    test('GroupedPosProduct computes minPrice, maxPrice, and isMultiVariant correctly', () {
      final now = DateTime.now();
      final p1 = Product(
        id: 'p1',
        companyId: 'comp1',
        productName: 'Espresso',
        variantName: 'Single',
        price: 90.0,
        costPrice: 30.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final p2 = Product(
        id: 'p2',
        companyId: 'comp1',
        productName: 'Espresso',
        variantName: 'Double',
        price: 130.0,
        costPrice: 45.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = GroupedPosProduct(
        productName: 'Espresso',
        productTypeId: 'cat1',
        variants: [p1, p2],
      );

      expect(grouped.isMultiVariant, isTrue);
      expect(grouped.minPrice, 90.0);
      expect(grouped.maxPrice, 130.0);
    });
  });

  group('VariantSelectionDialog', () {
    testWidgets('Renders all variants and returns selected variant on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final p1 = Product(
        id: 'v1',
        companyId: 'comp1',
        productName: 'Iced Latte',
        variantName: 'Regular',
        price: 110.0,
        costPrice: 50.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final p2 = Product(
        id: 'v2',
        companyId: 'comp1',
        productName: 'Iced Latte',
        variantName: 'Large',
        price: 140.0,
        costPrice: 65.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = GroupedPosProduct(
        productName: 'Iced Latte',
        variants: [p1, p2],
      );

      Product? chosen;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                chosen = await showDialog<Product?>(
                  context: ctx,
                  builder: (_) => VariantSelectionDialog(
                    groupedProduct: grouped,
                    cart: [
                      CartItem(product: p1, quantity: 2.0, unitPrice: 110.0),
                    ],
                  ),
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Iced Latte'), findsOneWidget);
      expect(find.text('Regular'), findsOneWidget);
      expect(find.text('₱110.00'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('₱140.00'), findsOneWidget);
      // p1 is in cart with qty 2 -> badge x2
      expect(find.text('x2'), findsOneWidget);

      // Tap 'Large' option
      await tester.tap(find.byKey(const Key('select_variant_option_v2')));
      await tester.pumpAndSettle();

      expect(chosen, isNotNull);
      expect(chosen!.id, 'v2');
      expect(chosen!.price, 140.0);
    });
  });

  group('ProductVariantsSheet', () {
    testWidgets('Renders variants sheet and triggers edit callback', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final p1 = Product(
        id: 'var1',
        companyId: 'comp1',
        productName: 'Milk Tea',
        variantName: 'Small',
        price: 80.0,
        costPrice: 30.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );
      final p2 = Product(
        id: 'var2',
        companyId: 'comp1',
        productName: 'Milk Tea',
        variantName: 'Large',
        price: 110.0,
        costPrice: 45.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = GroupedInventoryItem(
        productName: 'Milk Tea',
        categoryId: 'cat1',
        categoryName: 'Beverages',
        variants: [
          InventoryItemData(product: p1, inventory: null, categoryName: 'Beverages', categoryId: 'cat1'),
          InventoryItemData(product: p2, inventory: null, categoryName: 'Beverages', categoryId: 'cat1'),
        ],
      );

      InventoryItemData? edited;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  builder: (_) => ProductVariantsSheet(
                    groupedItem: grouped,
                    categories: const [],
                    onEditVariant: (v) => edited = v,
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Milk Tea'), findsWidgets);
      expect(find.text('Small'), findsOneWidget);
      expect(find.textContaining('₱80.00'), findsWidgets);
      expect(find.text('Large'), findsOneWidget);
      expect(find.textContaining('₱110.00'), findsWidgets);

      await tester.tap(find.byKey(const Key('edit_variant_button_var2')));
      await tester.pumpAndSettle();

      expect(edited, isNotNull);
      expect(edited!.product.id, 'var2');
      expect(edited!.product.price, 110.0);
    });
  });

  group('POS Counter Multi-Variant Single Card & Selection', () {
    testWidgets('Consolidates variants into 1 card, opens dialog on tap, and adds selected size to cart', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Seed tenancy tables
      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: 'default-company-001',
          name: 'Acme Test Corp',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'default-store-001',
          companyId: 'default-company-001',
          storeName: 'Main Store',
        ),
      );
      await db.into(db.cashRegisters).insert(
        CashRegistersCompanion.insert(
          id: 'default-reg-001',
          companyId: 'default-company-001',
          storeId: 'default-store-001',
          registerName: 'Register #1',
        ),
      );

      // Insert category
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(
          id: 'cat-bev',
          companyId: 'default-company-001',
          typeName: 'Beverages',
        ),
      );

      // Insert 3 variants of "Classic Milk Tea"
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'tea-small',
          companyId: 'default-company-001',
          productName: 'Classic Milk Tea',
          variantName: const Value('Small'),
          price: const Value(80.0),
          costPrice: const Value(30.0),
          unit: const Value('cup'),
          productTypeId: const Value('cat-bev'),
          sellBy: const Value('unit'),
          taxPercent: const Value(0.0),
          isActive: const Value(true),
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'tea-medium',
          companyId: 'default-company-001',
          productName: 'Classic Milk Tea',
          variantName: const Value('Medium'),
          price: const Value(100.0),
          costPrice: const Value(40.0),
          unit: const Value('cup'),
          productTypeId: const Value('cat-bev'),
          sellBy: const Value('unit'),
          taxPercent: const Value(0.0),
          isActive: const Value(true),
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'tea-large',
          companyId: 'default-company-001',
          productName: 'Classic Milk Tea',
          variantName: const Value('Large'),
          price: const Value(120.0),
          costPrice: const Value(50.0),
          unit: const Value('cup'),
          productTypeId: const Value('cat-bev'),
          sellBy: const Value('unit'),
          taxPercent: const Value(0.0),
          isActive: const Value(true),
        ),
      );

      // Mount CounterView
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CounterView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify ONLY ONE card is displayed for Classic Milk Tea
      expect(find.text('Classic Milk Tea'), findsOneWidget);

      // Verify card shows 3 SIZES badge and price starting from ₱80.00
      expect(find.text('3 SIZES'), findsOneWidget);
      expect(find.text('From ₱80.00'), findsOneWidget);

      // Tap the card to open size selector
      await tester.tap(find.text('Classic Milk Tea'));
      await tester.pumpAndSettle();

      // Verify VariantSelectionDialog is displayed with all 3 sizes
      expect(find.text('Select size / variant (3 available)'), findsOneWidget);
      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);

      // Tap 'Medium' (₱100.00)
      await tester.tap(find.byKey(const Key('select_variant_option_tea-medium')));
      await tester.pumpAndSettle();

      // Dialog should be dismissed, and item added to cart
      expect(find.text('Select size / variant (3 available)'), findsNothing);
      expect(find.text('Current Sale (1)'), findsOneWidget);
      expect(find.text('Medium'), findsWidgets);
      expect(find.text('₱100.00'), findsWidgets);

      // Gracefully unmount widget tree and flush stream cancellation timer
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Adding Sub-items and Variants', () {
    testWidgets('AddVariantDialog saves new variant to SQLite with parent attributes', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Seed tenancy tables
      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: 'default-company-001',
          name: 'Acme Test Corp',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'default-store-001',
          companyId: 'default-company-001',
          storeName: 'Main Store',
        ),
      );
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(
          id: 'cat-bev',
          companyId: 'default-company-001',
          typeName: 'Beverages',
        ),
      );

      bool? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: ctx,
                  builder: (_) => AddVariantDialog(
                    db: db,
                    productName: 'Iced Caramel Macchiato',
                    productTypeId: 'cat-bev',
                    categoryName: 'Beverages',
                    companyId: 'default-company-001',
                    unit: 'cup',
                    sellBy: 'unit',
                    defaultPrice: 120.0,
                    defaultCostPrice: 50.0,
                    taxPercent: 12.0,
                  ),
                );
              },
              child: const Text('Open Add Variant Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Add Variant Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Add Sub-item / Variant'), findsOneWidget);
      expect(find.text('Iced Caramel Macchiato'), findsOneWidget);
      expect(find.text('Beverages'), findsOneWidget);

      // Enter variant name
      await tester.enterText(find.byKey(const Key('add_variant_name_input')), 'Extra Large');
      // Price is pre-filled with defaultPrice 120.00, let's update to 160.00
      await tester.enterText(find.byKey(const Key('add_variant_price_input')), '160.00');
      // Enter stock
      await tester.enterText(find.byKey(const Key('add_variant_stock_input')), '25');

      // Tap submit
      await tester.tap(find.byKey(const Key('submit_add_variant_button')));
      await tester.pumpAndSettle();

      expect(result, isTrue);

      // Verify in DB
      final products = await (db.select(db.products)
            ..where((p) => p.productName.equals('Iced Caramel Macchiato') & p.variantName.equals('Extra Large')))
          .get();
      expect(products.length, 1);
      final newVariant = products.first;
      expect(newVariant.price, 160.0);
      expect(newVariant.unit, 'cup');
      expect(newVariant.sellBy, 'unit');
      expect(newVariant.productTypeId, 'cat-bev');

      final inventories = await (db.select(db.inventories)..where((i) => i.productId.equals(newVariant.id))).get();
      expect(inventories.length, 1);
      expect(inventories.first.quantityOnHand, 25.0);
    });

    testWidgets('ProductVariantsSheet renders Add Variant button and triggers callback', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final p1 = Product(
        id: 'var1',
        companyId: 'comp1',
        productName: 'Fresh Brew',
        variantName: 'Small',
        price: 70.0,
        costPrice: 25.0,
        unit: 'cup',
        sellBy: 'unit',
        taxPercent: 0.0,
        piecesPerPack: 1,
        trackExpiry: false,
        isSerialized: false,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = GroupedInventoryItem(
        productName: 'Fresh Brew',
        categoryId: 'cat1',
        categoryName: 'Coffee',
        variants: [
          InventoryItemData(product: p1, inventory: null, categoryName: 'Coffee', categoryId: 'cat1'),
        ],
      );

      bool addCallbackCalled = false;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  builder: (_) => ProductVariantsSheet(
                    groupedItem: grouped,
                    categories: const [],
                    onEditVariant: (_) {},
                    onAddVariant: (_) => addCallbackCalled = true,
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_variant_sheet_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('add_variant_sheet_button')));
      await tester.pumpAndSettle();

      expect(addCallbackCalled, isTrue);
    });

    testWidgets('EditProductDialog displays sibling variants section and opens AddVariantDialog', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: 'default-company-001',
          name: 'Acme Test Corp',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'default-store-001',
          companyId: 'default-company-001',
          storeName: 'Main Store',
        ),
      );
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(
          id: 'cat-bev',
          companyId: 'default-company-001',
          typeName: 'Beverages',
        ),
      );

      final p = await db.into(db.products).insertReturning(
        ProductsCompanion.insert(
          id: 'prod-latte-reg',
          companyId: 'default-company-001',
          productName: 'Matcha Latte',
          variantName: const Value('Regular'),
          price: const Value(95.0),
          costPrice: const Value(40.0),
          unit: const Value('cup'),
          productTypeId: const Value('cat-bev'),
          sellBy: const Value('unit'),
          taxPercent: const Value(0.0),
          isActive: const Value(true),
        ),
      );

      final inv = await db.into(db.inventories).insertReturning(
        InventoriesCompanion.insert(
          id: 'inv-latte-reg',
          companyId: 'default-company-001',
          storeId: 'default-store-001',
          productId: p.id,
          quantityOnHand: const Value(15.0),
          trackStock: const Value(true),
          reorderLevel: const Value(5.0),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditProductDialog(
            db: db,
            product: p,
            inventory: inv,
            categories: const [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Sibling variants section is rendered
      expect(find.textContaining('Sub-items / Variants'), findsOneWidget);
      expect(find.byKey(const Key('edit_dialog_add_variant_button')), findsOneWidget);

      // Tap Add Variant button in edit dialog
      await tester.tap(find.byKey(const Key('edit_dialog_add_variant_button')));
      await tester.pumpAndSettle();

      // AddVariantDialog opens with Matcha Latte pre-filled
      expect(find.text('Add Sub-item / Variant'), findsOneWidget);
      expect(find.text('Matcha Latte'), findsWidgets);

      // Add "Large" variant
      await tester.enterText(find.byKey(const Key('add_variant_name_input')), 'Large');
      await tester.enterText(find.byKey(const Key('add_variant_price_input')), '125.00');
      await tester.tap(find.byKey(const Key('submit_add_variant_button')));
      await tester.pumpAndSettle();

      // Verify second variant exists in DB
      final variants = await (db.select(db.products)
            ..where((item) => item.productName.equals('Matcha Latte') & item.isActive.equals(true)))
          .get();
      expect(variants.length, 2);
    });

    testWidgets('InventoryScreen deduplicates variants when multiple store inventories exist', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      const activeStoreId = 'store-active-123';
      const companyId = 'default-company-001';
      await DevicePrefs.setStoreId(activeStoreId);
      await DevicePrefs.setCompanyId(companyId);

      // Create company
      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: 'Acme Test Corp',
        ),
      );

      // Create stores
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'default-store-001',
          companyId: companyId,
          storeName: 'Default Store',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: activeStoreId,
          companyId: companyId,
          storeName: 'Active Branch Store',
        ),
      );

      // Create category
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(
          id: 'cat-apparel',
          companyId: companyId,
          typeName: 'Apparel',
        ),
      );

      // Create 2 products: t-shirt Small and t-shirt Medium
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-tshirt-s',
          companyId: companyId,
          productName: 't-shirt',
          variantName: const Value('Small'),
          price: const Value(100.0),
          costPrice: const Value(50.0),
          productTypeId: const Value('cat-apparel'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-tshirt-m',
          companyId: companyId,
          productName: 't-shirt',
          variantName: const Value('Medium'),
          price: const Value(120.0),
          costPrice: const Value(60.0),
          productTypeId: const Value('cat-apparel'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Insert legacy default-store-001 inventories (stock 0) AND active-store inventories (stock 10)
      // for BOTH products - reproducing the exact scenario from user report
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-s-default',
          companyId: companyId,
          storeId: 'default-store-001',
          productId: 'prod-tshirt-s',
          quantityOnHand: const Value(0.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-s-active',
          companyId: companyId,
          storeId: activeStoreId,
          productId: 'prod-tshirt-s',
          quantityOnHand: const Value(10.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-m-default',
          companyId: companyId,
          storeId: 'default-store-001',
          productId: 'prod-tshirt-m',
          quantityOnHand: const Value(0.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-m-active',
          companyId: companyId,
          storeId: activeStoreId,
          productId: 'prod-tshirt-m',
          quantityOnHand: const Value(10.0),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: InventoryScreen(db: db, showScaffold: false),
        ),
      ));
      await tester.pumpAndSettle();

      // Card should say "2 Sizes", NOT "4 Sizes"
      expect(find.text('2 Sizes'), findsOneWidget);
      expect(find.text('4 Sizes'), findsNothing);

      // Open variants sheet by tapping the card key
      await tester.tap(find.byKey(const Key('inventory_card_prod-tshirt-s')));
      await tester.pumpAndSettle();

      // In the variants sheet:
      // Small appears once, Medium appears once
      expect(
        find.descendant(of: find.byType(ProductVariantsSheet), matching: find.text('Small')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ProductVariantsSheet), matching: find.text('Medium')),
        findsOneWidget,
      );

      // Stock should show 10 pcs for both variants
      expect(
        find.descendant(of: find.byType(ProductVariantsSheet), matching: find.text('10 pcs')),
        findsNWidgets(2),
      );
      // "Out of stock" should NOT appear in variants sheet
      expect(
        find.descendant(of: find.byType(ProductVariantsSheet), matching: find.text('Out of stock')),
        findsNothing,
      );

      // Header shows 2 Variants
      expect(find.text('2 Variants'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await db.close();
    });

    test('cleanOrphanedInventories deletes legacy default-store-001 inventories when real store is active', () async {
      const activeStoreId = 'store-active-123';
      const companyId = 'default-company-001';

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: 'Acme Test Corp',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'default-store-001',
          companyId: companyId,
          storeName: 'Default Store',
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: activeStoreId,
          companyId: companyId,
          storeName: 'Active Branch Store',
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-any',
          companyId: companyId,
          productName: 'Sample Prod',
        ),
      );

      // Insert an inventory with default-store-001
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-orphan-test',
          companyId: companyId,
          storeId: 'default-store-001',
          productId: 'prod-any',
          quantityOnHand: const Value(0.0),
        ),
      );

      // Also insert active store inventory
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-real-test',
          companyId: companyId,
          storeId: activeStoreId,
          productId: 'prod-any',
          quantityOnHand: const Value(25.0),
        ),
      );

      // Run cleanup
      await db.posDao.cleanOrphanedInventories(activeStoreId);

      // default-store-001 should be gone, active store should remain
      final remaining = await db.select(db.inventories).get();
      expect(remaining.any((i) => i.storeId == 'default-store-001'), isFalse);
      expect(remaining.any((i) => i.storeId == activeStoreId), isTrue);
    });
  });
}
