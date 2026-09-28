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
    final effectiveCanEdit = canEdit ?? PermissionService.instance.hasPermission(PosPermissions.inventoryEdit);
    final effectiveCanAdjust = canAdjustStock ?? PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock);
    final isMulti = variantCount != null && variantCount! > 1;
    final canInteract = isMulti || effectiveCanEdit || effectiveCanAdjust;

    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= (sellBy == 'fraction' ? 5.0 : 10.0);

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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.cardBorderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, cardConstraints) {
              final isNarrow = cardConstraints.maxWidth < 180;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Category tag + Stock status badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Category tag (Expanded absorbs available space without overflowing)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            categoryName,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Stock indicator dot + pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(5),
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
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: cardConstraints.maxWidth * 0.48,
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Middle: Box-like visual icon container with variant badge
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.cardBorderColor.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: ProductThumbnail(
                              imagePath: imagePath,
                              imageUrl: imageUrl,
                              categoryName: categoryName,
                              fallbackIconSize: isNarrow ? 28 : 34,
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          if (variantCount != null && variantCount! > 1)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.amber.shade400, width: 0.8),
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
                            ),
                          if (variantDetails != null && variantDetails!.isNotEmpty)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: cardConstraints.maxWidth - 16,
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: variantDetails!.take(3).map((vd) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.cardBorderColor, width: 0.6),
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
                            )
                          else if (variantName != null && variantName!.isNotEmpty)
                            Positioned(
                              bottom: 5,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: cardConstraints.maxWidth - 24,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppTheme.accentColor.withValues(alpha: 0.25),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  variantName!,
                                  style: const TextStyle(
                                    fontSize: 9.5,
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
                  const SizedBox(height: 8),

                  // Name & SKU
                  Text(
                    productName,
                    style: TextStyle(
                      fontSize: isNarrow ? 12.5 : 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sku != null && sku!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'SKU: $sku',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, thickness: 1, color: AppTheme.cardBorderColor),
                  const SizedBox(height: 6),

                  // Bottom Row: Price + Quick Action Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          priceRange ?? '₱${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: isNarrow ? 13 : 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryColor,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMulti) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          key: const Key('inventory_item_sizes_button'),
                          onTap: onQuickStockTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 6 : 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.format_list_bulleted_rounded,
                                  size: 14,
                                  color: AppTheme.accentColor,
                                ),
                                const SizedBox(width: 3),
                                const Text(
                                  'Sizes',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (effectiveCanEdit) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          key: const Key('inventory_item_edit_button'),
                          onTap: onQuickStockTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 6 : 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.edit_note_rounded,
                                  size: 14,
                                  color: AppTheme.accentColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isNarrow ? 'Edit' : 'Edit Item',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (effectiveCanAdjust) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          key: const Key('inventory_item_adjust_button'),
                          onTap: onQuickStockTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 6 : 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.tune_rounded,
                                  size: 14,
                                  color: AppTheme.accentColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isNarrow ? 'Stock' : 'Adjust Stock',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
