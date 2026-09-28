import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../data/local/database.dart';
import '../../theme/app_theme.dart';

/// Modal dialog for quickly creating and attaching a new variant / sub-item
/// to an existing product family.
class AddVariantDialog extends StatefulWidget {
  final AppDatabase db;
  final String productName;
  final String? productTypeId;
  final String? categoryName;
  final String companyId;
  final String unit;
  final String sellBy;
  final double defaultPrice;
  final double defaultCostPrice;
  final double taxPercent;
  final bool trackExpiry;
  final DateTime? expiryDate;
  final String? tags;

  const AddVariantDialog({
    super.key,
    required this.db,
    required this.productName,
    this.productTypeId,
    this.categoryName,
    required this.companyId,
    this.unit = 'pcs',
    this.sellBy = 'unit',
    this.defaultPrice = 0.0,
    this.defaultCostPrice = 0.0,
    this.taxPercent = 0.0,
    this.trackExpiry = false,
    this.expiryDate,
    this.tags,
  });

  @override
  State<AddVariantDialog> createState() => _AddVariantDialogState();
}

class _AddVariantDialogState extends State<AddVariantDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _variantController;
  late final TextEditingController _priceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _stockController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _variantController = TextEditingController();
    _priceController = TextEditingController(
      text: widget.defaultPrice > 0 ? widget.defaultPrice.toStringAsFixed(2) : '',
    );
    _costPriceController = TextEditingController(
      text: widget.defaultCostPrice > 0 ? widget.defaultCostPrice.toStringAsFixed(2) : '',
    );
    _stockController = TextEditingController(
      text: widget.sellBy == 'fraction' ? '10.000' : '10',
    );
    _skuController = TextEditingController();
    _barcodeController = TextEditingController();
  }

  @override
  void dispose() {
    _variantController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  void _adjustStock(double delta) {
    final curr = double.tryParse(_stockController.text.trim()) ?? 0.0;
    final updated = (curr + delta).clamp(0.0, 999999.0);
    setState(() {
      _stockController.text = widget.sellBy == 'fraction'
          ? updated.toStringAsFixed(3)
          : updated.toStringAsFixed(0);
    });
  }

  Future<void> _saveVariant() async {
    final hasPerm = PermissionService.instance.hasPermission(PosPermissions.inventoryAdd);

    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add product variants.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final vName = _variantController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final costPrice = double.tryParse(_costPriceController.text.trim()) ?? 0.0;
    final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;
    final sku = _skuController.text.trim();
    final barcode = _barcodeController.text.trim();

    setState(() => _isSaving = true);

    try {
      const uuid = Uuid();
      final prodId = uuid.v4();
      final invId = uuid.v4();

      final stores = await widget.db.select(widget.db.stores).get();
      final storeId = DevicePrefs.storeId ?? (stores.isNotEmpty ? stores.first.id : 'default-store-001');

      await widget.db.transaction(() async {
        final insertedProduct = await widget.db.into(widget.db.products).insertReturning(
              ProductsCompanion.insert(
                id: prodId,
                companyId: widget.companyId,
                productTypeId: drift.Value(widget.productTypeId),
                productName: widget.productName,
                price: drift.Value(price),
                costPrice: drift.Value(costPrice),
                unit: drift.Value(widget.unit),
                sellBy: drift.Value(widget.sellBy),
                variantName: drift.Value(vName),
                sku: drift.Value(sku.isEmpty ? null : sku),
                barcode: drift.Value(barcode.isEmpty ? null : barcode),
                taxPercent: drift.Value(widget.taxPercent),
                trackExpiry: drift.Value(widget.trackExpiry),
                expiryDate: drift.Value(widget.expiryDate),
                tags: drift.Value(widget.tags),
                isActive: const drift.Value(true),
              ),
            );

        await widget.db.posDao.queueSync('products', insertedProduct.id, 'INSERT', {
          'id': insertedProduct.id,
          'company_id': insertedProduct.companyId,
          'product_type_id': insertedProduct.productTypeId,
          'product_name': insertedProduct.productName,
          'price': insertedProduct.price,
          'cost_price': insertedProduct.costPrice,
          'unit': insertedProduct.unit,
          'sell_by': insertedProduct.sellBy,
          'variant_name': insertedProduct.variantName,
          'sku': insertedProduct.sku,
          'barcode': insertedProduct.barcode,
          'tax_percent': insertedProduct.taxPercent,
          'track_expiry': insertedProduct.trackExpiry,
          'expiry_date': insertedProduct.expiryDate?.toIso8601String(),
          'tags': insertedProduct.tags,
          'is_active': insertedProduct.isActive,
        });

        final insertedInventory = await widget.db.into(widget.db.inventories).insertReturning(
              InventoriesCompanion.insert(
                id: invId,
                companyId: widget.companyId,
                storeId: storeId,
                productId: prodId,
                quantityOnHand: drift.Value(stock),
                trackStock: const drift.Value(true),
                reorderLevel: drift.Value(widget.sellBy == 'fraction' ? 5.0 : 10.0),
              ),
            );

        await widget.db.posDao.queueSync('inventories', insertedInventory.id, 'INSERT', {
          'id': insertedInventory.id,
          'company_id': insertedInventory.companyId,
          'store_id': insertedInventory.storeId,
          'product_id': insertedInventory.productId,
          'quantity_on_hand': insertedInventory.quantityOnHand,
          'track_stock': insertedInventory.trackStock,
          'reorder_level': insertedInventory.reorderLevel,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added variant "$vName" to ${widget.productName}'),
            backgroundColor: AppTheme.accentColor,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding variant: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isCompact = screenWidth < 420;

    final step = widget.sellBy == 'fraction' ? 0.250 : 1.0;
    final stepLabel = widget.sellBy == 'fraction' ? '0.250' : '1';

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: mediaQuery.size.height * 0.90,
        ),
        padding: EdgeInsets.all(isCompact ? 16 : 22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add_to_photos_rounded, size: 20, color: AppTheme.accentColor),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Add Sub-item / Variant',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
              const SizedBox(height: 10),

              // Parent Product Info Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorderColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.productName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.categoryName != null && widget.categoryName!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.categoryName!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Form fields in scrollable view
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Variant Name
                      TextFormField(
                        key: const Key('add_variant_name_input'),
                        controller: _variantController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Variant / Size Name *',
                          hintText: 'e.g. Small, Medium, Large, 500g, Hot',
                          prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Variant name required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Price & Cost Price
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('add_variant_price_input'),
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Price (₱/${widget.unit}) *',
                                hintText: '0.00',
                                prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Price required';
                                final p = double.tryParse(val.trim());
                                if (p == null || p < 0) return 'Invalid price';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              key: const Key('add_variant_cost_input'),
                              controller: _costPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Cost (₱)',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stock on Hand stepper
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.cardBorderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Initial Stock on Hand',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '±$stepLabel ${widget.unit}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.remove, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _adjustStock(-step),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    key: const Key('add_variant_stock_input'),
                                    controller: _stockController,
                                    textAlign: TextAlign.center,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      suffixText: widget.unit,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _adjustStock(step),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Barcode & SKU
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('add_variant_barcode_input'),
                              controller: _barcodeController,
                              decoration: const InputDecoration(
                                labelText: 'Barcode',
                                hintText: 'e.g. 480001001',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              key: const Key('add_variant_sku_input'),
                              controller: _skuController,
                              decoration: const InputDecoration(
                                labelText: 'SKU',
                                hintText: 'e.g. TEA-XL',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      key: const Key('submit_add_variant_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Add Variant',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSaving ? null : _saveVariant,
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
