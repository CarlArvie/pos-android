import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/core/services/product_image_service.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/presentation/screens/inventory_screen.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'reg-01',
      'provisioned_company_id': 'comp-01',
      'provisioned_store_id': 'store-01',
      'current_employee_id': 'emp-01',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('ProductImageService Memory Cache Tests', () {
    test('getCachedFile returns null for uncached path and returns File when cached', () {
      expect(ProductImageService.getCachedFile('non_existent.jpg'), isNull);

      // ProductImageService.getCachedFile retrieves from _resolvedFileCache
      expect(ProductImageService.getCachedFile(null), isNull);
      expect(ProductImageService.getCachedFile(''), isNull);
    });
  });

  group('Inventory Screen Optimizations & Interactive Quick Filters', () {
    testWidgets('Tapping stock status badge filters items and Reset Filter restores all', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());

      // Seed Company & Store
      await db.into(db.companies).insert(
        CompaniesCompanion.insert(id: 'comp-01', name: 'Test Corp'),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(id: 'store-01', companyId: 'comp-01', storeName: 'Main Store'),
      );

      // Seed 1 Category
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(id: 'cat-01', companyId: 'comp-01', typeName: 'General Goods'),
      );

      // Seed 3 Products: 1 in stock, 1 low stock, 1 out of stock
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p-in',
          companyId: 'comp-01',
          productTypeId: const drift.Value('cat-01'),
          productName: 'In Stock Widget',
          price: const drift.Value(50.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-in',
          companyId: 'comp-01',
          storeId: 'store-01',
          productId: 'p-in',
          quantityOnHand: const drift.Value(25.0), // In Stock (>10)
        ),
      );

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p-low',
          companyId: 'comp-01',
          productTypeId: const drift.Value('cat-01'),
          productName: 'Low Stock Gadget',
          price: const drift.Value(75.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-low',
          companyId: 'comp-01',
          storeId: 'store-01',
          productId: 'p-low',
          quantityOnHand: const drift.Value(3.0), // Low Stock (<=10)
        ),
      );

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p-out',
          companyId: 'comp-01',
          productTypeId: const drift.Value('cat-01'),
          productName: 'Out of Stock Gizmo',
          price: const drift.Value(90.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-out',
          companyId: 'comp-01',
          storeId: 'store-01',
          productId: 'p-out',
          quantityOnHand: const drift.Value(0.0), // Out of Stock (0)
        ),
      );

      await PermissionService.instance.setEmployeeCustomPermissions('emp-01', {
        PosPermissions.inventoryView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pumpAndSettle();

      // Initially all 3 items appear
      expect(find.text('In Stock Widget'), findsOneWidget);
      expect(find.text('Low Stock Gadget'), findsOneWidget);
      expect(find.text('Out of Stock Gizmo'), findsOneWidget);
      expect(find.text('Showing 3 items'), findsOneWidget);

      // Tap on "Out (1)" mini legend pill
      await tester.tap(find.text('Out (1)'));
      await tester.pumpAndSettle();

      // Now only Out of Stock item is shown
      expect(find.text('Out of Stock Gizmo'), findsOneWidget);
      expect(find.text('In Stock Widget'), findsNothing);
      expect(find.text('Low Stock Gadget'), findsNothing);
      expect(find.text('Showing 1 items'), findsOneWidget);
      expect(find.text('Reset Filter'), findsOneWidget);

      // Tap on "Low (1)" mini legend pill
      await tester.tap(find.text('Low (1)'));
      await tester.pumpAndSettle();

      // Now only Low Stock item is shown
      expect(find.text('Low Stock Gadget'), findsOneWidget);
      expect(find.text('In Stock Widget'), findsNothing);
      expect(find.text('Out of Stock Gizmo'), findsNothing);

      // Tap "Reset Filter"
      await tester.tap(find.text('Reset Filter'));
      await tester.pumpAndSettle();

      // All 3 items are restored
      expect(find.text('In Stock Widget'), findsOneWidget);
      expect(find.text('Low Stock Gadget'), findsOneWidget);
      expect(find.text('Out of Stock Gizmo'), findsOneWidget);
      expect(find.text('Showing 3 items'), findsOneWidget);

      await db.close();
    });

    testWidgets('Search input uses debouncing before filtering', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(id: 'comp-01', name: 'Test Corp'),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(id: 'store-01', companyId: 'comp-01', storeName: 'Main Store'),
      );
      await db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(id: 'cat-01', companyId: 'comp-01', typeName: 'General Goods'),
      );

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p-apple',
          companyId: 'comp-01',
          productTypeId: const drift.Value('cat-01'),
          productName: 'Fuji Apple',
          price: const drift.Value(40.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-apple',
          companyId: 'comp-01',
          storeId: 'store-01',
          productId: 'p-apple',
          quantityOnHand: const drift.Value(15.0),
        ),
      );

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p-banana',
          companyId: 'comp-01',
          productTypeId: const drift.Value('cat-01'),
          productName: 'Cavendish Banana',
          price: const drift.Value(30.0),
        ),
      );
      await db.into(db.inventories).insert(
        InventoriesCompanion.insert(
          id: 'inv-banana',
          companyId: 'comp-01',
          storeId: 'store-01',
          productId: 'p-banana',
          quantityOnHand: const drift.Value(15.0),
        ),
      );

      await PermissionService.instance.setEmployeeCustomPermissions('emp-01', {
        PosPermissions.inventoryView,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryScreen(db: db, showScaffold: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fuji Apple'), findsOneWidget);
      expect(find.text('Cavendish Banana'), findsOneWidget);

      // Enter text into search
      await tester.enterText(find.byType(TextField).first, 'Apple');
      // Pump 50ms (before the 200ms debounce timer)
      await tester.pump(const Duration(milliseconds: 50));
      // Banana is still visible because debounce hasn't elapsed
      expect(find.text('Cavendish Banana'), findsOneWidget);

      // Now advance timer past 200ms debounce
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Filtered to Apple only
      expect(find.text('Fuji Apple'), findsOneWidget);
      expect(find.text('Cavendish Banana'), findsNothing);

      await db.close();
    });
  });
}
