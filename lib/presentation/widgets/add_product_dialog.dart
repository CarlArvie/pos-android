import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../data/local/database.dart';
import '../../core/device_prefs.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/product_image_service.dart';
import 'common/product_image_picker.dart';
import '../theme/app_theme.dart';

class SubitemEntry {
  final TextEditingController variantController;
  final TextEditingController priceController;
  final TextEditingController costPriceController;
  final TextEditingController stockController;
  final TextEditingController skuController;
  final TextEditingController barcodeController;

  SubitemEntry({
    String variant = '',
    String price = '',
    String costPrice = '',
    String stock = '10',
    String sku = '',
    String barcode = '',
  })  : variantController = TextEditingController(text: variant),
        priceController = TextEditingController(text: price),
        costPriceController = TextEditingController(text: costPrice),
        stockController = TextEditingController(text: stock),
        skuController = TextEditingController(text: sku),
        barcodeController = TextEditingController(text: barcode);

  void dispose() {
    variantController.dispose();
    priceController.dispose();
    costPriceController.dispose();
    stockController.dispose();
    skuController.dispose();
    barcodeController.dispose();
  }
}

class AddProductDialog extends StatefulWidget {
  final AppDatabase db;
  final List<ProductType> categories;

  const AddProductDialog({
    super.key,
    required this.db,
    required this.categories,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();

  // Mode: true = Simple, false = Advanced
  bool _isSimpleMode = true;

  // Form Controllers
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _stockController = TextEditingController(text: '10');
  final _variantController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _taxRateController = TextEditingController(text: '12.0');
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();

  // Multi-Subitem / Variant state
  bool _hasMultipleVariants = false;
  final List<SubitemEntry> _subitems = [];

  // Image Attachment
  XFile? _pickedImageFile;
  String? _localImagePath;

  // Selections
  String? _selectedCategoryId;
  String _sellBy = 'unit'; // 'unit' or 'fraction'
  String _unit = 'pcs';
  bool _addTax = false;
  bool _trackExpiry = false;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) {
      _selectedCategoryId = widget.categories.first.id;
    }
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
    for (final s in _subitems) {
      s.dispose();
    }
    super.dispose();
  }

  void _onSellByChanged(String? val) {
    if (val == null) return;
    setState(() {
      _sellBy = val;
      if (_sellBy == 'fraction') {
        _unit = 'kg';
        if (_stockController.text == '10') {
          _stockController.text = '10.000';
        }
        for (final s in _subitems) {
          if (s.stockController.text == '10') {
            s.stockController.text = '10.000';
          }
        }
      } else {
        _unit = 'pcs';
        if (_stockController.text == '10.000') {
          _stockController.text = '10';
        }
        for (final s in _subitems) {
          if (s.stockController.text == '10.000') {
            s.stockController.text = '10';
          }
        }
      }
    });
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _saveProduct() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();
    final tags = _tagsController.text.trim();
    final taxRate = _addTax ? (double.tryParse(_taxRateController.text.trim()) ?? 0.0) : 0.0;

    if (_hasMultipleVariants && _subitems.isNotEmpty) {
      // Validate all subitems have a name and price
      for (int i = 0; i < _subitems.length; i++) {
        final vName = _subitems[i].variantController.text.trim();
        final vPrice = double.tryParse(_subitems[i].priceController.text.trim());
        if (vName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please enter a variant name for subitem #${i + 1}')),
          );
          return;
        }
        if (vPrice == null || vPrice < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please enter a valid price for subitem "$vName"')),
          );
          return;
        }
      }
    }

    const uuid = Uuid();

    // Get active tenant from DevicePrefs
    final companies = await widget.db.select(widget.db.companies).get();
    final stores = await widget.db.select(widget.db.stores).get();
    final companyId = DevicePrefs.companyId ?? (companies.isNotEmpty ? companies.first.id : 'default-company-001');
    final storeId = DevicePrefs.storeId ?? (stores.isNotEmpty ? stores.first.id : 'default-store-001');

    String? savedImagePath = _localImagePath;
    if (_pickedImageFile != null) {
      final imageId = uuid.v4();
      savedImagePath = await ProductImageService.saveImageLocally(imageId, _pickedImageFile!);
    }

    if (_hasMultipleVariants && _subitems.isNotEmpty) {
      // Atomic SQLite transaction
      await widget.db.transaction(() async {
        for (final sub in _subitems) {
          final prodId = uuid.v4();
          final invId = uuid.v4();
          final vName = sub.variantController.text.trim();
          final vPrice = double.tryParse(sub.priceController.text.trim()) ?? 0.0;
          final vCost = double.tryParse(sub.costPriceController.text.trim()) ?? 0.0;
          final vStock = double.tryParse(sub.stockController.text.trim()) ?? 0.0;
          final vSku = sub.skuController.text.trim();
          final vBarcode = sub.barcodeController.text.trim();

          final insertedProduct = await widget.db.into(widget.db.products).insertReturning(
                ProductsCompanion.insert(
                  id: prodId,
                  companyId: companyId,
                  productTypeId: drift.Value(_selectedCategoryId),
                  productName: name,
                  price: drift.Value(vPrice),
                  costPrice: drift.Value(vCost),
                  unit: drift.Value(_unit),
                  sellBy: drift.Value(_sellBy),
                  variantName: drift.Value(vName.isEmpty ? null : vName),
                  sku: drift.Value(vSku.isEmpty ? null : vSku),
                  barcode: drift.Value(vBarcode.isEmpty ? null : vBarcode),
                  taxPercent: drift.Value(taxRate),
                  imagePath: drift.Value(savedImagePath),
                  trackExpiry: drift.Value(_trackExpiry),
                  expiryDate: drift.Value(_expiryDate),
                  notes: drift.Value(notes.isEmpty ? null : notes),
                  tags: drift.Value(tags.isEmpty ? null : tags),
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
            'image_path': insertedProduct.imagePath,
            'image_url': insertedProduct.imageUrl,
            'track_expiry': insertedProduct.trackExpiry,
            'expiry_date': insertedProduct.expiryDate?.toIso8601String(),
            'notes': insertedProduct.notes,
            'tags': insertedProduct.tags,
            'is_active': insertedProduct.isActive,
          });

          final insertedInventory = await widget.db.into(widget.db.inventories).insertReturning(
                InventoriesCompanion.insert(
                  id: invId,
                  companyId: companyId,
                  storeId: storeId,
                  productId: prodId,
                  quantityOnHand: drift.Value(vStock),
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
      });
    } else {
      // Single item save
      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      final costPrice = double.tryParse(_costPriceController.text.trim()) ?? 0.0;
      final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;
      final sku = _skuController.text.trim();
      final barcode = _barcodeController.text.trim();
      final variant = _variantController.text.trim();
      final prodId = uuid.v4();
      final invId = uuid.v4();

      final insertedProduct = await widget.db.into(widget.db.products).insertReturning(
            ProductsCompanion.insert(
              id: prodId,
              companyId: companyId,
              productTypeId: drift.Value(_selectedCategoryId),
              productName: name,
              price: drift.Value(price),
              costPrice: drift.Value(costPrice),
              unit: drift.Value(_unit),
              sellBy: drift.Value(_sellBy),
              variantName: drift.Value(variant.isEmpty ? null : variant),
              sku: drift.Value(sku.isEmpty ? null : sku),
              barcode: drift.Value(barcode.isEmpty ? null : barcode),
              taxPercent: drift.Value(taxRate),
              imagePath: drift.Value(savedImagePath),
              trackExpiry: drift.Value(_trackExpiry),
              expiryDate: drift.Value(_expiryDate),
              notes: drift.Value(notes.isEmpty ? null : notes),
              tags: drift.Value(tags.isEmpty ? null : tags),
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
        'image_path': insertedProduct.imagePath,
        'image_url': insertedProduct.imageUrl,
        'track_expiry': insertedProduct.trackExpiry,
        'expiry_date': insertedProduct.expiryDate?.toIso8601String(),
        'notes': insertedProduct.notes,
        'tags': insertedProduct.tags,
        'is_active': insertedProduct.isActive,
      });

      final insertedInventory = await widget.db.into(widget.db.inventories).insertReturning(
            InventoriesCompanion.insert(
              id: invId,
              companyId: companyId,
              storeId: storeId,
              productId: prodId,
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

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to create new products.'),
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

    // Responsive dialog max width
    final double dialogMaxWidth = _isSimpleMode
        ? (screenWidth > 500 ? 460.0 : screenWidth * 0.94)
        : (isTablet ? (screenWidth > 920 ? 840.0 : screenWidth * 0.90) : (screenWidth * 0.94));

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
              // Dialog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add New Item',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mode Toggle (Simple vs Advanced)
              _buildModeToggle(),
              const SizedBox(height: 16),

              // Scrollable Responsive Form Fields
              Flexible(
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final useTwoColumns = !_isSimpleMode && constraints.maxWidth >= 580;
                      if (_isSimpleMode) {
                        return _buildSimpleModeForm();
                      } else if (useTwoColumns) {
                        return _buildAdvancedTabletForm(constraints.maxWidth);
                      } else {
                        return _buildAdvancedPhoneForm(constraints.maxWidth);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bottom Action Buttons
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Layout Variations
  // ==========================================

  Widget _buildSimpleModeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildItemNameField(),
        const SizedBox(height: 12),
        _buildCategoryDropdown(),
        const SizedBox(height: 12),
        _buildSellByDropdown(),
        const SizedBox(height: 14),
        _buildPicturePlaceholder(),
        const SizedBox(height: 14),
        _buildPriceField(),
        const SizedBox(height: 12),
        _buildStockField(isSimple: true),
      ],
    );
  }

  Widget _buildAdvancedPhoneForm(double availableWidth) {
    final allowPairedBarcodeSku = availableWidth >= 420;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildItemNameField(),
        const SizedBox(height: 12),
        _buildCategoryDropdown(),
        const SizedBox(height: 12),
        _buildSellByDropdown(),
        const SizedBox(height: 12),
        _buildMultiSubitemToggle(),
        const SizedBox(height: 14),
        if (_hasMultipleVariants) ...[
          _buildMultiSubitemBuilder(availableWidth),
        ] else ...[
          _buildVariantField(),
          const SizedBox(height: 12),
          _buildPriceField(),
          const SizedBox(height: 12),
          _buildCostPriceField(),
          const SizedBox(height: 12),
          _buildStockField(isSimple: false),
          const SizedBox(height: 12),
          if (allowPairedBarcodeSku)
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
        ],
        const SizedBox(height: 14),
        _buildPicturePlaceholder(),
        const SizedBox(height: 14),
        _buildTaxToggle(),
        const SizedBox(height: 12),
        _buildExpiryToggle(),
        const SizedBox(height: 12),
        _buildTagsField(),
        const SizedBox(height: 12),
        _buildNotesField(),
      ],
    );
  }

  Widget _buildAdvancedTabletForm(double availableWidth) {
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
              _buildMultiSubitemToggle(),
              const SizedBox(height: 12),
              if (!_hasMultipleVariants) ...[
                _buildVariantField(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildBarcodeField()),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSkuField()),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              _buildPicturePlaceholder(),
              const SizedBox(height: 12),
              _buildTagsField(),
              const SizedBox(height: 12),
              _buildNotesField(),
            ],
          ),
        ),
        const SizedBox(width: 22),
        // Right Column: Pricing, Stock & Controls (or Multi-Subitems)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasMultipleVariants) ...[
                _buildMultiSubitemBuilder(availableWidth / 2),
                const SizedBox(height: 14),
                _buildTaxToggle(),
                const SizedBox(height: 12),
                _buildExpiryToggle(),
              ] else ...[
                _buildSectionHeader(Icons.payments_outlined, 'Pricing & Stock Control'),
                Row(
                  children: [
                    Expanded(child: _buildPriceField()),
                    const SizedBox(width: 10),
                    Expanded(child: _buildCostPriceField()),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStockField(isSimple: false),
                const SizedBox(height: 12),
                _buildTaxToggle(),
                const SizedBox(height: 12),
                _buildExpiryToggle(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSubitemToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _hasMultipleVariants
            ? AppTheme.accentColor.withValues(alpha: 0.08)
            : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hasMultipleVariants
              ? AppTheme.accentColor.withValues(alpha: 0.35)
              : AppTheme.cardBorderColor,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.style_outlined, size: 20, color: AppTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Multiple Subitems / Variants',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Add sizes, portions, or colors (e.g. Small, Med, Large)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const Key('has_multiple_variants_switch'),
            value: _hasMultipleVariants,
            activeTrackColor: AppTheme.accentColor,
            onChanged: (val) {
              setState(() {
                _hasMultipleVariants = val;
                if (_hasMultipleVariants && _subitems.isEmpty) {
                  final initialStock = _sellBy == 'fraction' ? '10.000' : '10';
                  _subitems.add(SubitemEntry(
                    variant: _variantController.text.isNotEmpty ? _variantController.text : 'Small',
                    price: _priceController.text.isNotEmpty ? _priceController.text : '100.00',
                    costPrice: _costPriceController.text,
                    stock: _stockController.text.isNotEmpty ? _stockController.text : initialStock,
                    sku: _skuController.text,
                    barcode: _barcodeController.text,
                  ));
                  _subitems.add(SubitemEntry(
                    variant: 'Medium',
                    price: _priceController.text.isNotEmpty ? _priceController.text : '120.00',
                    costPrice: _costPriceController.text,
                    stock: initialStock,
                  ));
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSubitemBuilder(double availableWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(Icons.format_list_bulleted_rounded, 'Subitems / Variants (${_subitems.length})'),
        ...List.generate(_subitems.length, (index) {
          final sub = _subitems[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Subitem #${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ),
                    if (_subitems.length > 1)
                      IconButton(
                        key: Key('remove_subitem_button_$index'),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            final removed = _subitems.removeAt(index);
                            removed.dispose();
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Variant Name & Selling Price
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        key: Key('subitem_variant_input_$index'),
                        controller: sub.variantController,
                        decoration: const InputDecoration(
                          labelText: 'Variant Name *',
                          hintText: 'e.g. Small, 500g',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                        validator: (val) {
                          if (_hasMultipleVariants && (val == null || val.trim().isEmpty)) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        key: Key('subitem_price_input_$index'),
                        controller: sub.priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Price (₱) *',
                          hintText: '0.00',
                          prefixText: '₱ ',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                        validator: (val) {
                          if (_hasMultipleVariants && (val == null || val.trim().isEmpty)) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Stock & Cost Price
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: Key('subitem_stock_input_$index'),
                        controller: sub.stockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Stock ($_unit) *',
                          hintText: _sellBy == 'fraction' ? '10.000' : '10',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        key: Key('subitem_cost_input_$index'),
                        controller: sub.costPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Cost (₱)',
                          hintText: '0.00',
                          prefixText: '₱ ',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Barcode & SKU
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: Key('subitem_barcode_input_$index'),
                        controller: sub.barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode',
                          hintText: 'Optional',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        key: Key('subitem_sku_input_$index'),
                        controller: sub.skuController,
                        decoration: const InputDecoration(
                          labelText: 'SKU',
                          hintText: 'Optional',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        OutlinedButton.icon(
          key: const Key('add_subitem_row_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accentColor,
            side: const BorderSide(color: AppTheme.accentColor),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text('Add Another Subitem / Size', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () {
            setState(() {
              _subitems.add(SubitemEntry(
                stock: _sellBy == 'fraction' ? '10.000' : '10',
              ));
            });
          },
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

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isSimpleMode = true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _isSimpleMode ? AppTheme.surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _isSimpleMode
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Simple Mode',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: _isSimpleMode ? FontWeight.bold : FontWeight.w500,
                    color: _isSimpleMode ? AppTheme.accentColor : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isSimpleMode = false),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_isSimpleMode ? AppTheme.surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !_isSimpleMode
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Advanced Mode',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: !_isSimpleMode ? FontWeight.bold : FontWeight.w500,
                    color: !_isSimpleMode ? AppTheme.accentColor : Colors.grey.shade700,
                  ),
                ),
              ),
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
      onChanged: (val) => setState(() => _selectedCategoryId = val),
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
            : 'Sold as a whole, non-divisible discrete unit (e.g. 1, 2, 3 pcs)',
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
      onChanged: _onSellByChanged,
    );
  }

  Widget _buildVariantField() {
    return TextFormField(
      key: const Key('product_variant_input'),
      controller: _variantController,
      decoration: const InputDecoration(
        labelText: 'Variant Name',
        hintText: 'e.g. 500g, Small, Hot, Regular',
      ),
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      key: const Key('product_price_input'),
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _sellBy == 'fraction' ? 'Selling Price (₱/kg) *' : 'Selling Price (₱) *',
        hintText: '0.00',
        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
      ),
      validator: (val) {
        if (_hasMultipleVariants) return null;
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
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Cost Price (₱)',
        hintText: '0.00',
      ),
    );
  }

  Widget _buildStockField({required bool isSimple}) {
    return TextFormField(
      key: const Key('product_stock_input'),
      controller: _stockController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: isSimple ? 'Initial Stock Available' : 'Stock Available *',
        suffixText: _unit,
        hintText: _sellBy == 'fraction' ? '10.000' : '10',
      ),
    );
  }

  Widget _buildBarcodeField() {
    return TextFormField(
      key: const Key('product_barcode_input'),
      controller: _barcodeController,
      decoration: const InputDecoration(
        labelText: 'Barcode',
        hintText: 'e.g. 480001001',
        prefixIcon: Icon(Icons.qr_code_rounded, size: 20),
      ),
    );
  }

  Widget _buildSkuField() {
    return TextFormField(
      key: const Key('product_sku_input'),
      controller: _skuController,
      decoration: const InputDecoration(
        labelText: 'SKU',
        hintText: 'e.g. BEV-001',
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
      pickedFile: _pickedImageFile,
      categoryName: catName,
      onImagePicked: (file) {
        setState(() {
          _pickedImageFile = file;
        });
      },
      onImageRemoved: () {
        setState(() {
          _pickedImageFile = null;
          _localImagePath = null;
        });
      },
    );
  }

  Widget _buildActionButtons() {
    final saveLabel = _hasMultipleVariants && _subitems.isNotEmpty
        ? 'Save All (${_subitems.length} Subitems)'
        : 'Save Item';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
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
          onPressed: _saveProduct,
          child: Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
