import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/daos/pos_dao.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/widgets/inventory_item_card.dart';
import 'package:pos/presentation/widgets/pos_bottom_nav_bar.dart';
import 'package:pos/presentation/widgets/admin_drawer.dart';
import 'package:pos/presentation/screens/main_shell_screen.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/auth/auth_guard.dart';

import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/presentation/screens/staff/staff_management_view.dart';
import 'package:pos/presentation/screens/customers_view.dart';
import 'package:pos/presentation/widgets/counter/checkout_dialog.dart';
import 'package:pos/presentation/models/cart_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'current_employee_role': 'Admin',
      'current_employee_id': 'default-emp-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'provisioned_register_id': 'default-reg-001',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  testWidgets('Inventory screen smoke test with hamburger drawer and categories', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Verify Header Title and Add Item button
    expect(find.text('Inventory'), findsAtLeastNWidgets(1));
    expect(find.text('Add Item'), findsOneWidget);

    // 2. Verify hamburger icon is present
    final menuButton = find.byIcon(Icons.menu_rounded);
    expect(menuButton, findsOneWidget);

    // 3. Verify category chips are present
    expect(find.text('All Items'), findsOneWidget);
    expect(find.text('Beverages'), findsAtLeastNWidgets(1));

    // 4. Tap hamburger menu to open drawer
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // 5. Verify Drawer contents
    expect(find.text('Admin Portal'), findsOneWidget);
    expect(find.text('Main Retail Branch'), findsOneWidget);
    expect(find.text('Point of Sale'), findsOneWidget);

    // Close drawer
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    // 6. Test Category Filter tap
    await tester.tap(find.text('Beverages').first);
    await tester.pumpAndSettle();

    // Verify items are displayed
    expect(find.text('Brewed Iced Americano 500ml'), findsOneWidget);

    await db.close();
  });

  testWidgets('Bottom navigation bar switches tabs and More opens drawer', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Verify all 5 bottom navigation items are present
    expect(find.text('Inventory'), findsAtLeastNWidgets(1));
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Counter'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // 1. Tap Counter (Middle action button)
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Register #1 • Shift Active'), findsOneWidget);

    // 2. Tap Transactions
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('View historical receipts and process refunds'), findsOneWidget);

    // 3. Tap Reports
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory Health'), findsOneWidget);

    // 4. Tap More -> Should open the Admin Drawer
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Admin Portal'), findsOneWidget);
    expect(find.text('Local Database: SQLite Active'), findsOneWidget);

    await db.close();
  });

  testWidgets('Add Item in Simple Mode works reactively', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Tap Add Item button
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    // Verify dialog appeared with Simple Mode active by default
    expect(find.text('Add New Item'), findsOneWidget);
    expect(find.text('Simple Mode'), findsOneWidget);
    expect(find.text('Add Photo'), findsOneWidget);

    // Fill in product name, price, and stock
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Special Mocha 350ml');
    await tester.enterText(find.byKey(const Key('product_price_input')), '120.00');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '25');

    // Tap Save
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // Search for the newly added item to verify addition and search filtering
    await tester.enterText(find.byType(TextField).first, 'Special Mocha');
    await tester.pumpAndSettle();

    // Verify newly added item appears in the inventory grid
    expect(find.text('Special Mocha 350ml'), findsOneWidget);
    expect(find.text('₱120.00'), findsOneWidget);

    await db.close();
  });

  testWidgets('Add Item in Advanced Mode with fraction 1:1000 and variant', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Tap Add Item button
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    // Switch to Advanced Mode
    await tester.tap(find.text('Advanced Mode'));
    await tester.pumpAndSettle();

    // Fill Item Name
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Fresh Organic Mango (kg)');

    // Select Sell by Fraction (1:1000)
    await tester.tap(find.byKey(const Key('sell_by_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell by Fraction (Loose 1:1000: kg, g)').last);
    await tester.pumpAndSettle();

    // Fill Variant, Prices, and Fractional Stock (15.750 kg)
    await tester.enterText(find.byKey(const Key('product_variant_input')), 'Carabao Sweet');
    await tester.enterText(find.byKey(const Key('product_price_input')), '140.00');
    await tester.enterText(find.byKey(const Key('product_cost_price_input')), '90.00');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '15.750');
    await tester.enterText(find.byKey(const Key('product_sku_input')), 'MNG-001');
    await tester.enterText(find.byKey(const Key('product_barcode_input')), '48000999');
    await tester.enterText(find.byKey(const Key('product_tags_input')), 'fruit, fresh, mango');
    await tester.enterText(find.byKey(const Key('product_notes_input')), 'Guimaras harvest');

    // Save
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // Search for the newly added fractional item
    await tester.enterText(find.byType(TextField).first, 'Organic Mango');
    await tester.pumpAndSettle();

    // Verify item name, variant badge, price, and 1:1000 fractional stock
    expect(find.text('Fresh Organic Mango (kg)'), findsOneWidget);
    expect(find.text('Carabao Sweet'), findsOneWidget);
    expect(find.text('₱140.00'), findsOneWidget);
    expect(find.text('15.750 kg'), findsOneWidget);

    await db.close();
  });

  testWidgets('Responsive Add Item on small mobile phone (360x640) renders without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Open Add Item Dialog
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    // Verify Simple mode renders cleanly on phone
    expect(find.text('Add New Item'), findsOneWidget);
    expect(find.text('Simple Mode'), findsOneWidget);

    // Switch to Advanced Mode
    await tester.tap(find.text('Advanced Mode'));
    await tester.pumpAndSettle();

    // Enter details in single-column phone flow
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Cold Brew Can');
    await tester.enterText(find.byKey(const Key('product_price_input')), '85.00');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '40');

    // Tap Save
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // Filter/search to verify item in inventory grid on small phone
    await tester.enterText(find.byType(TextField).first, 'Cold Brew');
    await tester.pumpAndSettle();

    // Verify item saved
    expect(find.text('Cold Brew Can'), findsOneWidget);

    await db.close();
  });

  testWidgets('Responsive Add Item on tablet (1024x768) activates dual-column layout', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Open Add Item Dialog
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    // Switch to Advanced Mode
    await tester.tap(find.text('Advanced Mode'));
    await tester.pumpAndSettle();

    // Verify tablet dual-column section headers are visible
    expect(find.text('Item Identification'), findsOneWidget);
    expect(find.text('Pricing & Stock Control'), findsOneWidget);

    // Fill fields
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Artisan Cheddar (kg)');
    await tester.enterText(find.byKey(const Key('product_price_input')), '450.00');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '8.500');

    // Save
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // Search and verify
    await tester.enterText(find.byType(TextField).first, 'Artisan Cheddar');
    await tester.pumpAndSettle();
    expect(find.text('Artisan Cheddar (kg)'), findsOneWidget);

    await db.close();
  });

  testWidgets('Add Item with Multi-Subitem (Variant) Builder creates multiple sizes with independent prices and stock', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Tap Add Item button
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    // Switch to Advanced Mode
    await tester.tap(find.text('Advanced Mode'));
    await tester.pumpAndSettle();

    // Fill Item Name
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Cotton Roundneck T-Shirt');

    // Enable Multi-Subitem Builder
    await tester.tap(find.byKey(const Key('has_multiple_variants_switch')));
    await tester.pumpAndSettle();

    // Verify multi-subitem section appeared with pre-populated starter rows
    expect(find.text('Subitems / Variants (2)'), findsOneWidget);

    // Row 0: Small @ ₱200
    await tester.enterText(find.byKey(const Key('subitem_variant_input_0')), 'Small');
    await tester.enterText(find.byKey(const Key('subitem_price_input_0')), '200.00');
    await tester.enterText(find.byKey(const Key('subitem_stock_input_0')), '15');

    // Row 1: Medium @ ₱220
    await tester.enterText(find.byKey(const Key('subitem_variant_input_1')), 'Medium');
    await tester.enterText(find.byKey(const Key('subitem_price_input_1')), '220.00');
    await tester.enterText(find.byKey(const Key('subitem_stock_input_1')), '20');

    // Add 3rd subitem (Large @ ₱250)
    await tester.ensureVisible(find.byKey(const Key('add_subitem_row_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_subitem_row_button')));
    await tester.pumpAndSettle();

    expect(find.text('Subitems / Variants (3)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('subitem_variant_input_2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('subitem_variant_input_2')), 'Large');
    await tester.enterText(find.byKey(const Key('subitem_price_input_2')), '250.00');
    await tester.enterText(find.byKey(const Key('subitem_stock_input_2')), '10');

    // Verify dynamic button label
    expect(find.text('Save All (3 Subitems)'), findsOneWidget);

    // Tap Save
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // Filter to verify all 3 variants exist in inventory
    await tester.enterText(find.byType(TextField).first, 'Cotton Roundneck');
    await tester.pumpAndSettle();

    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('₱200.00'), findsOneWidget);
    expect(find.text('₱220.00'), findsOneWidget);
    expect(find.text('₱250.00'), findsOneWidget);

    await db.close();
  });

  testWidgets('Inventory grid adapts to screen size: 3 items per row on tablet, 2 on phone', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // 1. Tablet Viewport (768 x 1024 portrait tablet)
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Verify GridView has crossAxisCount == 3 on 768px tablet
    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);
    final GridView gridView = tester.widget(gridFinder);
    final delegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);

    // 2. Phone Viewport (390 x 844 phone)
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    final GridView phoneGrid = tester.widget(gridFinder);
    final phoneDelegate = phoneGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(phoneDelegate.crossAxisCount, 2);

    await db.close();
  });

  testWidgets('Edit Item with full details, price update, and stock adjustment', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Search for 'Cavendish Bananas' in inventory grid
    await tester.enterText(find.byType(TextField).first, 'Cavendish Bananas');
    await tester.pumpAndSettle();

    // 2. Tap the item card / Edit button to open detailed EditProductDialog
    await tester.tap(find.text('Cavendish Bananas (kg)'));
    await tester.pumpAndSettle();

    // 3. Verify EditProductDialog is opened with pre-filled details
    expect(find.text('Edit Item: Cavendish Bananas (kg)'), findsOneWidget);
    expect(find.text('Current Stock on Hand'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // 4. Update Selling Price and Stock
    await tester.enterText(find.byKey(const Key('product_price_input')), '78.50');
    await tester.enterText(find.byKey(const Key('product_variant_input')), 'Lakatan Ripe');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '22.500');

    // 5. Tap Save Changes
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // 6. Verify inventory grid reactively reflects updated price, variant, and stock
    expect(find.text('₱78.50'), findsOneWidget);
    expect(find.text('Lakatan Ripe'), findsOneWidget);
    expect(find.text('22.500 kg'), findsOneWidget);

    await db.close();
  });

  testWidgets('Edit Item on mobile phone (360x640) with stock stepper and archive item flow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Search for 'Artisan Sourdough Loaf' in inventory grid
    await tester.enterText(find.byType(TextField).first, 'Artisan Sourdough');
    await tester.pumpAndSettle();

    // 2. Tap to open edit dialog
    await tester.tap(find.text('Artisan Sourdough Loaf'));
    await tester.pumpAndSettle();

    // 3. Verify dialog opened without overflow on 360x640 phone
    expect(find.text('Edit Item: Artisan Sourdough Loaf'), findsOneWidget);
    expect(find.text('Current Stock on Hand'), findsOneWidget);

    // 4. Test stepper + button (unit step = +1)
    // Initial stock is 8 loaves
    expect(find.byKey(const Key('product_stock_input')), findsOneWidget);
    // Scroll the stock stepper into view (variants section may push it below fold on 360x640)
    await tester.ensureVisible(find.byKey(const Key('product_stock_input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final stockInput = tester.widget<TextFormField>(find.byKey(const Key('product_stock_input')));
    expect(stockInput.controller?.text, '9');

    // 5. Test Archive Item
    await tester.tap(find.text('Archive Item'));
    await tester.pumpAndSettle();

    // Verify confirmation alert appears
    expect(find.text('Archive Item?'), findsOneWidget);
    // Tap confirm 'Archive Item' in the AlertDialog
    await tester.tap(find.widgetWithText(ElevatedButton, 'Archive Item'));
    await tester.pumpAndSettle();

    // 6. Verify item is removed from active inventory
    expect(find.text('Artisan Sourdough Loaf'), findsNothing);

    await db.close();
  });

  testWidgets('VAT tax, track expiration, tags, internal notes, and active for sale persist to SQLite DB on Add and Edit', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Open Add Item -> Advanced Mode
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Advanced Mode'));
    await tester.pumpAndSettle();

    // 2. Fill basic fields
    await tester.enterText(find.byKey(const Key('product_name_input')), 'Gouda Reserve');
    await tester.enterText(find.byKey(const Key('product_price_input')), '320.00');
    await tester.enterText(find.byKey(const Key('product_stock_input')), '15');

    // 3. Toggle VAT / Tax and enter custom 15.0%
    await tester.ensureVisible(find.byKey(const Key('tax_switch')));
    await tester.tap(find.byKey(const Key('tax_switch')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tax_rate_input')));
    await tester.enterText(find.byKey(const Key('tax_rate_input')), '15.0');

    // 4. Toggle Track Expiration Date
    await tester.ensureVisible(find.byKey(const Key('expiry_switch')));
    await tester.tap(find.byKey(const Key('expiry_switch')));
    await tester.pumpAndSettle();

    // 5. Fill Tags and Internal Notes
    await tester.ensureVisible(find.byKey(const Key('product_tags_input')));
    await tester.enterText(find.byKey(const Key('product_tags_input')), 'imported, cheese, promo');

    await tester.ensureVisible(find.byKey(const Key('product_notes_input')));
    await tester.enterText(find.byKey(const Key('product_notes_input')), 'Keep in Chiller #2. Supplier: EuroFoods.');

    // 6. Save Product to Database
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // 7. Verify directly in Drift SQLite DB table
    final addedProd = await (db.select(db.products)..where((p) => p.productName.equals('Gouda Reserve'))).getSingle();
    expect(addedProd.taxPercent, 15.0);
    expect(addedProd.trackExpiry, isTrue);
    expect(addedProd.tags, 'imported, cheese, promo');
    expect(addedProd.notes, 'Keep in Chiller #2. Supplier: EuroFoods.');
    expect(addedProd.isActive, isTrue);

    // 8. Now open Edit Item for 'Gouda Reserve'
    await tester.enterText(find.byType(TextField).first, 'Gouda Reserve');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InventoryItemCard, 'Gouda Reserve'));
    await tester.pumpAndSettle();

    // Verify fields were pre-filled accurately in Edit Dialog
    expect(find.text('Edit Item: Gouda Reserve'), findsOneWidget);

    // 9. Modify tax, notes, tags, and active status
    await tester.ensureVisible(find.byKey(const Key('tax_rate_input')));
    await tester.enterText(find.byKey(const Key('tax_rate_input')), '18.0');

    await tester.ensureVisible(find.byKey(const Key('product_tags_input')));
    await tester.enterText(find.byKey(const Key('product_tags_input')), 'premium, aged, gouda');

    await tester.ensureVisible(find.byKey(const Key('product_notes_input')));
    await tester.enterText(find.byKey(const Key('product_notes_input')), 'Transferred to Chiller #4.');

    // Toggle active switch to false
    await tester.ensureVisible(find.byKey(const Key('active_switch')));
    await tester.tap(find.byKey(const Key('active_switch')));
    await tester.pumpAndSettle();

    // 10. Save Changes
    await tester.tap(find.byKey(const Key('save_product_button')));
    await tester.pumpAndSettle();

    // 11. Verify updated record in SQLite database
    final updatedProd = await (db.select(db.products)..where((p) => p.productName.equals('Gouda Reserve'))).getSingle();
    expect(updatedProd.taxPercent, 18.0);
    expect(updatedProd.tags, 'premium, aged, gouda');
    expect(updatedProd.notes, 'Transferred to Chiller #4.');
    expect(updatedProd.isActive, isFalse);

    // 12. Verify that inactive item card is hidden from active inventory grid
    expect(find.widgetWithText(InventoryItemCard, 'Gouda Reserve'), findsNothing);

    await db.close();
  });

  testWidgets('Counter POS speed checkout with barcode scanning, fractional weighing, and SQLite sales execution', (WidgetTester tester) async {
    // Tablet layout for split catalog + cart view
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Switch to Counter Tab
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();

    // Verify Counter interface
    expect(find.textContaining('Register #1 • Shift Active'), findsOneWidget);
    expect(find.text('Cart is empty'), findsOneWidget);

    // 2. Barcode scan add: enter Americano barcode '480001005'
    await tester.enterText(find.byKey(const Key('counter_barcode_search_input')), '480001005');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Verify Americano added to cart
    expect(find.text('Current Sale (1)'), findsOneWidget);
    expect(find.text('Brewed Iced Americano 500ml'), findsAtLeastNWidgets(1));

    // 3. Add fractional weighed item: Tap 'Cavendish Bananas (kg)'
    await tester.tap(find.text('Cavendish Bananas (kg)').first);
    await tester.pumpAndSettle();

    // Verify WeighedItemDialog opened
    expect(find.byKey(const Key('unit_chip_kg')), findsOneWidget);
    expect(find.text('Quick Presets:'), findsOneWidget);

    // Tap 500g preset
    await tester.tap(find.byKey(const Key('preset_500g')));
    await tester.pumpAndSettle();

    // Add to cart
    await tester.tap(find.byKey(const Key('confirm_weighed_item_button')));
    await tester.pumpAndSettle();

    // Verify 2 items in cart (Americano ₱110 + Bananas 0.5kg @ ₱85 = ₱42.50 -> Total = ₱152.50)
    expect(find.text('Current Sale (2)'), findsOneWidget);
    expect(find.text('0.500 kg'), findsOneWidget);

    // 4. Test Hold & Recall Cart
    await tester.tap(find.byKey(const Key('hold_cart_button')));
    await tester.pumpAndSettle();
    expect(find.text('Cart is empty'), findsOneWidget);

    // Recall Cart
    await tester.tap(find.byKey(const Key('hold_cart_button')));
    await tester.pumpAndSettle();
    expect(find.text('Current Sale (2)'), findsOneWidget);

    // Dismiss active SnackBar so it doesn't intercept taps
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // 5. Open Checkout
    await tester.tap(find.byKey(const Key('charge_checkout_button')));
    await tester.pumpAndSettle();

    // Verify Checkout Dialog
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(find.text('AMOUNT DUE'), findsOneWidget);
    expect(find.text('₱152.50'), findsAtLeastNWidgets(1));

    // Enter Cash Tendered: ₱200.00
    await tester.enterText(find.byKey(const Key('amount_tendered_input')), '200.00');
    await tester.pumpAndSettle();

    // Verify Change Due is ₱47.50
    expect(find.text('₱47.50'), findsOneWidget);

    // Complete Payment
    await tester.tap(find.byKey(const Key('confirm_payment_button')));
    await tester.pumpAndSettle();

    // Verify Success Receipt screen
    expect(find.text('Payment Successful!'), findsOneWidget);
    expect(find.text('Start Next Sale'), findsOneWidget);

    // 6. Direct Database Assertions: Verify sales record created in SQLite
    final sales = await db.select(db.salesTransactions).get();
    expect(sales.length, 6);
    expect(sales.last.grandTotal, 152.50);

    final lineItems = await (db.select(db.transactionItems)..where((i) => i.salesTransactionId.equals(sales.last.id))).get();
    expect(lineItems.length, 2);

    final tenders = await (db.select(db.tenderPayments)..where((t) => t.salesTransactionId.equals(sales.last.id))).get();
    expect(tenders.length, 1);
    expect(tenders.first.paymentMethod, 'cash');
    expect(tenders.first.amountTendered, 200.0);
    expect(tenders.first.changeAmount, 47.50);

    // Verify Inventory decrement: Americano stock was 45 -> now 44
    final americano = await (db.select(db.products)..where((p) => p.barcode.equals('480001005'))).getSingle();
    final americanoInv = await (db.select(db.inventories)..where((i) => i.productId.equals(americano.id))).getSingle();
    expect(americanoInv.quantityOnHand, 44.0);

    // Close Receipt and verify next sale starts empty
    await tester.tap(find.byKey(const Key('next_sale_button')));
    await tester.pumpAndSettle();
    expect(find.text('Cart is empty'), findsOneWidget);

    await db.close();
  });

  testWidgets('Counter POS on mobile phone (390x844): permanent cart visibility, bottom bar, and slide-up cart sheet with steppers & discounts', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Switch to Counter Tab on Phone
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();

    // Verify top cart button and bottom sticky bar are BOTH visible when cart is empty
    expect(find.byKey(const Key('counter_cart_button')), findsOneWidget);
    expect(find.text('Cart (0)'), findsOneWidget);
    expect(find.text('Cart empty'), findsOneWidget);
    expect(find.byKey(const Key('mobile_view_empty_cart_button')), findsOneWidget);

    // 2. Tap View Cart on empty cart to open slide-up Cart Sheet
    await tester.tap(find.byKey(const Key('mobile_view_empty_cart_button')));
    await tester.pumpAndSettle();

    expect(find.text('Current Sale (0)'), findsOneWidget);
    expect(find.text('Scan a barcode or tap products on the catalog'), findsOneWidget);

    // Close Cart Sheet by tapping barrier
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 3. Add discrete unit item: Barcode scan Americano '480001005'
    await tester.enterText(find.byKey(const Key('counter_barcode_search_input')), '480001005');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Header badge updates to Cart (1) and bottom bar updates to 1 item(s) • ₱110.00 with Checkout
    expect(find.text('Cart (1)'), findsOneWidget);
    expect(find.text('1 item(s)'), findsOneWidget);
    expect(find.text('₱110.00'), findsOneWidget);
    expect(find.byKey(const Key('mobile_checkout_button')), findsOneWidget);

    // 4. Add fractional weighed item: Tap Bananas (first item at top of catalog grid)
    await tester.tap(find.text('Cavendish Bananas (kg)').first);
    await tester.pumpAndSettle();

    // WeighedItemDialog opens
    expect(find.byKey(const Key('unit_chip_kg')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preset_250g')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_weighed_item_button')));
    await tester.pumpAndSettle();

    // Header updates to Cart (2) and bottom bar updates to ₱131.25 (110 + 21.25)
    expect(find.text('Cart (2)'), findsOneWidget);
    expect(find.text('2 item(s)'), findsOneWidget);
    expect(find.text('₱131.25'), findsOneWidget);

    // 5. Open mobile cart sheet via top cart button
    await tester.tap(find.byKey(const Key('counter_cart_button')));
    await tester.pumpAndSettle();

    // Verify slide-up sheet displays line items
    expect(find.text('Current Sale (2)'), findsOneWidget);
    expect(find.text('0.250 kg'), findsOneWidget);
    expect(find.text('1 pcs'), findsOneWidget);

    // Test quantity stepper inside sheet: increment Americano +1
    await tester.tap(find.byKey(const Key('stepper_plus_0')));
    await tester.pumpAndSettle();

    // Americano is now 2 pcs -> Total updates to ₱241.25 (220 + 21.25)
    expect(find.text('2 pcs'), findsOneWidget);
    expect(find.text('₱241.25'), findsAtLeastNWidgets(1));

    // Test discount toggle inside sheet
    await tester.tap(find.byKey(const Key('discount_toggle_button')));
    await tester.pumpAndSettle();
    expect(find.text('Discount (Senior/PWD)'), findsOneWidget);

    // Charge button in sheet
    expect(find.byKey(const Key('charge_checkout_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('charge_checkout_button')));
    await tester.pumpAndSettle();

    // Verify Checkout Dialog opens
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(find.text('AMOUNT DUE'), findsOneWidget);

    // Cancel checkout
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await db.close();
  });

  testWidgets('Cash Shift lifecycle on POS Counter: Open Shift with starting float, sales accumulation, and Close Shift with drawer balancing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Switch to Counter
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();

    // Seeded shift is active (Float: ₱1000)
    expect(find.textContaining('Register #1 • Shift Active'), findsOneWidget);
    expect(find.byKey(const Key('close_shift_button')), findsOneWidget);

    // 2. Close the initial shift
    await tester.tap(find.byKey(const Key('close_shift_button')));
    await tester.pumpAndSettle();

    // Verify CloseShiftDialog opens
    expect(find.text('Shift Reconciliation & Close'), findsOneWidget);
    expect(find.text('Expected Cash in Drawer'), findsOneWidget);
    expect(find.text('Drawer is Balanced (₱0.00)'), findsOneWidget);

    // Confirm close
    await tester.ensureVisible(find.byKey(const Key('confirm_close_shift_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_close_shift_button')));
    await tester.pumpAndSettle();

    // Verify banner reactively switches to Shift Closed
    expect(find.text('Register #1 • Shift Closed'), findsOneWidget);
    expect(find.byKey(const Key('open_shift_button')), findsOneWidget);

    // 3. Open a new Shift with ₱2,000 float
    await tester.tap(find.byKey(const Key('open_shift_button')));
    await tester.pumpAndSettle();

    expect(find.text('Open Cash Shift'), findsOneWidget);
    expect(find.byKey(const Key('preset_float_2000')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset_float_2000')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('open_shift_notes_input')), 'Midday shift opening');
    await tester.tap(find.byKey(const Key('confirm_open_shift_button')));
    await tester.pumpAndSettle();

    // Verify banner reflects ₱2,000 float
    expect(find.textContaining('Shift Active (Float: ₱2000)'), findsOneWidget);

    // 4. Perform a Cash sale: Add Americano (₱110)
    await tester.tap(find.text('Brewed Iced Americano 500ml').first);
    await tester.pumpAndSettle();

    // Dismiss active SnackBar so it doesn't intercept taps
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
    await tester.pumpAndSettle();

    // Open checkout
    await tester.tap(find.byKey(const Key('charge_checkout_button')));
    await tester.pumpAndSettle();

    // Pay with ₱110 cash exact
    await tester.tap(find.byKey(const Key('confirm_payment_button')));
    await tester.pumpAndSettle();

    // Close receipt
    await tester.tap(find.byKey(const Key('next_sale_button')));
    await tester.pumpAndSettle();

    // 5. Close the shift with drawer balancing
    await tester.tap(find.byKey(const Key('close_shift_button')));
    await tester.pumpAndSettle();

    // Verify reconciliation figures:
    // Opening float = ₱2000, Cash Sales = ₱110, Expected = ₱2110
    expect(find.text('₱2110.00'), findsAtLeastNWidgets(1));
    expect(find.text('Drawer is Balanced (₱0.00)'), findsOneWidget);

    // Test shortage simulation: Enter ₱2,100 actual cash (₱10 short)
    await tester.enterText(find.byKey(const Key('actual_closing_cash_input')), '2100.00');
    await tester.pumpAndSettle();

    expect(find.text('Cash Short: -₱10.00'), findsOneWidget);

    // Confirm close shift
    await tester.ensureVisible(find.byKey(const Key('confirm_close_shift_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_close_shift_button')));
    await tester.pumpAndSettle();

    // Verify banner is now Shift Closed
    expect(find.text('Register #1 • Shift Closed'), findsOneWidget);

    // 6. Direct Database Assertions
    final shifts = await (db.select(db.cashManagements)..orderBy([(s) => OrderingTerm.asc(s.openTime)])).get();
    expect(shifts.length, 2);

    final secondShift = shifts[1];
    expect(secondShift.status, 'closed');
    expect(secondShift.openingBalance, 2000.0);
    expect(secondShift.closingBalance, 2100.0);
    expect(secondShift.expectedBalance, 2110.0);

    await db.close();
  });

  testWidgets('Transactions screen: KPI summary, date/payment filters, search, receipt details modal, and Excel export trigger', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Navigate to Transactions tab
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();

    // 2. Verify Header & KPI metrics banner
    expect(find.text('Transaction Ledger'), findsOneWidget);
    expect(find.text('View historical receipts and process refunds'), findsOneWidget);
    expect(find.text('Filtered Revenue'), findsOneWidget);
    expect(find.text('Total Orders'), findsOneWidget);
    expect(find.text('Avg Ticket'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);

    // Initial state: 5 seeded transactions visible
    expect(find.textContaining('INV-2026-0001'), findsOneWidget);
    expect(find.textContaining('INV-2026-0002'), findsOneWidget);

    // 3. Test Search filtering
    await tester.enterText(find.byKey(const Key('transaction_search_input')), '0002');
    await tester.pumpAndSettle();

    expect(find.textContaining('INV-2026-0002'), findsOneWidget);
    expect(find.textContaining('INV-2026-0001'), findsNothing);

    // Clear search
    await tester.enterText(find.byKey(const Key('transaction_search_input')), '');
    await tester.pumpAndSettle();

    // 4. Test Payment Method Filter (Tap '📱 GCash')
    await tester.ensureVisible(find.text('📱 GCash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('📱 GCash'));
    await tester.pumpAndSettle();

    expect(find.textContaining('INV-2026-0002'), findsOneWidget);
    expect(find.textContaining('INV-2026-0001'), findsNothing);

    // Reset payment filter
    await tester.ensureVisible(find.text('All Methods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Methods'));
    await tester.pumpAndSettle();
    expect(find.textContaining('INV-2026-0001'), findsOneWidget);

    // 5. Test Date Preset Filter (Tap 'Today')
    await tester.ensureVisible(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.textContaining('INV-2026-0001'), findsOneWidget);
    expect(find.textContaining('INV-2026-0002'), findsOneWidget);
    expect(find.textContaining('INV-2026-0005'), findsNothing);

    // Reset date filter
    await tester.ensureVisible(find.text('All Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Time'));
    await tester.pumpAndSettle();

    // 6. Test Tap Transaction Card -> Open Transaction Details Dialog
    await tester.tap(find.textContaining('INV-2026-0001'));
    await tester.pumpAndSettle();

    // Verify receipt modal contents
    expect(find.text('Transaction Details'), findsOneWidget);
    expect(find.text('PURCHASED ITEMS'), findsOneWidget);
    expect(find.text('PAYMENT & TOTALS'), findsOneWidget);
    expect(find.text('Export / Share Receipt'), findsOneWidget);

    // Close receipt modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // 7. Test Export Report Modal
    await tester.tap(find.byKey(const Key('export_transactions_button')));
    await tester.pumpAndSettle();

    expect(find.text('Export Transactions'), findsOneWidget);
    expect(find.text('Excel (.xlsx)'), findsOneWidget);
    expect(find.text('CSV (.csv)'), findsOneWidget);
    expect(find.byKey(const Key('save_report_to_device_button')), findsOneWidget);
    expect(find.byKey(const Key('share_report_button')), findsOneWidget);

    // Tap Save to Device
    await tester.tap(find.byKey(const Key('save_report_to_device_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Close export dialog
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await db.close();
  });

  testWidgets('Customer Management via side drawer: directory listing, KPI cards, adding customer, tier filtering, and responsive cellphone title', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Verify Customers tab is NOT on the bottom navigation bar
    expect(find.descendant(of: find.byType(PosBottomNavBar), matching: find.text('Customers')), findsNothing);

    // 2. Open drawer and tap Customers
    await tester.tap(find.byTooltip('Navigation Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Admin Portal'), findsOneWidget);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();

    // Verify Customer Management header on standard desktop/tablet width
    expect(find.text('Customer Directory'), findsOneWidget);
    expect(find.text('Track loyalty points and store credit'), findsOneWidget);
    expect(find.text('Total Customers'), findsOneWidget);
    expect(find.text('Receivables Due'), findsOneWidget);

    // 3. Tap Add Customer FAB
    await tester.tap(find.byKey(const Key('add_customer_fab')));
    await tester.pumpAndSettle();

    expect(find.text('Add New Customer'), findsOneWidget);

    // Fill customer details
    await tester.enterText(find.byKey(const Key('customer_name_input')), 'Juan Dela Cruz');
    await tester.enterText(find.byKey(const Key('customer_phone_input')), '0917-555-8888');
    await tester.enterText(find.byKey(const Key('customer_email_input')), 'juan@example.com');
    await tester.enterText(find.byKey(const Key('customer_address_input')), 'Unit 102, Manila');
    await tester.enterText(find.byKey(const Key('customer_points_input')), '250');

    // Select Gold tier
    await tester.tap(find.byKey(const Key('customer_tier_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold').last);
    await tester.pumpAndSettle();

    // Save Customer
    await tester.tap(find.byKey(const Key('save_customer_button')));
    await tester.pumpAndSettle();

    // Verify customer appears in directory
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('0917-555-8888'), findsOneWidget);
    expect(find.text('250 Points'), findsOneWidget);
    expect(find.text('Gold'), findsWidgets);

    // 4. Test Search
    await tester.enterText(find.byKey(const Key('customer_search_input')), '0917-555');
    await tester.pumpAndSettle();
    expect(find.text('Juan Dela Cruz'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customer_search_input')), 'NonExistentPerson');
    await tester.pumpAndSettle();
    expect(find.text('No customers match the filter'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customer_search_input')), '');
    await tester.pumpAndSettle();

    // 5. Test Drawer Navigation to Customers
    await tester.tap(find.byTooltip('Navigation Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Admin Portal'), findsOneWidget);

    // Tap Customers in drawer
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.text('Customer Directory'), findsOneWidget);

    // 6. Test Responsive title on cellphone screen (360x640)
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    // On cellphone screen, title adapts to 'Customers' only
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Customer Directory'), findsNothing);

    await db.close();
  });

  testWidgets('Cashier header customer button icon: quick-register customer, attach to sale, and checkout recording', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Navigate to Counter
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();

    // Verify Cashier add customer button icon on the left of header
    expect(find.byKey(const Key('cashier_add_customer_button')), findsOneWidget);

    // 1. Tap cashier add customer button
    await tester.tap(find.byKey(const Key('cashier_add_customer_button')));
    await tester.pumpAndSettle();

    // Dialog opens
    expect(find.text('Customer Selection'), findsOneWidget);
    expect(find.byKey(const Key('cashier_register_new_customer_button')), findsOneWidget);

    // Register a new customer directly from cashier
    await tester.tap(find.byKey(const Key('cashier_register_new_customer_button')));
    await tester.pumpAndSettle();

    expect(find.text('Add New Customer'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('customer_name_input')), 'Maria Clara');
    await tester.enterText(find.byKey(const Key('customer_phone_input')), '0918-123-4567');
    await tester.tap(find.byKey(const Key('save_customer_button')));
    await tester.pumpAndSettle();

    // Verify Maria Clara is now attached to the cashier header
    expect(find.text('Maria Clara'), findsOneWidget);
    expect(find.byKey(const Key('clear_customer_button')), findsOneWidget);

    // 2. Add product to cart and checkout
    final productTile = find.text('Brewed Iced Americano 500ml').first;
    await tester.tap(productTile);
    await tester.pumpAndSettle();

    // Open checkout
    await tester.tap(find.byKey(const Key('charge_checkout_button')));
    await tester.pumpAndSettle();

    // Verify customer is displayed in checkout modal
    expect(find.textContaining('Customer: Maria Clara'), findsOneWidget);

    // Complete sale
    await tester.tap(find.byKey(const Key('confirm_payment_button')));
    await tester.pumpAndSettle();

    expect(find.text('Payment Successful!'), findsOneWidget);

    // Close checkout dialog
    await tester.tap(find.text('Start Next Sale'));
    await tester.pumpAndSettle();

    // Verify customer is cleared for next sale
    expect(find.byKey(const Key('clear_customer_button')), findsNothing);

    // Verify sales transaction in SQLite has customerId recorded
    final lastSale = await (db.select(db.salesTransactions)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1))
      .getSingle();
    expect(lastSale.customerId, isNotNull);

    final customerInDb = await (db.select(db.customers)
      ..where((c) => c.id.equals(lastSale.customerId!)))
      .getSingle();
    expect(customerInDb.fullName, 'Maria Clara');

    await db.close();
  });

  testWidgets('Reports screen: Executive P&L, 12 core metrics, expenses management, and inventory health tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Navigate to Reports screen
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    // 2. Verify Tab Switchers
    expect(find.text('Sales & Profit'), findsOneWidget);
    expect(find.text('Inventory Health'), findsOneWidget);

    // 3. Verify Date Preset Chips
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Last 7 Days'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // Switch to All Time preset so all 5 seeded transactions appear
    await tester.tap(find.text('All Time'));
    await tester.pumpAndSettle();

    // 4. Verify P&L Master Card
    expect(find.text('Profit & Loss (P&L) Statement'), findsOneWidget);
    expect(find.text('Total Sales (Net)'), findsOneWidget);
    expect(find.text('COGS (Cost of Goods)'), findsOneWidget);
    expect(find.text('Gross Profit'), findsOneWidget);
    expect(find.text('Store Expenses'), findsOneWidget);
    expect(find.text('Net Profit'), findsOneWidget);

    // 5. Verify Transaction KPI Row
    await tester.ensureVisible(find.text('Receipts'));
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('Avg Order (AOV)'), findsOneWidget);
    expect(find.text('VAT (12%)'), findsOneWidget);
    expect(find.text('Discounts'), findsOneWidget);

    // 6. Verify Top Stocks, Top Categories, Payment Modes
    await tester.ensureVisible(find.text('Top Stocks (Best-Sellers)'));
    expect(find.text('Top Stocks (Best-Sellers)'), findsOneWidget);
    expect(find.text('Top Categories'), findsOneWidget);

    await tester.ensureVisible(find.text('Payment Modes'));
    expect(find.text('Payment Modes'), findsOneWidget);
    expect(find.text('Top Customers'), findsOneWidget);

    await tester.ensureVisible(find.text('Sales by Staff (Sold By)'));
    expect(find.text('Sales by Staff (Sold By)'), findsOneWidget);

    // 7. Test Add Expense Flow
    expect(find.byKey(const Key('add_expense_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add_expense_button')));
    await tester.pumpAndSettle();

    // Verify modal
    expect(find.text('Record Store Expense'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('expense_amount_input')), '450.00');
    await tester.enterText(find.byKey(const Key('expense_desc_input')), 'Packaging boxes restock');
    await tester.tap(find.byKey(const Key('save_expense_button')));
    await tester.pumpAndSettle();

    // Modal closed, expense saved
    expect(find.text('Record Store Expense'), findsNothing);
    expect(find.textContaining('Packaging boxes restock'), findsAtLeastNWidgets(1));

    // 8. Test Inventory Health tab
    await tester.ensureVisible(find.byIcon(Icons.inventory_2_rounded));
    await tester.tap(find.byIcon(Icons.inventory_2_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Stock Valuation'), findsOneWidget);
    expect(find.text('Optimal In Stock'), findsAtLeastNWidgets(1));

    // 9. Mobile responsive rendering check (360x640)
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();

    // Switch back to Sales & Profit on phone
    await tester.tap(find.byIcon(Icons.trending_up_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profit & Loss (P&L) Statement'), findsOneWidget);

    await db.close();
  });

  testWidgets('AuthGuard blocks unauthenticated user without session or employeeId', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // Temporarily clear employee ID to simulate unauthenticated state
    await DevicePrefs.setCurrentEmployeeId(null);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Verify Authentication Required barrier is rendered
    expect(find.text('Authentication Required'), findsOneWidget);
    expect(find.text('Go to Login'), findsOneWidget);

    // Restore employee ID for subsequent tests
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('AuthGuard and MainShellScreen block Cashier from Admin-only screens and dialogs', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // Set role to Cashier
    await DevicePrefs.setCurrentEmployeeRole('Cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-emp-001');

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db, initialIndex: 2),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Verify Cashier lands on Point of Sale
    expect(find.text('Point of Sale'), findsAtLeastNWidgets(1));

    // 2. Direct AuthGuard test for an admin-only feature
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuthGuard(
          db: db,
          allowedRoles: const ['admin'],
          featureName: 'Financial Reports',
          child: const Text('Top Secret Financial Data'),
        ),
      ),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Access Denied barrier should block child
    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.text('Current Role: CASHIER'), findsOneWidget);
    expect(find.text('Top Secret Financial Data'), findsNothing);
    expect(find.text('Return to POS Counter'), findsOneWidget);
    expect(find.text('Request Manager Override'), findsOneWidget);

    // Restore Admin role
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('StaffManagementView displays Directory and Roles & Permissions tabs', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await PermissionService.instance.init(force: true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StaffManagementView(db: db)),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Verify Header and TabBar
    expect(find.text('Staff & Permissions'), findsOneWidget);
    expect(find.textContaining('Staff Directory'), findsOneWidget);
    expect(find.textContaining('Roles & Permissions'), findsOneWidget);

    // 2. Verify staff directory list loaded
    expect(find.text('Add Staff'), findsOneWidget);
    expect(find.text('System Admin'), findsOneWidget);

    // 3. Switch to Roles & Permissions tab
    final rolesTab = find.textContaining('Roles & Permissions');
    await tester.tap(rolesTab);
    await tester.pumpAndSettle();

    // 4. Verify Roles sidebar and module accordions
    expect(find.text('Roles'), findsOneWidget);
    expect(find.text('Store Manager'), findsAtLeastNWidgets(1));
    expect(find.text('Cashier'), findsAtLeastNWidgets(1));
    expect(find.text('Inventory Specialist'), findsAtLeastNWidgets(1));

    // 5. Verify Accordion module cards
    expect(find.text('Point of Sale & Register'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Inventory Management'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Inventory Management'), findsOneWidget);

    await db.close();
  });

  testWidgets('StaffManagementView responsive on narrow mobile screen (339.4x749) renders without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(339.4 * 2.0, 749.0 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await PermissionService.instance.init(force: true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StaffManagementView(db: db)),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // 1. Verify Directory renders without overflow
    expect(find.text('Staff & Permissions'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);

    // Drag to scroll down and reveal System Admin
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('System Admin'), findsOneWidget);

    // 2. Switch to Roles & Permissions tab
    final rolesTab = find.textContaining('Roles & Permissions');
    await tester.ensureVisible(rolesTab);
    await tester.tap(rolesTab);
    await tester.pumpAndSettle();

    // 3. On mobile, dropdown selector is rendered instead of fixed sidebar
    expect(find.text('Selected Role'), findsOneWidget);

    // Scroll down in permissions matrix to reveal module accordions
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('Point of Sale & Register'), findsOneWidget);

    await db.close();
  });

  testWidgets('AuthGuard requiredPermission blocks unauthorized access and allows authorized access', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    await DevicePrefs.setCurrentEmployeeRole('Cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-emp-001');
    await PermissionService.instance.init(force: true);

    // Test 1: Blocked feature (reports.view)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuthGuard(
          db: db,
          requiredPermission: PosPermissions.reportsView,
          featureName: 'Reports & Analytics',
          child: const Text('Top Secret Executive Analytics'),
        ),
      ),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.text('Top Secret Executive Analytics'), findsNothing);

    // Test 2: Allowed feature (pos.view)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuthGuard(
          db: db,
          requiredPermission: PosPermissions.posView,
          featureName: 'Counter Terminal',
          child: const Text('POS Counter Content Live'),
        ),
      ),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('POS Counter Content Live'), findsOneWidget);
    expect(find.text('Access Denied'), findsNothing);

    // Restore Admin
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('Cashier dynamically reveals Inventory button in bottom nav and drawer when inventory.view is granted', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // 1. Log in as Cashier (using lowercase 'cashier' to also verify case-insensitivity)
    await DevicePrefs.setCurrentEmployeeRole('cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-001');
    await PermissionService.instance.init(force: true);

    // By default, Cashier does NOT have inventory.view
    expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isFalse);
    expect(PermissionService.instance.canAccessTab(0), isFalse);

    await tester.pumpWidget(MaterialApp(
      home: MainShellScreen(database: db),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    // Verify Inventory is NOT in the bottom navigation bar
    expect(find.descendant(of: find.byType(PosBottomNavBar), matching: find.text('Inventory')), findsNothing);

    // 2. Grant inventory.view permission to Cashier role
    final currentCashierPerms = PermissionService.instance.getRolePermissions('Cashier');
    final updatedPerms = {...currentCashierPerms, PosPermissions.inventoryView};
    await PermissionService.instance.saveRolePermissions('Cashier', updatedPerms);

    await tester.pumpAndSettle();

    // 3. Verify PermissionService immediately reflects the new permission
    expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isTrue);
    expect(PermissionService.instance.canAccessTab(0), isTrue);

    // 4. Verify Inventory button NOW APPEARS in the bottom navigation bar!
    expect(find.descendant(of: find.byType(PosBottomNavBar), matching: find.text('Inventory')), findsOneWidget);

    // 5. Open navigation drawer and verify Inventory button is also visible there
    final menuButton = find.byTooltip('Navigation Menu');
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AdminDrawer), matching: find.text('Inventory')), findsOneWidget);

    // Close drawer by tapping the Inventory item in the drawer
    await tester.tap(find.descendant(of: find.byType(AdminDrawer), matching: find.text('Inventory')));
    await tester.pumpAndSettle();

    // Verify navigating to Inventory works
    expect(find.text('Inventory Management'), findsWidgets);

    // Restore default
    await PermissionService.instance.resetRoleToDefault('Cashier');
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('Cashier dynamically reveals 3-dot action menu and Edit Customer option when customers.edit permission is granted', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // Add a customer
    final companies = await db.select(db.companies).get();
    final companyId = companies.first.id;
    await db.posDao.addCustomer(
      companyId: companyId,
      fullName: 'Elena Gilbert',
      phone: '09123456789',
    );

    // 1. Start session as Cashier with default permissions (no customers.edit)
    await DevicePrefs.setCurrentEmployeeRole('Cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-001');
    await PermissionService.instance.init(force: true);
    await PermissionService.instance.resetRoleToDefault('Cashier');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CustomersView(db: db)),
      theme: AppTheme.lightTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Elena Gilbert'), findsOneWidget);

    // 2. Verify the 3-dot menu button is NOT visible for Cashier without customers.edit
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);

    // 3. Grant customers.edit to Cashier role
    final currentCashierPerms = PermissionService.instance.getRolePermissions('Cashier');
    final updatedPerms = {...currentCashierPerms, PosPermissions.customersEdit};
    await PermissionService.instance.saveRolePermissions('Cashier', updatedPerms);
    await tester.pumpAndSettle();

    // 4. Verify the 3-dot menu button NOW APPEARS on the customer card!
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    // 5. Tap the 3-dot menu
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    // 6. Verify 'Edit Customer' is available and 'Archive / Remove' is hidden (no customers.delete)
    expect(find.text('Edit Customer'), findsOneWidget);
    expect(find.text('Archive / Remove'), findsNothing);

    // Restore defaults
    await PermissionService.instance.resetRoleToDefault('Cashier');
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('Cashier dynamically reveals Credit tender at checkout when customers.credit_charge is granted', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    final posDao = PosDao(db);
    final customer = await posDao.addCustomer(
      companyId: 'default-company-001',
      fullName: 'Benjamin Franklin',
      phone: '09123459999',
      creditLimit: 5000.0,
    );

    final allProducts = await posDao.getActiveProducts('default-company-001');
    final product = allProducts.first;
    final cartItem = CartItem(product: product, quantity: 2.0, unitPrice: product.price);

    // 1. Session as Cashier without customers.credit_charge
    await DevicePrefs.setCurrentEmployeeRole('Cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-emp-001');
    await PermissionService.instance.init(force: true);
    await PermissionService.instance.resetRoleToDefault('Cashier');

    // Pump CheckoutDialog
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: CheckoutDialog(
          db: db,
          items: [cartItem],
          subtotal: cartItem.netSubtotal,
          discountTotal: 0.0,
          taxTotal: cartItem.taxAmount,
          grandTotal: cartItem.lineTotal,
          customer: customer,
          onSaleCompleted: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Cash, GCash, Maya, Card exist, but Credit does NOT exist
    expect(find.byKey(const Key('payment_method_cash')), findsOneWidget);
    expect(find.byKey(const Key('payment_method_credit')), findsNothing);

    // 2. Grant customers.credit_charge to Cashier
    final cashierPerms = PermissionService.instance.getRolePermissions('Cashier');
    await PermissionService.instance.saveRolePermissions('Cashier', {
      ...cashierPerms,
      PosPermissions.customersCreditCharge,
    });

    // Re-pump CheckoutDialog
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: CheckoutDialog(
          db: db,
          items: [cartItem],
          subtotal: cartItem.netSubtotal,
          discountTotal: 0.0,
          taxTotal: cartItem.taxAmount,
          grandTotal: cartItem.lineTotal,
          customer: customer,
          onSaleCompleted: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Credit tender is NOW VISIBLE!
    expect(find.byKey(const Key('payment_method_credit')), findsOneWidget);

    // Tap Credit tender
    await tester.tap(find.byKey(const Key('payment_method_credit')));
    await tester.pumpAndSettle();

    // Verify Credit Account Info Box is displayed
    expect(find.byKey(const Key('credit_account_info_box')), findsOneWidget);
    expect(find.text('Customer Store Credit Account'), findsOneWidget);
    expect(find.text('₱5000.00'), findsWidgets);

    // Complete Payment
    await tester.tap(find.byKey(const Key('confirm_payment_button')));
    await tester.pumpAndSettle();

    // Verify receipt view shows Store Credit
    expect(find.text('Payment Successful!'), findsOneWidget);
    expect(find.text('STORE CREDIT (ON ACCOUNT)'), findsOneWidget);
    expect(find.text('Benjamin Franklin'), findsOneWidget);

    // Verify customer's dueAmount in SQLite was incremented
    final updatedCust = await (db.select(db.customers)..where((c) => c.id.equals(customer.id))).getSingle();
    expect(updatedCust.dueAmount > 0, isTrue);

    // Restore
    await PermissionService.instance.resetRoleToDefault('Cashier');
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });

  testWidgets('Customer credit debt settlement: Settle Due button and SettleCreditDialog record payment and update balance', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);

    // Add a customer with outstanding debt
    final posDao = PosDao(db);
    final cust = await posDao.addCustomer(
      companyId: 'default-company-001',
      fullName: 'Lucas Scott',
      phone: '09170001122',
      creditLimit: 5000.0,
    );
    // Update dueAmount to 850.0
    await (db.update(db.customers)..where((c) => c.id.equals(cust.id))).write(
      CustomersCompanion(dueAmount: const Value(850.0)),
    );

    // 1. Session as Cashier with customers.credit_settle granted
    await DevicePrefs.setCurrentEmployeeRole('Cashier');
    await DevicePrefs.setCurrentEmployeeId('cashier-emp-001');
    await PermissionService.instance.init(force: true);
    final cashierPerms = PermissionService.instance.getRolePermissions('Cashier');
    await PermissionService.instance.saveRolePermissions('Cashier', {
      ...cashierPerms,
      PosPermissions.customersCreditSettle,
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: CustomersView(db: db)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Lucas Scott'), findsOneWidget);
    expect(find.text('Due: ₱850.00'), findsOneWidget);

    // Verify Settle Due button is visible on the customer card
    final settleBtn = find.byKey(Key('settle_due_button_${cust.id}'));
    expect(settleBtn, findsOneWidget);

    // 2. Tap Settle Due
    await tester.tap(settleBtn);
    await tester.pumpAndSettle();

    // SettleCreditDialog is open
    expect(find.text('Settle Credit Balance'), findsOneWidget);
    expect(find.text('₱850.00'), findsWidgets);

    // Change amount to 350.00
    await tester.enterText(find.byKey(const Key('settle_amount_input')), '350.00');
    await tester.pumpAndSettle();

    // Verify remaining due calculation (850 - 350 = 500)
    expect(find.text('₱500.00'), findsWidgets);

    // Select GCash method
    await tester.tap(find.byKey(const Key('settle_method_gcash')));
    await tester.pumpAndSettle();

    // Enter notes
    await tester.enterText(find.byKey(const Key('settle_notes_input')), 'GCash ref #12345');
    await tester.pumpAndSettle();

    // Submit payment
    await tester.tap(find.byKey(const Key('settle_submit_button')));
    await tester.pumpAndSettle();

    // Dialog closed and SnackBar shown
    expect(find.text('Payment of ₱350.00 recorded for Lucas Scott.'), findsOneWidget);

    // Verify customer card updated on screen to Due: ₱500.00
    expect(find.text('Due: ₱500.00'), findsOneWidget);

    // 3. Open 3-dot menu and check Payment History
    await tester.tap(find.byKey(Key('customer_card_menu_${cust.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Payment History'), findsOneWidget);
    await tester.tap(find.text('Payment History'));
    await tester.pumpAndSettle();

    // CustomerPaymentHistoryDialog is open
    expect(find.text('Payment Ledger'), findsOneWidget);
    expect(find.text('₱350.00'), findsOneWidget);
    expect(find.text('GCASH'), findsOneWidget);
    expect(find.text('Note: GCash ref #12345'), findsOneWidget);

    // Close ledger
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Restore
    await PermissionService.instance.resetRoleToDefault('Cashier');
    await DevicePrefs.setCurrentEmployeeRole('Admin');
    await DevicePrefs.setCurrentEmployeeId('default-emp-001');
    await db.close();
  });
}


