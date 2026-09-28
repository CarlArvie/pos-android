import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/daos/pos_dao.dart';
import 'package:pos/presentation/widgets/common/product_thumbnail.dart';
import 'package:pos/presentation/widgets/common/product_image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PosDao posDao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    posDao = PosDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Inventory Image - Database & Schema Tests', () {
    test('Products table stores and retrieves imagePath and imageUrl', () async {
      const companyId = 'comp-img-01';
      const prodId = 'prod-img-01';

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: 'Test Store Co',
        ),
      );

      // Insert product with both local imagePath and cloud imageUrl
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: prodId,
          companyId: companyId,
          productName: 'Iced Caramel Macchiato',
          price: const Value(150.0),
          imagePath: const Value('product_images/prod_img_01_123.jpg'),
          imageUrl: const Value('https://cdn.example.com/product-images/comp-img-01/products/prod-img-01.jpg'),
        ),
      );

      final retrieved = await (db.select(db.products)..where((p) => p.id.equals(prodId))).getSingle();
      expect(retrieved.productName, equals('Iced Caramel Macchiato'));
      expect(retrieved.imagePath, equals('product_images/prod_img_01_123.jpg'));
      expect(retrieved.imageUrl, equals('https://cdn.example.com/product-images/comp-img-01/products/prod-img-01.jpg'));

      // Update product to remove image
      await (db.update(db.products)..where((p) => p.id.equals(prodId))).write(
        const ProductsCompanion(
          imagePath: Value(null),
          imageUrl: Value(null),
        ),
      );

      final updated = await (db.select(db.products)..where((p) => p.id.equals(prodId))).getSingle();
      expect(updated.imagePath, isNull);
      expect(updated.imageUrl, isNull);
    });

    test('upsertFromCloud updates imageUrl while preserving existing local imagePath', () async {
      const companyId = 'comp-cloud-01';
      const prodId = 'prod-preserve-01';

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: 'Preserve Co',
        ),
      );

      // Local product saved with offline photo
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: prodId,
          companyId: companyId,
          productName: 'Artisan Bread',
          price: const Value(85.0),
          imagePath: const Value('product_images/artisan_bread_local.jpg'),
          imageUrl: const Value(null),
        ),
      );

      // Simulate pull from cloud with cloud CDN URL
      await posDao.upsertFromCloud(
        products: [
          {
            'id': prodId,
            'company_id': companyId,
            'product_name': 'Artisan Bread',
            'price': 85.0,
            'cost_price': 40.0,
            'unit': 'pcs',
            'sell_by': 'unit',
            'is_active': true,
            'image_url': 'https://storage.supabase.co/product-images/artisan_bread.jpg',
          }
        ],
      );

      final result = await (db.select(db.products)..where((p) => p.id.equals(prodId))).getSingle();
      expect(result.imagePath, equals('product_images/artisan_bread_local.jpg'),
          reason: 'Local cached file path must not be wiped out by cloud sync');
      expect(result.imageUrl, equals('https://storage.supabase.co/product-images/artisan_bread.jpg'),
          reason: 'Cloud imageUrl must be updated');
    });
  });

  group('ProductThumbnail Widget Tests', () {
    testWidgets('Renders category fallback icon when no image path or url is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductThumbnail(
              categoryName: 'Beverages',
              width: 60,
              height: 60,
            ),
          ),
        ),
      );

      expect(find.byType(ProductThumbnail), findsOneWidget);
      expect(find.byIcon(Icons.local_cafe_rounded), findsOneWidget);
    });

    testWidgets('Renders appropriate icon for Bakery category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductThumbnail(
              categoryName: 'Bakery & Pastries',
              width: 60,
              height: 60,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.bakery_dining_rounded), findsOneWidget);
    });

    testWidgets('Renders fallback generic inventory icon for unmapped category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductThumbnail(
              categoryName: 'Hardware Tools',
              width: 60,
              height: 60,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget);
    });
  });

  group('ProductImagePicker Widget Tests', () {
    testWidgets('Renders empty state with Add Photo action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImagePicker(
              imagePath: null,
              imageUrl: null,
              categoryName: 'Produce',
              onImagePicked: (_) {},
              onImageRemoved: () {},
            ),
          ),
        ),
      );

      expect(find.text('Product Photo'), findsOneWidget);
      expect(find.text('Tap to take photo or pick from gallery'), findsOneWidget);
      expect(find.text('Add Photo'), findsOneWidget);
    });

    testWidgets('Renders change and remove buttons when imagePath is present', (tester) async {
      bool removed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImagePicker(
              imagePath: 'product_images/test.jpg',
              categoryName: 'Beverages',
              onImagePicked: (_) {},
              onImageRemoved: () {
                removed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Product Photo Attached'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.byKey(const Key('remove_picture_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove_picture_button')));
      await tester.pump();

      expect(removed, isTrue);
    });
  });
}
