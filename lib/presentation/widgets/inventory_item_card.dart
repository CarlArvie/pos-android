import 'package:flutter/material.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../theme/app_theme.dart';
import 'common/product_thumbnail.dart';

class InventoryItemCard extends StatelessWidget {
  final String productName;
  final String categoryName;
  final String? sku;
  final String? barcode;
  final double price;
  final double stockQuantity;
  final String unit;
  final String sellBy;
  final String? variantName;
  final int? variantCount;
  final String? priceRange;
  final List<({String name, String price})>? variantDetails;
  final String? imagePath;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onQuickStockTap;
  final bool? canEdit;
  final bool? canAdjustStock;

  const InventoryItemCard({
    super.key,
    required this.productName,
    required this.categoryName,
    this.sku,
    this.barcode,
    required this.price,
    required this.stockQuantity,
    required this.unit,
    this.sellBy = 'unit',
    this.variantName,
    this.variantCount,
    this.priceRange,
    this.variantDetails,
    this.imagePath,
    this.imageUrl,
    required this.onTap,
    required this.onQuickStockTap,
    this.canEdit,
    this.canAdjustStock,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCanEdit =
        canEdit ??
        PermissionService.instance.hasPermission(PosPermissions.inventoryEdit);
    final effectiveCanAdjust =
        canAdjustStock ??
        PermissionService.instance.hasPermission(
          PosPermissions.inventoryAdjustStock,
        );
    final isMulti = variantCount != null && variantCount! > 1;
    final canInteract = isMulti || effectiveCanEdit || effectiveCanAdjust;

    final isOutOfStock = stockQuantity <= 0;
    final isLowStock =
        stockQuantity > 0 &&
        stockQuantity <= (sellBy == 'fraction' ? 5.0 : 10.0);

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

    final formattedQty = sellBy == 'fraction'
        ? stockQuantity.toStringAsFixed(3)
        : stockQuantity.toStringAsFixed(0);

    final statusText = isOutOfStock
        ? 'Out of stock'
        : isLowStock
        ? '$formattedQty $unit left'
        : '$formattedQty $unit';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canInteract ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorderColor, width: 1.0),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Section: Image with floating category & stock badges
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: AppTheme.cardBorderColor.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductThumbnail(
                        imagePath: imagePath,
                        imageUrl: imageUrl,
                        categoryName: categoryName,
                        fallbackIconSize: 28,
                        borderRadius: BorderRadius.circular(8),
                      ),

                      // Top-Left: Category Tag
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppTheme.cardBorderColor,
                              width: 0.6,
                            ),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 80),
                            child: Text(
                              categoryName,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),

                      // Top-Right: Stock status badge
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom-Right: Variants badge (if multi) or variant name
                      if (variantCount != null && variantCount! > 1)
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.shade400,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '$variantCount Sizes',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        )
                      else if (variantName != null && variantName!.isNotEmpty)
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.accentColor.withValues(
                                  alpha: 0.25,
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              variantName!,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Bottom Section: Product Name, SKU, Variants details, and Price row
              Text(
                productName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              if (sku != null && sku!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    'SKU: $sku',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Colors.grey.shade600,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              if (variantDetails != null && variantDetails!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: variantDetails!.take(3).map((vd) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: AppTheme.cardBorderColor,
                            width: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              vd.name,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              vd.price,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 5),

              // Price and Action Button Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      priceRange ?? '₱${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMulti)
                    InkWell(
                      key: const Key('inventory_item_sizes_button'),
                      onTap: onQuickStockTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.format_list_bulleted_rounded,
                              size: 12,
                              color: AppTheme.accentColor,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Sizes',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (effectiveCanEdit)
                    InkWell(
                      key: const Key('inventory_item_edit_button'),
                      onTap: onQuickStockTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 13,
                              color: AppTheme.accentColor,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Edit Item',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (effectiveCanAdjust)
                    InkWell(
                      key: const Key('inventory_item_adjust_button'),
                      onTap: onQuickStockTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 13,
                              color: AppTheme.accentColor,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Adjust Stock',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
