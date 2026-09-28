import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart' as uuid;
import '../../data/local/database.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/edit_product_dialog.dart';
import '../../core/device_prefs.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../models/grouped_product.dart';
import '../widgets/inventory/product_variants_sheet.dart';
import '../widgets/inventory/add_variant_dialog.dart';

class InventoryScreen extends StatefulWidget {
  final AppDatabase db;
  final bool showScaffold;
  final Widget? bottomNavigationBar;

  const InventoryScreen({
    super.key,
    required this.db,
    this.showScaffold = true,
    this.bottomNavigationBar,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _selectedCategoryId = 'all';
  String _selectedStockFilter = 'all'; // 'all', 'inStock', 'lowStock', 'outOfStock'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  late final Stream<List<ProductType>> _categoriesStream;
  late final Stream<List<InventoryItemData>> _inventoryItemsStream;

  @override
  void initState() {
    super.initState();
    _categoriesStream = _watchCategories();
    _inventoryItemsStream = _watchInventoryItems();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _searchQuery = val.trim();
        });
      }
    });
  }

  // Combined stream of products with their inventory stock and categories
  Stream<List<InventoryItemData>> _watchInventoryItems() {
    final activeStoreId = DevicePrefs.storeId;
    final activeCompanyId = DevicePrefs.companyId;

    Expression<bool> invCondition = widget.db.inventories.productId.equalsExp(widget.db.products.id) &
        widget.db.inventories.isDeleted.equals(false);
    if (activeStoreId != null && activeStoreId.isNotEmpty) {
      invCondition = invCondition & widget.db.inventories.storeId.equals(activeStoreId);
    }

    final query = widget.db.select(widget.db.products).join([
      leftOuterJoin(
        widget.db.inventories,
        invCondition,
      ),
      leftOuterJoin(
        widget.db.productTypes,
        widget.db.productTypes.id.equalsExp(widget.db.products.productTypeId) &
            widget.db.productTypes.isDeleted.equals(false),
      ),
    ]);

    Expression<bool> prodCondition = widget.db.products.isDeleted.equals(false);
    if (activeCompanyId != null && activeCompanyId.isNotEmpty) {
      prodCondition = prodCondition & widget.db.products.companyId.equals(activeCompanyId);
    }
    query.where(prodCondition);

    return query.watch().map((rows) {
      final Map<String, InventoryItemData> productMap = {};
      for (final row in rows) {
        final product = row.readTable(widget.db.products);
        final inventory = row.readTableOrNull(widget.db.inventories);
        final category = row.readTableOrNull(widget.db.productTypes);

        if (!productMap.containsKey(product.id)) {
          productMap[product.id] = InventoryItemData(
            product: product,
            inventory: inventory,
            categoryName: category?.typeName ?? 'Uncategorized',
            categoryId: category?.id ?? 'none',
          );
        } else {
          // If a row for this product already exists, prefer an inventory record from the active store
          final existing = productMap[product.id]!;
          if (existing.inventory == null && inventory != null) {
            productMap[product.id] = InventoryItemData(
              product: product,
              inventory: inventory,
              categoryName: category?.typeName ?? existing.categoryName,
              categoryId: category?.id ?? existing.categoryId,
            );
          } else if (activeStoreId != null && inventory != null && inventory.storeId == activeStoreId) {
            productMap[product.id] = InventoryItemData(
              product: product,
              inventory: inventory,
              categoryName: category?.typeName ?? existing.categoryName,
              categoryId: category?.id ?? existing.categoryId,
            );
          }
        }
      }
      return productMap.values.toList();
    });
  }

  Stream<List<ProductType>> _watchCategories() {
    final activeCompanyId = DevicePrefs.companyId;
    if (activeCompanyId != null && activeCompanyId.isNotEmpty) {
      return (widget.db.select(widget.db.productTypes)
            ..where((c) => c.isDeleted.equals(false) & c.companyId.equals(activeCompanyId)))
          .watch();
    }
    return (widget.db.select(widget.db.productTypes)
          ..where((c) => c.isDeleted.equals(false)))
        .watch();
  }

  void _showAddItemDialog(List<ProductType> categories) {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AddProductDialog(
        db: widget.db,
        categories: categories,
      ),
    );
  }

  void _showEditProductDialog(InventoryItemData item, List<ProductType> categories) {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to edit products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => EditProductDialog(
        db: widget.db,
        product: item.product,
        inventory: item.inventory,
        categories: categories,
      ),
    );
  }

  void _showAddVariantDialog(GroupedInventoryItem item, List<ProductType> categories) {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final primary = item.primaryItem;
    showDialog(
      context: context,
      builder: (ctx) => AddVariantDialog(
        db: widget.db,
        productName: item.productName,
        productTypeId: item.categoryId,
        categoryName: item.categoryName,
        companyId: primary.product.companyId,
        unit: item.unit,
        sellBy: item.sellBy,
        defaultPrice: primary.product.price,
        defaultCostPrice: primary.product.costPrice,
        taxPercent: primary.product.taxPercent,
        trackExpiry: primary.product.trackExpiry,
        expiryDate: primary.product.expiryDate,
        tags: primary.product.tags,
      ),
    );
  }

  void _showProductVariantsSheet(GroupedInventoryItem groupedItem, List<ProductType> categories) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductVariantsSheet(
        groupedItem: groupedItem,
        categories: categories,
        onEditVariant: (variant) {
          _showEditProductDialog(variant, categories);
        },
        onAddVariant: (grouped) {
          _showAddVariantDialog(grouped, categories);
        },
      ),
    );
  }

  List<GroupedInventoryItem> _groupInventoryItems(List<InventoryItemData> items) {
    final Map<String, Map<String, InventoryItemData>> groups = {};
    for (final item in items) {
      final key = '${item.categoryId}::${item.product.productName.trim().toLowerCase()}';
      final variantMap = groups.putIfAbsent(key, () => <String, InventoryItemData>{});
      // Deduplicate variants by product.id
      variantMap.putIfAbsent(item.product.id, () => item);
    }

    return groups.values.map((variantMap) {
      final variants = variantMap.values.toList();
      final first = variants.first;
      return GroupedInventoryItem(
        productName: first.product.productName,
        categoryId: first.categoryId,
        categoryName: first.categoryName,
        variants: variants,
      );
    }).toList();
  }

  void _showAddCategoryDialog() {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryCategories)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to manage categories.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Category'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Beverages, Shoes, Electronics',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final companyId = DevicePrefs.companyId!;
                final catId = const uuid.Uuid().v4();
                
                // Save locally
                await widget.db.into(widget.db.productTypes).insert(
                  ProductTypesCompanion.insert(
                    id: catId,
                    companyId: companyId,
                    typeName: name,
                  )
                );
                
                // Queue Sync
                await widget.db.posDao.queueSync('product_types', catId, 'INSERT', {
                  'id': catId,
                  'company_id': companyId,
                  'type_name': name,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                });
                
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = StreamBuilder<List<ProductType>>(
        stream: _categoriesStream,
        builder: (context, catSnapshot) {
          final categories = catSnapshot.data ?? [];

          return StreamBuilder<List<InventoryItemData>>(
            stream: _inventoryItemsStream,
            builder: (context, itemSnapshot) {
              if (itemSnapshot.connectionState == ConnectionState.waiting && !itemSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allItems = itemSnapshot.data ?? [];

              // Single-pass computation for categories count and stock status breakdown (O(N) instead of O(N*M))
              int inStockCount = 0;
              int lowStockCount = 0;
              int outOfStockCount = 0;
              final Map<String, int> categoryCounts = {};

              for (final item in allItems) {
                if (!item.product.isActive) continue;
                final stock = item.inventory?.quantityOnHand ?? 0.0;
                final threshold = item.product.sellBy == 'fraction' ? 5.0 : 10.0;

                if (stock <= 0) {
                  outOfStockCount++;
                } else if (stock <= threshold) {
                  lowStockCount++;
                } else {
                  inStockCount++;
                }

                categoryCounts[item.categoryId] = (categoryCounts[item.categoryId] ?? 0) + 1;
              }

              // Filter by category, active status, search query, and interactive quick stock filter
              final filteredItems = allItems.where((item) {
                if (!item.product.isActive) return false;

                final matchesCategory = _selectedCategoryId == 'all' ||
                    item.categoryId == _selectedCategoryId;
                if (!matchesCategory) return false;

                if (_selectedStockFilter != 'all') {
                  final stock = item.inventory?.quantityOnHand ?? 0.0;
                  final threshold = item.product.sellBy == 'fraction' ? 5.0 : 10.0;
                  if (_selectedStockFilter == 'inStock' && stock <= threshold) return false;
                  if (_selectedStockFilter == 'lowStock' && (stock <= 0 || stock > threshold)) return false;
                  if (_selectedStockFilter == 'outOfStock' && stock > 0) return false;
                }

                final q = _searchQuery.toLowerCase();
                final matchesSearch = q.isEmpty ||
                    item.product.productName.toLowerCase().contains(q) ||
                    (item.product.sku?.toLowerCase().contains(q) ?? false) ||
                    (item.product.barcode?.toLowerCase().contains(q) ?? false);

                return matchesSearch;
              }).toList();

              final groupedItems = _groupInventoryItems(filteredItems);

              return Column(
                children: [
                  // Search and Category Bar Container
                  Container(
                    color: AppTheme.surfaceColor,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        // Search bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search product name, SKU, or barcode...',
                            hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchDebounceTimer?.cancel();
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            isDense: true,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: 12),

                        // Categories Horizontal Scroll List
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _CategoryChip(
                                label: 'All Items',
                                count: allItems.length,
                                isSelected: _selectedCategoryId == 'all',
                                onTap: () => setState(() => _selectedCategoryId = 'all'),
                              ),
                              ...categories.map((c) {
                                final count = categoryCounts[c.id] ?? 0;
                                return _CategoryChip(
                                  label: c.typeName,
                                  count: count,
                                  isSelected: _selectedCategoryId == c.id,
                                  onTap: () => setState(() => _selectedCategoryId = c.id),
                                );
                              }),
                              if (PermissionService.instance.hasPermission(PosPermissions.inventoryCategories))
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: ActionChip(
                                    label: const Row(
                                      children: [
                                        Icon(Icons.add_rounded, size: 16, color: AppTheme.primaryColor),
                                        SizedBox(width: 4),
                                        Text('New Category', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    side: BorderSide.none,
                                    onPressed: _showAddCategoryDialog,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quick Stats bar with interactive stock status filters
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Showing ${groupedItems.length} items',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (_selectedStockFilter != 'all') ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => setState(() => _selectedStockFilter = 'all'),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.close_rounded, size: 12, color: Colors.black54),
                                      SizedBox(width: 2),
                                      Text('Reset Filter', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _MiniLegend(
                              color: AppTheme.inStockColor,
                              label: 'In Stock ($inStockCount)',
                              isSelected: _selectedStockFilter == 'inStock',
                              onTap: () => setState(() => _selectedStockFilter = _selectedStockFilter == 'inStock' ? 'all' : 'inStock'),
                            ),
                            _MiniLegend(
                              color: AppTheme.lowStockColor,
                              label: 'Low ($lowStockCount)',
                              isSelected: _selectedStockFilter == 'lowStock',
                              onTap: () => setState(() => _selectedStockFilter = _selectedStockFilter == 'lowStock' ? 'all' : 'lowStock'),
                            ),
                            _MiniLegend(
                              color: AppTheme.outOfStockColor,
                              label: 'Out ($outOfStockCount)',
                              isSelected: _selectedStockFilter == 'outOfStock',
                              onTap: () => setState(() => _selectedStockFilter = _selectedStockFilter == 'outOfStock' ? 'all' : 'outOfStock'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Box-like Items Grid
                  Expanded(
                    child: groupedItems.isEmpty
                        ? _buildEmptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Responsive columns based on available width:
                              // - > 1150px (Desktop POS): 5 cards per row
                              // - 880px - 1150px (Tablet Landscape): 4 cards per row
                              // - 560px - 880px (Tablet Portrait / Foldable): 3 cards per row
                              // - 340px - 560px (Phones): 2 cards per row (grid boxes)
                              // - < 340px (Ultra-narrow): 1 card per row
                              final int crossAxisCount;
                              final double childAspectRatio;

                              if (constraints.maxWidth > 1150) {
                                crossAxisCount = 5;
                                childAspectRatio = 0.86;
                              } else if (constraints.maxWidth > 880) {
                                crossAxisCount = 4;
                                childAspectRatio = 0.85;
                              } else if (constraints.maxWidth > 560) {
                                crossAxisCount = 3;
                                childAspectRatio = 0.84;
                              } else if (constraints.maxWidth > 340) {
                                crossAxisCount = 2;
                                childAspectRatio = 0.82;
                              } else {
                                crossAxisCount = 1;
                                childAspectRatio = 1.6;
                              }

                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: childAspectRatio,
                                ),
                                itemCount: groupedItems.length,
                                itemBuilder: (context, index) {
                                  final grouped = groupedItems[index];
                                  final isMulti = grouped.isMultiVariant;
                                  final primary = grouped.primaryItem;

                                  return InventoryItemCard(
                                    key: Key('inventory_card_${primary.product.id}'),
                                    productName: grouped.productName,
                                    categoryName: grouped.categoryName,
                                    sku: isMulti ? null : primary.product.sku,
                                    barcode: isMulti ? null : primary.product.barcode,
                                    price: isMulti ? grouped.minPrice : primary.product.price,
                                    priceRange: isMulti
                                        ? (grouped.minPrice == grouped.maxPrice
                                            ? '₱${grouped.minPrice.toStringAsFixed(2)}'
                                            : '₱${grouped.minPrice.toStringAsFixed(2)} – ₱${grouped.maxPrice.toStringAsFixed(2)}')
                                        : null,
                                    variantCount: isMulti ? grouped.variants.length : null,
                                    variantName: isMulti ? null : primary.product.variantName,
                                    variantDetails: isMulti
                                        ? grouped.variants.map((v) => (
                                            name: v.product.variantName ?? 'Standard',
                                            price: '₱${v.product.price.toStringAsFixed(2)}',
                                          )).toList()
                                        : null,
                                    imagePath: primary.product.imagePath,
                                    imageUrl: primary.product.imageUrl,
                                    stockQuantity: grouped.totalStock,
                                    unit: grouped.unit,
                                    sellBy: grouped.sellBy,
                                    canEdit: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
                                    canAdjustStock: PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock),
                                    onTap: () {
                                      if (isMulti) {
                                        _showProductVariantsSheet(grouped, categories);
                                      } else {
                                        if (PermissionService.instance.hasPermission(PosPermissions.inventoryEdit) ||
                                            PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock)) {
                                          _showEditProductDialog(primary, categories);
                                        }
                                      }
                                    },
                                    onQuickStockTap: () {
                                      if (isMulti) {
                                        _showProductVariantsSheet(grouped, categories);
                                      } else {
                                        if (PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock) ||
                                            PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)) {
                                          _showEditProductDialog(primary, categories);
                                        }
                                      }
                                    },
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      );

    if (!widget.showScaffold) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: AdminDrawer(
        db: widget.db,
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            tooltip: 'Navigation Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inventory'),
            Text(
              'Admin Catalog & Stock',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<List<ProductType>>(
            stream: _categoriesStream,
            builder: (context, snapshot) {
              final categories = snapshot.data ?? [];
              if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Add Item',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _showAddItemDialog(categories),
                ),
              );
            },
          ),
        ],
      ),
      body: content,
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No matching items found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search or category filter',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor : AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : AppTheme.cardBorderColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniLegend extends StatelessWidget {
  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _MiniLegend({
    required this.color,
    required this.label,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? color : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
