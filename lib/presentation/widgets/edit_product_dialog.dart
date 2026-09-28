import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/local/database.dart';
import '../../core/device_prefs.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../../core/services/product_image_service.dart';
import '../theme/app_theme.dart';
import 'common/product_image_picker.dart';
import 'inventory/add_variant_dialog.dart';

class EditProductDialog extends StatefulWidget {
  final AppDatabase db;
  final Product product;
  final Inventory? inventory;
  final List<ProductType> categories;

  const EditProductDialog({
    super.key,
    required this.db,
    required this.product,
    required this.inventory,
    required this.categories,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _stockController;
  late final TextEditingController _variantController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _skuController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;

  // Selections
  String? _selectedCategoryId;
  late String _sellBy;
  late String _unit;
  late bool _addTax;
  late bool _trackExpiry;
  DateTime? _expiryDate;
  late bool _isActive;
  List<Product> _siblingVariants = [];

  // Image Attachment
  XFile? _pickedImageFile;
  String? _localImagePath;
  String? _cloudImageUrl;
  bool _imageRemoved = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final inv = widget.inventory;

    _localImagePath = p.imagePath;
    _cloudImageUrl = p.imageUrl;

    _nameController = TextEditingController(text: p.productName);
    _priceController = TextEditingController(text: p.price.toStringAsFixed(2));
    _costPriceController = TextEditingController(text: p.costPrice.toStringAsFixed(2));

    final stockVal = inv?.quantityOnHand ?? 0.0;
    _stockController = TextEditingController(
      text: p.sellBy == 'fraction' ? stockVal.toStringAsFixed(3) : stockVal.toStringAsFixed(0),
    );

    _variantController = TextEditingController(text: p.variantName ?? '');
    _barcodeController = TextEditingController(text: p.barcode ?? '');
    _skuController = TextEditingController(text: p.sku ?? '');
    _taxRateController = TextEditingController(
      text: p.taxPercent > 0 ? p.taxPercent.toStringAsFixed(1) : '12.0',
    );
    _notesController = TextEditingController(text: p.notes ?? '');
    _tagsController = TextEditingController(text: p.tags ?? '');

    _selectedCategoryId = p.productTypeId;
    _sellBy = p.sellBy;
    _unit = p.unit;
    _addTax = p.taxPercent > 0;
    _trackExpiry = p.trackExpiry;
    _expiryDate = p.expiryDate;
    _isActive = p.isActive;

    _loadSiblingVariants();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _variantController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _taxRateController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _onSellByChanged(String? val) {
    if (val == null) return;
    setState(() {
      _sellBy = val;
      if (_sellBy == 'fraction') {
        _unit = 'kg';
        final curr = double.tryParse(_stockController.text) ?? 0.0;
        _stockController.text = curr.toStringAsFixed(3);
      } else {
        _unit = 'pcs';
        final curr = double.tryParse(_stockController.text) ?? 0.0;
        _stockController.text = curr.toStringAsFixed(0);
      }
    });
  }

  void _adjustStock(double delta) {
    final curr = double.tryParse(_stockController.text.trim()) ?? 0.0;
    final updated = (curr + delta).clamp(0.0, 999999.0);
    setState(() {
      _stockController.text = _sellBy == 'fraction'
          ? updated.toStringAsFixed(3)
          : updated.toStringAsFixed(0);
    });
  }

  Future<void> _loadSiblingVariants() async {
    try {
      final results = await (widget.db.select(widget.db.products)
            ..where((p) =>
                p.productName.equals(widget.product.productName) &
                p.companyId.equals(widget.product.companyId) &
                p.isDeleted.equals(false) &
                p.isActive.equals(true)))
          .get();
      if (mounted) {
        setState(() {
          _siblingVariants = results;
        });
      }
    } catch (_) {}
  }

  Future<void> _showAddVariantDialog() async {
    final categoriesMap = {for (final c in widget.categories) c.id: c.typeName};
    final categoryName = _selectedCategoryId != null ? categoriesMap[_selectedCategoryId] : null;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AddVariantDialog(
        db: widget.db,
        productName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : widget.product.productName,
        productTypeId: _selectedCategoryId,
        categoryName: categoryName,
        companyId: widget.product.companyId,
        unit: _unit,
        sellBy: _sellBy,
        defaultPrice: double.tryParse(_priceController.text.trim()) ?? widget.product.price,
        defaultCostPrice: double.tryParse(_costPriceController.text.trim()) ?? widget.product.costPrice,
        taxPercent: _addTax ? (double.tryParse(_taxRateController.text.trim()) ?? 0.0) : 0.0,
        trackExpiry: _trackExpiry,
        expiryDate: _expiryDate,
        tags: _tagsController.text.trim(),
      ),
    );

    if (added == true) {
      await _loadSiblingVariants();
    }
  }

  Future<void> _switchToVariant(Product sibling) async {
    if (sibling.id == widget.product.id) return;
    final activeStoreId = DevicePrefs.storeId;
    final invQuery = widget.db.select(widget.db.inventories)
      ..where((i) => i.productId.equals(sibling.id) & i.isDeleted.equals(false));
    if (activeStoreId != null && activeStoreId.isNotEmpty) {
      invQuery.where((i) => i.storeId.equals(activeStoreId));
    }
    final invList = await invQuery.get();
    final inv = invList.isNotEmpty ? invList.first : null;

    if (mounted) {
      Navigator.pop(context, false);
      showDialog(
        context: context,
        builder: (ctx) => EditProductDialog(
          db: widget.db,
          product: sibling,
          inventory: inv,
          categories: widget.categories,
        ),
      );
    }
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _saveChanges() async {
    final hasEdit = PermissionService.instance.hasPermission(PosPermissions.inventoryEdit);
    final hasAdjust = PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock);

    if (!hasEdit && !hasAdjust) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to edit products or adjust stock.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;

    // 1. Update Product record if user has inventoryEdit
    if (hasEdit) {
      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      final costPrice = double.tryParse(_costPriceController.text.trim()) ?? widget.product.costPrice;
      final name = _nameController.text.trim();
      final sku = _skuController.text.trim();
      final barcode = _barcodeController.text.trim();
      final variant = _variantController.text.trim();
      final notes = _notesController.text.trim();
      final tags = _tagsController.text.trim();
      final taxRate = _addTax ? (double.tryParse(_taxRateController.text.trim()) ?? 0.0) : 0.0;

      String? finalImagePath = _localImagePath;
      String? finalImageUrl = _cloudImageUrl;

      if (_imageRemoved) {
        if (widget.product.imagePath != null && widget.product.imagePath!.isNotEmpty) {
          await ProductImageService.deleteImageLocally(widget.product.imagePath!);
        }
        finalImagePath = null;
        finalImageUrl = null;
      } else if (_pickedImageFile != null) {
        if (widget.product.imagePath != null && widget.product.imagePath!.isNotEmpty) {
          await ProductImageService.deleteImageLocally(widget.product.imagePath!);
        }
        finalImagePath = await ProductImageService.saveImageLocally(widget.product.id, _pickedImageFile!);
      }

      await (widget.db.update(widget.db.products)..where((p) => p.id.equals(widget.product.id))).write(
        ProductsCompanion(
          productName: drift.Value(name),
          productTypeId: drift.Value(_selectedCategoryId),
          price: drift.Value(price),
          costPrice: drift.Value(costPrice),
          unit: drift.Value(_unit),
          sellBy: drift.Value(_sellBy),
          variantName: drift.Value(variant.isEmpty ? null : variant),
          sku: drift.Value(sku.isEmpty ? null : sku),
          barcode: drift.Value(barcode.isEmpty ? null : barcode),
          taxPercent: drift.Value(taxRate),
          trackExpiry: drift.Value(_trackExpiry),
          expiryDate: drift.Value(_expiryDate),
          imagePath: drift.Value(finalImagePath),
          imageUrl: drift.Value(finalImageUrl),
          notes: drift.Value(notes.isEmpty ? null : notes),
          tags: drift.Value(tags.isEmpty ? null : tags),
          isActive: drift.Value(_isActive),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      
      await widget.db.posDao.queueSync('products', widget.product.id, 'UPDATE', {
        'product_name': name,
        'product_type_id': _selectedCategoryId,
        'price': price,
        'cost_price': costPrice,
        'unit': _unit,
        'sell_by': _sellBy,
        'variant_name': variant.isEmpty ? null : variant,
        'sku': sku.isEmpty ? null : sku,
        'barcode': barcode.isEmpty ? null : barcode,
        'tax_percent': taxRate,
        'track_expiry': _trackExpiry,
        'expiry_date': _expiryDate?.toIso8601String(),
        'image_path': finalImagePath,
        'image_url': finalImageUrl,
        'notes': notes.isEmpty ? null : notes,
        'tags': tags.isEmpty ? null : tags,
        'is_active': _isActive,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    // 2. Update or Insert Inventory record if user has inventoryAdjustStock
    if (hasAdjust) {
      final activeStoreId = DevicePrefs.storeId;
      Inventory? targetInv = widget.inventory;

      // If widget.inventory wasn't provided, check if an inventory record already exists for this store/product
      if (targetInv == null && activeStoreId != null && activeStoreId.isNotEmpty) {
        targetInv = await (widget.db.select(widget.db.inventories)
              ..where((i) =>
                  i.productId.equals(widget.product.id) &
                  i.storeId.equals(activeStoreId) &
                  i.isDeleted.equals(false)))
            .getSingleOrNull();
      }

      if (targetInv != null) {
        await (widget.db.update(widget.db.inventories)..where((i) => i.id.equals(targetInv!.id))).write(
          InventoriesCompanion(
            quantityOnHand: drift.Value(stock),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );
        
        await widget.db.posDao.queueSync('inventories', targetInv.id, 'UPDATE', {
          'company_id': targetInv.companyId,
          'store_id': targetInv.storeId,
          'product_id': targetInv.productId,
          'quantity_on_hand': stock,
          'reorder_level': targetInv.reorderLevel,
          'unit_cost': targetInv.unitCost,
          'track_stock': targetInv.trackStock,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        final stores = await widget.db.select(widget.db.stores).get();
        final storeId = activeStoreId ?? (stores.isNotEmpty ? stores.first.id : 'default-store-001');

        // Check again before inserting to avoid UNIQUE constraint collision on (store_id, product_id)
        final existing = await (widget.db.select(widget.db.inventories)
              ..where((i) => i.storeId.equals(storeId) & i.productId.equals(widget.product.id)))
            .getSingleOrNull();

        if (existing != null) {
          await (widget.db.update(widget.db.inventories)..where((i) => i.id.equals(existing.id))).write(
            InventoriesCompanion(
              quantityOnHand: drift.Value(stock),
              isDeleted: const drift.Value(false),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          await widget.db.posDao.queueSync('inventories', existing.id, 'UPDATE', {
            'company_id': existing.companyId,
            'store_id': existing.storeId,
            'product_id': existing.productId,
            'quantity_on_hand': stock,
            'reorder_level': existing.reorderLevel,
            'unit_cost': existing.unitCost,
            'track_stock': existing.trackStock,
            'updated_at': DateTime.now().toIso8601String(),
          });
        } else {
          const uuid = Uuid();
          final invId = uuid.v4();
          final insertedInventory = await widget.db.into(widget.db.inventories).insertReturning(
            InventoriesCompanion.insert(
              id: invId,
              companyId: widget.product.companyId,
              storeId: storeId,
              productId: widget.product.id,
              quantityOnHand: drift.Value(stock),
              trackStock: const drift.Value(true),
              reorderLevel: drift.Value(_sellBy == 'fraction' ? 5.0 : 10.0),
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
        }
      }
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _confirmDelete() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryDelete)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete or archive products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Item?'),
        content: Text('Are you sure you want to deactivate "${widget.product.productName}"? It will no longer be visible for cashier checkout.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.outOfStockColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive Item'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Soft-delete: mark as inactive
      await (widget.db.update(widget.db.products)..where((p) => p.id.equals(widget.product.id))).write(
        ProductsCompanion(
          isActive: const drift.Value(false),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      
      await widget.db.posDao.queueSync('products', widget.product.id, 'UPDATE', {
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEdit = PermissionService.instance.hasPermission(PosPermissions.inventoryEdit);
    final hasAdjust = PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock);
    if (!hasEdit && !hasAdjust) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to edit this product or adjust stock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    final isTablet = screenWidth >= 680;
    final isCompactPhone = screenWidth < 420;

    final double dialogMaxWidth = isTablet ? (screenWidth > 920 ? 840.0 : screenWidth * 0.90) : (screenWidth * 0.94);
    final dialogPadding = isCompactPhone
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        : const EdgeInsets.all(22);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompactPhone ? 10 : 20,
        vertical: isCompactPhone ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: screenHeight * 0.92,
        ),
        padding: dialogPadding,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note_rounded, size: 22, color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Edit Item: ${widget.product.productName}',
                            style: const TextStyle(
                              fontSize: 17,
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
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Scrollable Responsive Form
              Flexible(
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final useTwoColumns = constraints.maxWidth >= 580;
                      if (useTwoColumns) {
                        return _buildTabletLayout();
                      } else {
                        return _buildPhoneLayout(constraints.maxWidth);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actions: Delete on left, Cancel + Save on right
              LayoutBuilder(
                builder: (context, actionConstraints) {
                  final isNarrow = actionConstraints.maxWidth < 430;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                key: const Key('save_product_button'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accentColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _saveChanges,
                                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        if (PermissionService.instance.hasPermission(PosPermissions.inventoryDelete)) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.outOfStockColor,
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('Archive Item'),
                              onPressed: _confirmDelete,
                            ),
                          ),
                        ],
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (PermissionService.instance.hasPermission(PosPermissions.inventoryDelete))
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.outOfStockColor,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Archive Item'),
                          onPressed: _confirmDelete,
                        )
                      else
                        const SizedBox.shrink(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const Key('save_product_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            ),
                            onPressed: _saveChanges,
                            child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Layouts
  // ==========================================

  Widget _buildPhoneLayout(double availableWidth) {
    final allowPaired = availableWidth >= 420;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildItemNameField(),
        const SizedBox(height: 12),
        _buildCategoryDropdown(),
        const SizedBox(height: 12),
        _buildSellByDropdown(),
        const SizedBox(height: 12),
        _buildVariantField(),
        const SizedBox(height: 12),
        _buildVariantsSection(),
        const SizedBox(height: 12),
        _buildStockEditor(),
        const SizedBox(height: 12),
        _buildPriceField(),
        const SizedBox(height: 12),
        _buildCostPriceField(),
        const SizedBox(height: 12),
        if (allowPaired)
          Row(
            children: [
              Expanded(child: _buildBarcodeField()),
              const SizedBox(width: 10),
              Expanded(child: _buildSkuField()),
            ],
          )
        else ...[
          _buildBarcodeField(),
          const SizedBox(height: 12),
          _buildSkuField(),
        ],
        const SizedBox(height: 14),
        _buildPicturePlaceholder(),
        const SizedBox(height: 14),
        _buildTaxToggle(),
        const SizedBox(height: 12),
        _buildExpiryToggle(),
        const SizedBox(height: 12),
        _buildActiveSwitch(),
        const SizedBox(height: 12),
        _buildTagsField(),
        const SizedBox(height: 12),
        _buildNotesField(),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Catalog & Identification
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(Icons.inventory_2_outlined, 'Item Identification'),
              _buildItemNameField(),
              const SizedBox(height: 12),
              _buildCategoryDropdown(),
              const SizedBox(height: 12),
              _buildSellByDropdown(),
              const SizedBox(height: 12),
              _buildVariantField(),
              const SizedBox(height: 12),
              _buildVariantsSection(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildBarcodeField(isCompact: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildSkuField()),
                ],
              ),
              const SizedBox(height: 12),
              _buildActiveSwitch(),
              const SizedBox(height: 12),
              _buildTagsField(),
            ],
          ),
        ),
        const SizedBox(width: 22),
        // Right Column: Pricing, Live Stock & Controls
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(Icons.payments_outlined, 'Pricing & Stock Management'),
              _buildPicturePlaceholder(),
              const SizedBox(height: 12),
              _buildStockEditor(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildPriceField(isCompact: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildCostPriceField()),
                ],
              ),
              const SizedBox(height: 12),
              _buildTaxToggle(),
              const SizedBox(height: 12),
              _buildExpiryToggle(),
              const SizedBox(height: 12),
              _buildNotesField(),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Component Builders
  // ==========================================

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemNameField() {
    return TextFormField(
      key: const Key('product_name_input'),
      controller: _nameController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      decoration: const InputDecoration(
        labelText: 'Item Name *',
        hintText: 'e.g. Fuji Apples or Ground Beef',
      ),
      validator: (val) => val == null || val.trim().isEmpty ? 'Item name required' : null,
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedCategoryId,
      decoration: const InputDecoration(labelText: 'Category *'),
      items: widget.categories.map((c) {
        return DropdownMenuItem(
          value: c.id,
          child: Text(
            c.typeName,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)
          ? (val) => setState(() => _selectedCategoryId = val)
          : null,
    );
  }

  Widget _buildSellByDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('sell_by_dropdown'),
      isExpanded: true,
      initialValue: _sellBy,
      decoration: InputDecoration(
        labelText: 'Sell Unit Type *',
        helperText: _sellBy == 'fraction'
            ? '1:1000 scale: 1.000 kg = 1000g, 0.250 kg = 250g'
            : 'Sold as a whole discrete unit (e.g. 1, 2, 3 pcs)',
        helperStyle: TextStyle(
          fontSize: 11,
          color: _sellBy == 'fraction' ? AppTheme.accentColor : Colors.grey.shade600,
          fontWeight: _sellBy == 'fraction' ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      items: const [
        DropdownMenuItem(
          value: 'unit',
          child: Row(
            children: [
              Icon(Icons.check_box_outline_blank_rounded, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sell by Unit (Whole & fixed: pcs, box)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        DropdownMenuItem(
          value: 'fraction',
          child: Row(
            children: [
              Icon(Icons.scale_rounded, size: 18, color: AppTheme.accentColor),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sell by Fraction (Loose 1:1000: kg, g)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
      onChanged: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)
          ? _onSellByChanged
          : null,
    );
  }

  Widget _buildVariantField() {
    return TextFormField(
      key: const Key('product_variant_input'),
      controller: _variantController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      decoration: const InputDecoration(
        labelText: 'Variant Name',
        hintText: 'e.g. 500g, Small, Hot, Regular',
      ),
    );
  }

  Widget _buildVariantsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.style_outlined, size: 17, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Sub-items / Variants (${_siblingVariants.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: AppTheme.primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) ...[
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const Key('edit_dialog_add_variant_button'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: AppTheme.accentColor),
                    foregroundColor: AppTheme.accentColor,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text(
                    'Add Variant',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showAddVariantDialog,
                ),
              ],
            ],
          ),
          if (_siblingVariants.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _siblingVariants.map((v) {
                final isCurrent = v.id == widget.product.id;
                final label = (v.variantName != null && v.variantName!.isNotEmpty)
                    ? v.variantName!
                    : 'Standard';

                return ChoiceChip(
                  key: Key('sibling_variant_chip_${v.id}'),
                  label: Text('$label • ₱${v.price.toStringAsFixed(2)}'),
                  selected: isCurrent,
                  selectedColor: AppTheme.accentColor.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? AppTheme.accentColor : AppTheme.primaryColor,
                  ),
                  onSelected: (selected) {
                    if (!isCurrent) {
                      _switchToVariant(v);
                    }
                  },
                );
              }).toList(),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Add more sizes or options (e.g. Small, Medium, Large) for this item.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockEditor() {
    final canAdjustStock = PermissionService.instance.hasPermission(PosPermissions.inventoryAdjustStock);
    final step = _sellBy == 'fraction' ? 0.250 : 1.0;
    final stepLabel = _sellBy == 'fraction' ? '0.250' : '1';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Current Stock on Hand',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (canAdjustStock)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '±$stepLabel $_unit',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (canAdjustStock) ...[
                IconButton.filledTonal(
                  key: const Key('stock_decrement_button'),
                  icon: const Icon(Icons.remove, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _adjustStock(-step),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextFormField(
                  key: const Key('product_stock_input'),
                  controller: _stockController,
                  enabled: canAdjustStock,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: canAdjustStock ? null : Colors.grey.shade600,
                  ),
                  decoration: InputDecoration(
                    suffixText: _unit,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    helperText: canAdjustStock ? null : 'Stock adjustment restricted',
                    helperStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              if (canAdjustStock) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('stock_increment_button'),
                  icon: const Icon(Icons.add, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _adjustStock(step),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceField({bool isCompact = false}) {
    return TextFormField(
      key: const Key('product_price_input'),
      controller: _priceController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _sellBy == 'fraction' ? 'Selling Price (₱/kg) *' : 'Selling Price (₱) *',
        hintText: '0.00',
        prefixIcon: isCompact ? null : const Icon(Icons.payments_outlined, size: 20),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return 'Price required';
        if (double.tryParse(val.trim()) == null) return 'Enter a valid number';
        return null;
      },
    );
  }

  Widget _buildCostPriceField() {
    return TextFormField(
      key: const Key('product_cost_price_input'),
      controller: _costPriceController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Cost Price (₱)',
        hintText: '0.00',
      ),
    );
  }

  Widget _buildBarcodeField({bool isCompact = false}) {
    return TextFormField(
      key: const Key('product_barcode_input'),
      controller: _barcodeController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      decoration: InputDecoration(
        labelText: 'Barcode',
        hintText: 'e.g. 480001001',
        prefixIcon: isCompact ? null : const Icon(Icons.qr_code_rounded, size: 20),
      ),
    );
  }

  Widget _buildSkuField() {
    return TextFormField(
      key: const Key('product_sku_input'),
      controller: _skuController,
      enabled: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit),
      decoration: const InputDecoration(
        labelText: 'SKU',
        hintText: 'e.g. BEV-001',
      ),
    );
  }

  Widget _buildActiveSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active for Sale', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  _isActive ? 'Available at checkout' : 'Hidden from checkout',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            key: const Key('active_switch'),
            value: _isActive,
            activeTrackColor: AppTheme.accentColor,
            onChanged: PermissionService.instance.hasPermission(PosPermissions.inventoryEdit)
                ? (val) => setState(() => _isActive = val)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTaxToggle() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Apply VAT / Tax', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Include tax during sale calculation', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const Key('tax_switch'),
                value: _addTax,
                activeTrackColor: AppTheme.accentColor,
                onChanged: (val) => setState(() => _addTax = val),
              ),
            ],
          ),
        ),
        if (_addTax) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('tax_rate_input'),
            controller: _taxRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tax Rate (%)',
              hintText: '12.0',
              suffixText: '%',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpiryToggle() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Track Expiration Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Monitor shelf life & expiration warning', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const Key('expiry_switch'),
                value: _trackExpiry,
                activeTrackColor: AppTheme.accentColor,
                onChanged: (val) => setState(() => _trackExpiry = val),
              ),
            ],
          ),
        ),
        if (_trackExpiry) ...[
          const SizedBox(height: 8),
          InkWell(
            key: const Key('expiry_date_picker_button'),
            onTap: _pickExpiryDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.event_rounded, size: 20, color: AppTheme.accentColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _expiryDate == null
                                ? 'Select Expiration Date'
                                : 'Expires: ${_expiryDate!.toLocal().toString().substring(0, 10)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _expiryDate != null ? FontWeight.bold : FontWeight.normal,
                              color: _expiryDate != null ? AppTheme.primaryColor : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.black54),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTagsField() {
    return TextFormField(
      key: const Key('product_tags_input'),
      controller: _tagsController,
      decoration: const InputDecoration(
        labelText: 'Tags (comma separated)',
        hintText: 'e.g. fresh, chilled, promo, meat',
        prefixIcon: Icon(Icons.tag_rounded, size: 20),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      key: const Key('product_notes_input'),
      controller: _notesController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Internal Notes',
        hintText: 'Supplier code, storage instructions, or batch notes...',
      ),
    );
  }

  Widget _buildPicturePlaceholder() {
    final catName = widget.categories
        .where((c) => c.id == _selectedCategoryId)
        .firstOrNull
        ?.typeName;

    return ProductImagePicker(
      imagePath: _localImagePath,
      imageUrl: _cloudImageUrl,
      pickedFile: _pickedImageFile,
      categoryName: catName,
      onImagePicked: (file) {
        setState(() {
          _pickedImageFile = file;
          _imageRemoved = false;
        });
      },
      onImageRemoved: () {
        setState(() {
          _pickedImageFile = null;
          _localImagePath = null;
          _cloudImageUrl = null;
          _imageRemoved = true;
        });
      },
    );
  }
}
