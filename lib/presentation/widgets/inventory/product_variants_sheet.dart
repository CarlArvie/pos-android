import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../models/grouped_product.dart';
import '../../theme/app_theme.dart';
import '../common/product_thumbnail.dart';

/// Modal bottom sheet displaying all sub-items/variants of a grouped product
/// in the Inventory screen, allowing the user to view stock/prices and edit any variant.
class ProductVariantsSheet extends StatelessWidget {
  final GroupedInventoryItem groupedItem;
  final List<ProductType> categories;
  final void Function(InventoryItemData variant) onEditVariant;
  final void Function(GroupedInventoryItem groupedItem)? onAddVariant;

  const ProductVariantsSheet({
    super.key,
    required this.groupedItem,
    required this.categories,
    required this.onEditVariant,
    this.onAddVariant,
  });

  @override
  Widget build(BuildContext context) {
    final priceRangeStr = groupedItem.minPrice == groupedItem.maxPrice
        ? '₱${groupedItem.minPrice.toStringAsFixed(2)}'
        : '₱${groupedItem.minPrice.toStringAsFixed(2)} – ₱${groupedItem.maxPrice.toStringAsFixed(2)}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              groupedItem.categoryName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${groupedItem.variants.length} Variants',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        groupedItem.productName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$priceRangeStr • Total Stock: ${groupedItem.totalStock.toStringAsFixed(groupedItem.sellBy == 'fraction' ? 3 : 0)} ${groupedItem.unit}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Variants List
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              itemCount: groupedItem.variants.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final v = groupedItem.variants[index];
                final stock = v.inventory?.quantityOnHand ?? 0.0;
                final isOutOfStock = stock <= 0;
                final isLowStock = stock > 0 && stock <= (v.product.sellBy == 'fraction' ? 5.0 : 10.0);

                final statusColor = isOutOfStock
                    ? AppTheme.outOfStockColor
                    : isLowStock
                        ? AppTheme.lowStockColor
                        : AppTheme.inStockColor;

                final statusBg = isOutOfStock
                    ? AppTheme.outOfStockBg
                    : isLowStock
                        ? AppTheme.lowStockBg
                        : AppTheme.inStockBg;

                final stockStr = v.product.sellBy == 'fraction'
                    ? '${stock.toStringAsFixed(3)} ${v.product.unit}'
                    : '${stock.toStringAsFixed(0)} ${v.product.unit}';

                final variantTitle = (v.product.variantName != null && v.product.variantName!.isNotEmpty)
                    ? v.product.variantName!
                    : 'Standard';

                return Container(
                  key: Key('variant_sheet_row_${v.product.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorderColor),
                  ),
                  child: Row(
                    children: [
                      ProductThumbnail(
                        imagePath: v.product.imagePath,
                        imageUrl: v.product.imageUrl,
                        categoryName: groupedItem.categoryName,
                        width: 44,
                        height: 44,
                        fallbackIconSize: 22,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(width: 12),
                      // Variant info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  variantTitle,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isOutOfStock ? 'Out of stock' : stockStr,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₱${v.product.price.toStringAsFixed(2)} / ${v.product.unit}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentColor,
                              ),
                            ),
                            if (v.product.sku != null || v.product.barcode != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (v.product.sku != null && v.product.sku!.isNotEmpty) 'SKU: ${v.product.sku}',
                                  if (v.product.barcode != null && v.product.barcode!.isNotEmpty) 'Barcode: ${v.product.barcode}',
                                ].join(' • '),
                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Edit or Adjust button (guarded by specific permissions)
                      if (PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          key: Key('edit_variant_button_${v.product.id}'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Edit', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(context);
                            onEditVariant(v);
                          },
                        ),
                      ] else if (PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock)) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          key: Key('adjust_variant_button_${v.product.id}'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 14),
                          label: const Text('Adjust', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(context);
                            onEditVariant(v);
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (onAddVariant != null &&
                    PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('add_variant_sheet_button'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: AppTheme.accentColor),
                        foregroundColor: AppTheme.accentColor,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Variant', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context);
                        onAddVariant!(groupedItem);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
