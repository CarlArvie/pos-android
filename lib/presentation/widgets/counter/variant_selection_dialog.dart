import 'package:flutter/material.dart';
import '../../models/cart_item.dart';
import '../../models/grouped_product.dart';
import '../../theme/app_theme.dart';

/// Modal dialog for POS Counter cashiers to quickly select a variant (size, flavor, etc.)
/// when tapping a multi-variant product card.
class VariantSelectionDialog extends StatelessWidget {
  final GroupedPosProduct groupedProduct;
  final List<CartItem> cart;

  const VariantSelectionDialog({
    super.key,
    required this.groupedProduct,
    required this.cart,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.style_rounded, color: AppTheme.accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupedProduct.productName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Select size / variant (${groupedProduct.variants.length} available)',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Variant Options
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: groupedProduct.variants.map((variant) {
                      final variantName = (variant.variantName != null && variant.variantName!.isNotEmpty)
                          ? variant.variantName!
                          : 'Standard';

                      final cartIndex = cart.indexWhere((item) => item.product.id == variant.id);
                      final inCart = cartIndex >= 0;
                      final cartQty = inCart ? cart[cartIndex].quantity : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: inCart
                              ? AppTheme.accentColor.withValues(alpha: 0.06)
                              : AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: Key('select_variant_option_${variant.id}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, variant),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: inCart ? AppTheme.accentColor : AppTheme.cardBorderColor,
                                  width: inCart ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          variantName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                        if (variant.sku != null && variant.sku!.isNotEmpty)
                                          Text(
                                            'SKU: ${variant.sku}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '₱${variant.price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (inCart)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        variant.sellBy == 'fraction'
                                            ? '${cartQty.toStringAsFixed(1)}kg'
                                            : 'x${cartQty.toInt()}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.add_rounded, size: 16, color: AppTheme.primaryColor),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
