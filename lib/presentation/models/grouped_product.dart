import '../../data/local/database.dart';

/// Data bundle for an inventory item with resolved category and stock details.
class InventoryItemData {
  final Product product;
  final Inventory? inventory;
  final String categoryName;
  final String categoryId;

  InventoryItemData({
    required this.product,
    required this.inventory,
    required this.categoryName,
    required this.categoryId,
  });
}

/// Represents a consolidated inventory item that groups multiple subitems / variants
/// under a single parent product name and category.
class GroupedInventoryItem {
  final String productName;
  final String categoryId;
  final String categoryName;
  final List<InventoryItemData> variants;

  GroupedInventoryItem({
    required this.productName,
    required this.categoryId,
    required this.categoryName,
    required this.variants,
  });

  bool get isMultiVariant => variants.length > 1;

  double get minPrice {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.product.price).reduce((a, b) => a < b ? a : b);
  }

  double get maxPrice {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.product.price).reduce((a, b) => a > b ? a : b);
  }

  double get totalStock {
    return variants.fold(0.0, (sum, v) => sum + (v.inventory?.quantityOnHand ?? 0.0));
  }

  String get unit => variants.isNotEmpty ? variants.first.product.unit : 'pc';
  String get sellBy => variants.isNotEmpty ? variants.first.product.sellBy : 'unit';

  /// Primary representative item for category & core metadata
  InventoryItemData get primaryItem => variants.first;
}

/// Represents a consolidated product on the POS Counter that groups multiple
/// subitems / variants under a single parent product card.
class GroupedPosProduct {
  final String productName;
  final String? productTypeId;
  final List<Product> variants;

  GroupedPosProduct({
    required this.productName,
    this.productTypeId,
    required this.variants,
  });

  bool get isMultiVariant => variants.length > 1;

  double get minPrice {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  }

  double get maxPrice {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);
  }

  String get unit => variants.isNotEmpty ? variants.first.unit : 'pc';
  String get sellBy => variants.isNotEmpty ? variants.first.sellBy : 'unit';

  Product get primaryProduct => variants.first;
}
