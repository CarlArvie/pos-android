import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/screens/inventory_screen.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/add_product_dialog.dart';
import 'package:pos/presentation/widgets/edit_product_dialog.dart';
import 'package:pos/presentation/widgets/inventory_item_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'staff-001',
      'current_employee_role': 'Inventory Specialist',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('Inventory Permissions Enforcement', () {
    testWidgets('inventoryAdd: "Add Item" button is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant inventoryView and inventoryAdd
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
        PosPermissions.inventoryAdd,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pumpAndSettle();

      // "Add Item" button is present
      expect(find.text('Add Item'), findsOneWidget);

      // 2. Now revoke inventoryAdd
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pumpAndSettle();

      // "Add Item" button is completely hidden
      expect(find.text('Add Item'), findsNothing);

      await db.close();
    });

    testWidgets('inventoryCategories: "New Category" chip is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      // 1. Grant inventoryView and inventoryCategories
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
        PosPermissions.inventoryCategories,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Scroll horizontal category list to reveal the end of the list
      await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('New Category'), findsOneWidget);

      // 2. Revoke inventoryCategories
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('New Category'), findsNothing);

      await db.close();
    });

    testWidgets('Cost price field is accessible in Advanced Mode when inventoryAdd is granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final categories = await db.select(db.productTypes).get();

      // Grant inventoryAdd
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryAdd,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddProductDialog(db: db, categories: categories),
        ),
      ));
      await tester.pumpAndSettle();

      // Switch to Advanced Mode to see Cost Price
      await tester.tap(find.text('Advanced Mode'));
      await tester.pumpAndSettle();

      // Cost price input IS visible
      expect(find.byKey(const Key('product_cost_price_input')), findsOneWidget);

      await db.close();
    });

    testWidgets('inventoryDelete: "Archive Item" button is visible when granted, hidden when revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final products = await db.select(db.products).get();
      final categories = await db.select(db.productTypes).get();
      final sampleProd = products.first;

      // 1. Grant inventoryEdit AND inventoryDelete
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryEdit,
        PosPermissions.inventoryDelete,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditProductDialog(
            db: db,
            product: sampleProd,
            inventory: null,
            categories: categories,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Archive Item'), findsOneWidget);

      // 2. Revoke inventoryDelete
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryEdit,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditProductDialog(
            db: db,
            product: sampleProd,
            inventory: null,
            categories: categories,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Archive Item button is strictly hidden
      expect(find.text('Archive Item'), findsNothing);

      await db.close();
    });

    testWidgets('inventoryAdjustStock without inventoryEdit allows stock change but disables general fields', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final products = await db.select(db.products).get();
      final categories = await db.select(db.productTypes).get();
      final sampleProd = products.first;

      // Grant ONLY inventoryAdjustStock (NO inventoryEdit)
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryAdjustStock,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditProductDialog(
            db: db,
            product: sampleProd,
            inventory: null,
            categories: categories,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify product name input is disabled
      final nameField = tester.widget<TextFormField>(find.byKey(const Key('product_name_input')));
      expect(nameField.enabled, isFalse);

      // Verify price input is disabled
      final priceField = tester.widget<TextFormField>(find.byKey(const Key('product_price_input')));
      expect(priceField.enabled, isFalse);

      // Verify stock input is enabled
      final stockField = tester.widget<TextFormField>(find.byKey(const Key('product_stock_input')));
      expect(stockField.enabled, isTrue);

      await db.close();
    });

    testWidgets('inventoryEdit without inventoryAdjustStock: disables stock steppers & input, allows editing name/price', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);
      final products = await db.select(db.products).get();
      final categories = await db.select(db.productTypes).get();
      final sampleProd = products.first;

      // Grant ONLY inventoryEdit (NO inventoryAdjustStock)
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryEdit,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditProductDialog(
            db: db,
            product: sampleProd,
            inventory: null,
            categories: categories,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // General fields ARE enabled
      final nameField = tester.widget<TextFormField>(find.byKey(const Key('product_name_input')));
      expect(nameField.enabled, isTrue);

      final priceField = tester.widget<TextFormField>(find.byKey(const Key('product_price_input')));
      expect(priceField.enabled, isTrue);

      // Stock input is DISABLED
      final stockField = tester.widget<TextFormField>(find.byKey(const Key('product_stock_input')));
      expect(stockField.enabled, isFalse);

      // Stepper buttons (+ and -) are NOT rendered
      expect(find.byKey(const Key('stock_increment_button')), findsNothing);
      expect(find.byKey(const Key('stock_decrement_button')), findsNothing);

      await db.close();
    });

    testWidgets('InventoryItemCard: Edit/Adjust button is completely hidden and card onTap is disabled when both revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Revoke both inventoryEdit and inventoryAdjustStock
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
      });

      bool tapped = false;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: InventoryItemCard(
            productName: 'Test Product',
            categoryName: 'General',
            price: 50.0,
            stockQuantity: 10,
            unit: 'pcs',
            onTap: () => tapped = true,
            onQuickStockTap: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Edit Item and Adjust Stock buttons are NOT rendered
      expect(find.byKey(const Key('inventory_item_edit_button')), findsNothing);
      expect(find.byKey(const Key('inventory_item_adjust_button')), findsNothing);

      // Tapping the card does NOT trigger onTap
      await tester.tap(find.text('Test Product'));
      await tester.pumpAndSettle();
      expect(tapped, isFalse);
    });

    testWidgets('InventoryItemCard: Shows "Adjust Stock" when inventoryAdjustStock is granted, but NOT "Edit Item"', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Grant inventoryAdjustStock, revoke inventoryEdit
      await PermissionService.instance.setEmployeeCustomPermissions('staff-001', {
        PosPermissions.inventoryView,
        PosPermissions.inventoryAdjustStock,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: InventoryItemCard(
            productName: 'Test Product',
            categoryName: 'General',
            price: 50.0,
            stockQuantity: 10,
            unit: 'pcs',
            onTap: () {},
            onQuickStockTap: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Edit Item button is NOT rendered
      expect(find.byKey(const Key('inventory_item_edit_button')), findsNothing);

      // Adjust Stock button IS rendered
      expect(find.byKey(const Key('inventory_item_adjust_button')), findsOneWidget);
      expect(find.text('Adjust Stock'), findsOneWidget);
    });
  });
}
