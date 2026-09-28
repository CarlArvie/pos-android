import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/local/database.dart';
import '../../data/local/daos/pos_dao.dart';
import '../../core/device_prefs.dart';
import '../models/cart_item.dart';
import '../theme/app_theme.dart';
import '../widgets/counter/weighed_item_dialog.dart';
import '../widgets/counter/checkout_dialog.dart';
import '../widgets/counter/open_shift_dialog.dart';
import '../widgets/counter/close_shift_dialog.dart';
import '../widgets/counter/price_override_dialog.dart';
import '../widgets/counter/custom_discount_dialog.dart';
import '../widgets/counter/quantity_input_dialog.dart';
import '../widgets/counter/cash_adjustment_dialog.dart';
import '../widgets/customers/add_customer_dialog.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../widgets/auth/manager_override_dialog.dart';
import '../models/grouped_product.dart';
import '../widgets/counter/variant_selection_dialog.dart';
import '../widgets/counter/sync_status_badge.dart';
import '../widgets/common/product_thumbnail.dart';

class CounterView extends StatefulWidget {
  final AppDatabase db;

  const CounterView({super.key, required this.db});

  @override
  State<CounterView> createState() => _CounterViewState();
}

class _CounterViewState extends State<CounterView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _selectedCategoryId = 'all';
  String _searchQuery = '';

  // Persistent streams initialized once in initState
  late Stream<CashManagement?> _activeShiftStream;
  late Stream<List<ProductType>> _categoriesStream;
  late Stream<List<Product>> _productsStream;

  // Active Cart State & O(1) quantity index
  final List<CartItem> _cart = [];
  final Map<String, double> _cartItemQuantities = {};
  double _overallDiscount = 0.0;
  String _discountType = 'none'; // 'none', 'pwd_senior_20', 'custom'
  String _discountLabel = 'Discount'; // display label for cart summary
  final List<List<CartItem>> _heldCarts = [];
  Customer? _selectedCustomer;

  // Memoized grouped products
  List<Product>? _lastFilteredProducts;
  List<GroupedPosProduct> _cachedGroupedProducts = const [];

  @override
  void initState() {
    super.initState();
    _initStreams();
    PermissionService.instance.changeNotifier.addListener(
      _onPermissionsChanged,
    );
  }

  void _initStreams() {
    final regId = DevicePrefs.registerId ?? 'default-reg-001';
    final empId = DevicePrefs.currentEmployeeId;
    _activeShiftStream = PosDao(
      widget.db,
    ).watchActiveShift(regId, employeeId: empId);
    _categoriesStream = (widget.db.select(
      widget.db.productTypes,
    )..where((c) => c.isDeleted.equals(false))).watch();
    _productsStream =
        (widget.db.select(widget.db.products)
              ..where((p) => p.isActive.equals(true))
              ..where((p) => p.isDeleted.equals(false)))
            .watch();
  }

  @override
  void didUpdateWidget(covariant CounterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) {
      _initStreams();
      _lastFilteredProducts = null;
      _cachedGroupedProducts = const [];
    }
  }

  void _rebuildCartQuantities() {
    _cartItemQuantities.clear();
    for (final item in _cart) {
      _cartItemQuantities[item.product.id] =
          (_cartItemQuantities[item.product.id] ?? 0.0) + item.quantity;
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    if (val.isEmpty) {
      setState(() => _searchQuery = '');
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() => _searchQuery = val);
        }
      });
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _onPermissionsChanged() {
    if (mounted) setState(() {});
  }

  void _openOpenShiftModal() async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.posShiftOpen,
    )) {
      final authorized = await ManagerOverrideDialog.requestOverride(
        context,
        widget.db,
        'Open Cash Drawer Shift',
      );
      if (!authorized) return;
    }
    if (!mounted) return;

    final companyId = DevicePrefs.companyId ?? 'default-company-001';
    final storeId = DevicePrefs.storeId ?? 'default-store-001';
    final registerId = DevicePrefs.registerId ?? 'default-reg-001';
    final regName =
        (registerId == 'default-reg-001' ||
            registerId.startsWith('default-reg-'))
        ? 'Main Checkout #1'
        : 'Register #${registerId.length > 4 ? registerId.substring(0, 4) : registerId}';

    showDialog(
      context: context,
      builder: (ctx) => OpenShiftDialog(
        db: widget.db,
        companyId: companyId,
        storeId: storeId,
        registerId: registerId,
        registerName: regName,
        onShiftOpened: () => setState(() {}),
      ),
    );
  }

  void _openCloseShiftModal(CashManagement shift) async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.posShiftClose,
    )) {
      final authorized = await ManagerOverrideDialog.requestOverride(
        context,
        widget.db,
        'Close Cash Drawer Shift',
      );
      if (!authorized) return;
    }
    if (!mounted) return;

    final registerId = DevicePrefs.registerId ?? 'default-reg-001';
    final regName =
        (registerId == 'default-reg-001' ||
            registerId.startsWith('default-reg-'))
        ? 'Main Checkout #1'
        : 'Register #${registerId.length > 4 ? registerId.substring(0, 4) : registerId}';

    showDialog(
      context: context,
      builder: (ctx) => CloseShiftDialog(
        db: widget.db,
        shift: shift,
        registerName: regName,
        onShiftClosed: () => setState(() {}),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    PermissionService.instance.changeNotifier.removeListener(
      _onPermissionsChanged,
    );
    _searchController.dispose();
    super.dispose();
  }

  // Cart Computations
  double get _cartSubtotal =>
      _cart.fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));

  double get _cartDiscountTotal {
    if (_discountType == 'pwd_senior_20') {
      return _cartSubtotal * (DevicePrefs.seniorPwdDiscountPercent / 100.0);
    }
    return _overallDiscount.clamp(0.0, _cartSubtotal);
  }

  double get _cartTaxTotal {
    if (_cart.isEmpty) return 0.0;
    // Compute gross tax as sum of per-item tax amounts
    double grossTax = 0.0;
    for (final item in _cart) {
      if (item.product.taxPercent > 0) {
        grossTax += item.rawTotal * (item.product.taxPercent / 100.0);
      }
    }
    if (grossTax <= 0) return 0.0;
    // Apply discount proportionally to taxable base
    final discountRatio = _cartSubtotal > 0
        ? (_cartDiscountTotal / _cartSubtotal).clamp(0.0, 1.0)
        : 0.0;
    return grossTax * (1.0 - discountRatio);
  }

  double get _cartGrandTotal {
    final total = (_cartSubtotal - _cartDiscountTotal) + _cartTaxTotal;
    return total > 0 ? total : 0.0;
  }

  // --- Cart Actions ---
  Future<void> _onProductTapped(Product product) async {
    if (product.sellBy == 'fraction') {
      // Prompt for weight
      final weight = await showDialog<double>(
        context: context,
        builder: (ctx) => WeighedItemDialog(product: product),
      );
      if (weight != null && weight > 0) {
        _addToCart(product, weight);
      }
    } else {
      // Unit item: increment or add 1
      _addToCart(product, 1.0);
    }
  }

  Future<void> _onGroupedProductTapped(GroupedPosProduct groupedProduct) async {
    if (groupedProduct.isMultiVariant) {
      final selectedVariant = await showDialog<Product?>(
        context: context,
        builder: (ctx) =>
            VariantSelectionDialog(groupedProduct: groupedProduct, cart: _cart),
      );
      if (selectedVariant != null) {
        _onProductTapped(selectedVariant);
      }
    } else {
      _onProductTapped(groupedProduct.primaryProduct);
    }
  }

  List<GroupedPosProduct> _groupPosProducts(List<Product> products) {
    final Map<String, List<Product>> groups = {};
    for (final p in products) {
      final key =
          '${p.productTypeId ?? "all"}::${p.productName.trim().toLowerCase()}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    return groups.values.map((group) {
      final first = group.first;
      return GroupedPosProduct(
        productName: first.productName,
        productTypeId: first.productTypeId,
        variants: group,
      );
    }).toList();
  }

  List<GroupedPosProduct> _getGroupedProducts(List<Product> products) {
    if (identical(_lastFilteredProducts, products)) {
      return _cachedGroupedProducts;
    }
    _lastFilteredProducts = products;
    _cachedGroupedProducts = _groupPosProducts(products);
    return _cachedGroupedProducts;
  }

  void _addToCart(Product product, double qty) {
    setState(() {
      final existingIndex = _cart.indexWhere(
        (item) => item.product.id == product.id,
      );
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity += qty;
      } else {
        _cart.add(
          CartItem(product: product, quantity: qty, unitPrice: product.price),
        );
      }
      _rebuildCartQuantities();
    });
  }

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _cart[index];
      final newQty = item.quantity + delta;
      if (newQty <= 0.001) {
        _cart.removeAt(index);
      } else {
        item.quantity = newQty;
      }
      _rebuildCartQuantities();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
      _rebuildCartQuantities();
    });
  }

  void _clearCart() async {
    if (_cart.isEmpty) return;
    if (!PermissionService.instance.hasPermission(PosPermissions.posVoidCart)) {
      final authorized = await ManagerOverrideDialog.requestOverride(
        context,
        widget.db,
        'Void / Clear Active Cart',
      );
      if (!authorized) return;
    }
    if (!mounted) return;
    setState(() {
      _cart.clear();
      _overallDiscount = 0.0;
      _discountType = 'none';
      _discountLabel = 'Discount';
      _rebuildCartQuantities();
    });
  }

  void _holdCart() {
    if (_cart.isEmpty) return;
    if (!PermissionService.instance.hasPermission(PosPermissions.posHoldCart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to park carts.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _heldCarts.add(List.from(_cart));
      _cart.clear();
      _overallDiscount = 0.0;
      _discountType = 'none';
      _rebuildCartQuantities();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cart parked (${_heldCarts.length} held). Ready for next customer.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Recall', onPressed: _recallHeldCart),
      ),
    );
  }

  void _recallHeldCart() {
    if (_heldCarts.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No held carts found.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      final recalled = _heldCarts.removeLast();
      _cart.clear();
      _cart.addAll(recalled);
      _rebuildCartQuantities();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Held cart restored with ${_cart.length} item(s).'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onBarcodeSubmitted(String query, List<Product> allProducts) {
    _searchDebounce?.cancel();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return;

    try {
      // Direct Barcode or SKU match
      final match = allProducts.firstWhere(
        (p) => (p.barcode?.toLowerCase() == q) || (p.sku?.toLowerCase() == q),
        orElse: () => allProducts.firstWhere(
          (p) => p.productName.toLowerCase() == q,
          orElse: () => allProducts.firstWhere(
            (p) => p.productName.toLowerCase().contains(q),
            orElse: () => throw Exception('Not found'),
          ),
        ),
      );

      _searchController.clear();
      setState(() => _searchQuery = '');
      _onProductTapped(match);
    } catch (_) {
      // Unknown barcode — show friendly message, do NOT crash
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No product found for: "$query"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _searchController.clear();
      setState(() => _searchQuery = '');
    }
  }

  void _openCustomerSelectionDialog() {
    final customersStream = (widget.db.select(
      widget.db.customers,
    )..where((c) => c.isDeleted.equals(false))).watch();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: 600,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.person_add_alt_1_rounded,
                              color: AppTheme.accentColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customer Selection',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                Text(
                                  'Attach customer for loyalty & credit account',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Register New Customer Action Button (Gated by customersAdd permission)
                      if (PermissionService.instance.hasPermission(
                        PosPermissions.customersAdd,
                      )) ...[
                        ElevatedButton.icon(
                          key: const Key(
                            'cashier_register_new_customer_button',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text(
                            'Register New Customer',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () async {
                            final navigator = Navigator.of(dialogCtx);
                            final newCustomer = await showDialog<Customer?>(
                              context: context,
                              builder: (ctx) =>
                                  AddCustomerDialog(db: widget.db),
                            );
                            if (newCustomer != null) {
                              setState(() => _selectedCustomer = newCustomer);
                              if (mounted && navigator.canPop()) {
                                navigator.pop();
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Search Box
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.cardBorderColor),
                        ),
                        child: TextField(
                          key: const Key('cashier_customer_search_input'),
                          onChanged: (val) =>
                              setDialogState(() => query = val.toLowerCase()),
                          decoration: const InputDecoration(
                            hintText: 'Search customer name or phone...',
                            hintStyle: TextStyle(fontSize: 12),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: Colors.grey,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Customer List Stream
                      Expanded(
                        child: StreamBuilder<List<Customer>>(
                          stream: customersStream,
                          builder: (context, snapshot) {
                            final list = (snapshot.data ?? [])
                              ..sort(
                                (a, b) => a.fullName.compareTo(b.fullName),
                              );
                            final filtered = list.where((c) {
                              if (query.isEmpty) return true;
                              return c.fullName.toLowerCase().contains(query) ||
                                  (c.phone?.toLowerCase().contains(query) ??
                                      false);
                            }).toList();

                            if (filtered.isEmpty) {
                              return Center(
                                child: Text(
                                  query.isEmpty
                                      ? 'No registered customers yet.\nClick "Register New Customer" above!'
                                      : 'No customer matching "$query"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, i) => const Divider(
                                height: 1,
                                color: AppTheme.cardBorderColor,
                              ),
                              itemBuilder: (ctx, idx) {
                                final customer = filtered[idx];
                                final isChosen =
                                    _selectedCustomer?.id == customer.id;

                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppTheme.accentColor
                                        .withValues(alpha: 0.12),
                                    child: Text(
                                      customer.fullName.isNotEmpty
                                          ? customer.fullName[0].toUpperCase()
                                          : 'C',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accentColor,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          customer.loyaltyTier,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${customer.phone ?? 'No phone'} • ${customer.pointsBalance.toStringAsFixed(0)} pts',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: isChosen
                                      ? const Icon(
                                          Icons.check_circle_rounded,
                                          color: AppTheme.inStockColor,
                                          size: 20,
                                        )
                                      : OutlinedButton(
                                          key: Key(
                                            'select_customer_${customer.id}',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 2,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          onPressed: () {
                                            setState(
                                              () =>
                                                  _selectedCustomer = customer,
                                            );
                                            Navigator.pop(dialogCtx);
                                          },
                                          child: const Text(
                                            'Select',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      if (_selectedCustomer != null) ...[
                        const Divider(
                          height: 16,
                          color: AppTheme.cardBorderColor,
                        ),
                        TextButton.icon(
                          key: const Key('cashier_remove_customer_button'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          icon: const Icon(
                            Icons.person_remove_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Remove Customer from Active Sale',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            setState(() => _selectedCustomer = null);
                            Navigator.pop(dialogCtx);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // Price Override
  // ==========================================
  Future<void> _openPriceOverride(int index) async {
    final item = _cart[index];
    final hasPerm = PermissionService.instance.hasPermission(
      PosPermissions.posPriceOverride,
    );
    if (!hasPerm) {
      final authorized = await ManagerOverrideDialog.requestOverride(
        context,
        widget.db,
        'Price Override: ${item.product.productName}',
      );
      if (!authorized) return;
    }
    if (!mounted) return;

    final newPrice = await showDialog<double>(
      context: context,
      builder: (ctx) => PriceOverrideDialog(
        productName: item.product.productName,
        currentPrice: item.unitPrice,
      ),
    );
    if (newPrice != null && newPrice > 0) {
      setState(() {
        _cart[index].unitPrice = newPrice;
      });
    }
  }

  // ==========================================
  // Quick Quantity Direct Input
  // ==========================================
  Future<void> _openQuantityInput(int index) async {
    final item = _cart[index];
    final newQty = await showDialog<double>(
      context: context,
      builder: (ctx) => QuantityInputDialog(
        productName: item.product.productName,
        currentQuantity: item.quantity,
        isDecimal: item.isFractional,
        unit: item.product.unit,
      ),
    );
    if (newQty != null && newQty > 0) {
      setState(() {
        _cart[index].quantity = newQty;
        _rebuildCartQuantities();
      });
    }
  }

  // ==========================================
  // Custom Discount (% or ₱ fixed) — replaces preset-only toggle
  // ==========================================
  Future<void> _openDiscountDialog({VoidCallback? onMutate}) async {
    final hasPresetPerm = PermissionService.instance.hasPermission(
      PosPermissions.posDiscountPreset,
    );
    final hasCustomPerm = PermissionService.instance.hasPermission(
      PosPermissions.posDiscountCustom,
    );

    // If no discount perms at all, require manager override
    if (!hasPresetPerm && !hasCustomPerm && _discountType == 'none') {
      final authorized = await ManagerOverrideDialog.requestOverride(
        context,
        widget.db,
        'Apply Discount',
      );
      if (!authorized) return;
    }
    if (!mounted) return;

    // Toggle off if already discounted
    if (_discountType != 'none') {
      setState(() {
        _discountType = 'none';
        _overallDiscount = 0.0;
        _discountLabel = 'Discount';
      });
      onMutate?.call();
      return;
    }

    final result = await showDialog<CustomDiscountResult>(
      context: context,
      builder: (ctx) => CustomDiscountDialog(
        cartSubtotal: _cartSubtotal,
        hasSeniorPwdPreset: hasPresetPerm,
      ),
    );

    if (result != null && mounted) {
      if (result.type == 'percent' &&
          result.inputValue == DevicePrefs.seniorPwdDiscountPercent) {
        // Senior/PWD preset
        setState(() {
          _discountType = 'pwd_senior_20';
          _overallDiscount = 0.0;
          _discountLabel =
              'Senior/PWD (${DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0)}%)';
        });
      } else {
        // Custom discount — check posDiscountCustom
        if (!hasCustomPerm) {
          final authorized = await ManagerOverrideDialog.requestOverride(
            context,
            widget.db,
            'Apply Custom Discount',
          );
          if (!authorized || !mounted) return;
        }
        setState(() {
          _discountType = 'custom';
          _overallDiscount = result.amount;
          _discountLabel = result.type == 'percent'
              ? 'Discount (${result.inputValue.toStringAsFixed(0)}%)'
              : 'Discount (₱${result.inputValue.toStringAsFixed(2)})';
        });
      }
      onMutate?.call();
    }
  }

  // ==========================================
  // Cash Drawer Adjustment (Pay In / Pay Out)
  // ==========================================
  Future<void> _openCashAdjustment(String type) async {
    final result = await showDialog<CashAdjustmentResult>(
      context: context,
      builder: (ctx) => CashAdjustmentDialog(initialType: type),
    );
    if (result != null && mounted) {
      final isIn = result.type == 'pay_in';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isIn ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${isIn ? 'Pay In' : 'Pay Out'}: ₱${result.amount.toStringAsFixed(2)} — ${result.reason}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: isIn ? Colors.green.shade700 : Colors.red.shade700,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // TODO: persist to cash_adjustments table in next iteration
    }
  }

  void _openCheckoutModal([String? shiftId]) {
    if (_cart.isEmpty) return;
    if (!PermissionService.instance.hasPermission(PosPermissions.posSell)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to process checkouts.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).clearSnackBars();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CheckoutDialog(
        db: widget.db,
        items: _cart,
        subtotal: _cartSubtotal,
        discountTotal: _cartDiscountTotal,
        taxTotal: _cartTaxTotal,
        grandTotal: _cartGrandTotal,
        shiftId: shiftId,
        customer: _selectedCustomer,
        onSaleCompleted: () {
          // Force-clear the cart directly after successful payment.
          // We bypass the permission-gated _clearCart() because the sale
          // is already finalized — the cashier does not need posVoidCart here.
          setState(() {
            _cart.clear();
            _overallDiscount = 0.0;
            _discountType = 'none';
            _discountLabel = 'Discount';
            _selectedCustomer = null;
            _rebuildCartQuantities();
          });
        },
      ),
    );
  }

  void _openMobileCartSheet(BuildContext context, String? shiftId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            void mutate() {
              setState(() {});
              setSheetState(() {});
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  _buildCartHeader(onMutate: mutate),
                  Expanded(child: _buildCartItemList(onMutate: mutate)),
                  _buildCartSummary(
                    shiftId: shiftId,
                    onCheckoutTriggered: () {
                      Navigator.of(modalCtx).pop();
                      _openCheckoutModal(shiftId);
                    },
                    onMutate: mutate,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CashManagement?>(
      stream: _activeShiftStream,
      builder: (context, shiftSnapshot) {
        final activeShift = shiftSnapshot.data;

        return StreamBuilder<List<ProductType>>(
          stream: _categoriesStream,
          builder: (context, catSnapshot) {
            final categories = catSnapshot.data ?? [];

            return StreamBuilder<List<Product>>(
              stream: _productsStream,
              builder: (context, prodSnapshot) {
                final allProducts = prodSnapshot.data ?? [];

                // Filter products
                final filteredProducts = allProducts.where((p) {
                  final matchesCat =
                      _selectedCategoryId == 'all' ||
                      p.productTypeId == _selectedCategoryId;
                  final q = _searchQuery.toLowerCase();
                  final matchesSearch =
                      q.isEmpty ||
                      p.productName.toLowerCase().contains(q) ||
                      (p.variantName?.toLowerCase().contains(q) ?? false) ||
                      (p.sku?.toLowerCase().contains(q) ?? false) ||
                      (p.barcode?.toLowerCase().contains(q) ?? false);
                  return matchesCat && matchesSearch;
                }).toList();

                final groupedProducts = _getGroupedProducts(filteredProducts);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isTablet = constraints.maxWidth >= 720;
                    if (isTablet) {
                      return _buildTabletLayout(
                        categories,
                        groupedProducts,
                        allProducts,
                        activeShift,
                      );
                    } else {
                      return _buildMobileLayout(
                        categories,
                        groupedProducts,
                        allProducts,
                        activeShift,
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // Tablet Split Layout (Catalog 60% + Cart 40%)
  // ==========================================
  Widget _buildTabletLayout(
    List<ProductType> categories,
    List<GroupedPosProduct> products,
    List<Product> allProducts,
    CashManagement? activeShift,
  ) {
    return Container(
      color: AppTheme.backgroundColor,
      child: Row(
        children: [
          // Left Pane: Catalog & Fast Entry (Flex 3)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildTopHeader(allProducts, activeShift),
                _buildCategorySelector(categories),
                Expanded(child: _buildProductGrid(products, crossAxisCount: 3)),
              ],
            ),
          ),
          // Divider
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppTheme.cardBorderColor,
          ),
          // Right Pane: Active Cart Invoice (Flex 2)
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildCartHeader(),
                  Expanded(child: _buildCartItemList()),
                  _buildCartSummary(shiftId: activeShift?.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Mobile Layout (Full Catalog + Bottom Bar)
  // ==========================================
  Widget _buildMobileLayout(
    List<ProductType> categories,
    List<GroupedPosProduct> products,
    List<Product> allProducts,
    CashManagement? activeShift,
  ) {
    return Container(
      color: AppTheme.backgroundColor,
      child: Column(
        children: [
          _buildTopHeader(allProducts, activeShift),
          _buildCategorySelector(categories),
          Expanded(child: _buildProductGrid(products, crossAxisCount: 2)),
          _buildMobileStickyCartBar(activeShift?.id),
        ],
      ),
    );
  }

  // ==========================================
  // Top Header (Shift & Barcode/Search Bar)
  // ==========================================
  Widget _buildTopHeader(
    List<Product> allProducts,
    CashManagement? activeShift,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.white,
      child: Column(
        children: [
          // Shift and Register Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: activeShift != null
                        ? AppTheme.inStockBg
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    activeShift != null
                        ? Icons.storefront_rounded
                        : Icons.lock_outline_rounded,
                    color: activeShift != null
                        ? AppTheme.inStockColor
                        : Colors.amber.shade900,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final regId = DevicePrefs.registerId;
                      String regLabel;
                      if (regId == null || regId == 'default-reg-001') {
                        regLabel = 'Register #1';
                      } else if (regId.startsWith('default-reg-')) {
                        final suffix = regId.replaceFirst('default-reg-', '');
                        final num = int.tryParse(suffix);
                        regLabel = 'Register #${num ?? suffix}';
                      } else {
                        regLabel =
                            'Register #${regId.length > 4 ? regId.substring(0, 4) : regId}';
                      }
                      return Text(
                        activeShift != null
                            ? '$regLabel • Shift Active (Float: ₱${activeShift.openingBalance.toStringAsFixed(0)})'
                            : '$regLabel • Shift Closed',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: activeShift != null
                              ? AppTheme.primaryColor
                              : Colors.amber.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                SyncStatusBadge(db: widget.db),
                if (activeShift != null) ...[
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      key: const Key('shift_cash_adjustments_menu'),
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 17,
                        color: AppTheme.primaryColor,
                      ),
                      tooltip: 'Cash Drawer Adjustments',
                      padding: EdgeInsets.zero,
                      onSelected: (val) {
                        if (val == 'pay_in') _openCashAdjustment('pay_in');
                        if (val == 'pay_out') _openCashAdjustment('pay_out');
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'pay_in',
                          child: Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline_rounded,
                                color: Colors.green,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Cash In / Pay In',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'pay_out',
                          child: Row(
                            children: [
                              Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Cash Out / Pay Out',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('close_shift_button'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 13),
                    label: const Text(
                      'Close Shift',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _openCloseShiftModal(activeShift),
                  ),
                ] else ...[
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    key: const Key('open_shift_button'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 13),
                    label: const Text(
                      'Open Shift',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _openOpenShiftModal,
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              // Button icon on cashier left side of the header to add a customer
              Material(
                color: _selectedCustomer != null
                    ? AppTheme.accentColor.withValues(alpha: 0.12)
                    : AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: const Key('cashier_add_customer_button'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: _openCustomerSelectionDialog,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedCustomer != null
                            ? AppTheme.accentColor
                            : AppTheme.cardBorderColor,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedCustomer != null
                              ? Icons.person_rounded
                              : Icons.person_add_alt_1_rounded,
                          color: _selectedCustomer != null
                              ? AppTheme.accentColor
                              : AppTheme.primaryColor,
                          size: 20,
                        ),
                        if (_selectedCustomer != null) ...[
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 85),
                            child: Text(
                              _selectedCustomer!.fullName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            key: const Key('clear_customer_button'),
                            onTap: () =>
                                setState(() => _selectedCustomer = null),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Barcode & Search Input
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorderColor),
                  ),
                  child: TextField(
                    key: const Key('counter_barcode_search_input'),
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: (val) => _onBarcodeSubmitted(val, allProducts),
                    decoration: InputDecoration(
                      hintText: 'Scan Barcode or Search Items...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppTheme.accentColor,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Park / Hold Cart Button
              Stack(
                clipBehavior: Clip.none,
                children: [
                  OutlinedButton.icon(
                    key: const Key('hold_cart_button'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(
                      Icons.pause_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text(
                      'Hold',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _cart.isNotEmpty
                        ? _holdCart
                        : (_heldCarts.isNotEmpty ? _recallHeldCart : null),
                  ),
                  if (_heldCarts.isNotEmpty)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_heldCarts.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),

              // Dedicated Cart Button (always visible on phone & tablet!)
              FilledButton.icon(
                key: const Key('counter_cart_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: _cart.isNotEmpty
                      ? AppTheme.accentColor
                      : AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: Text(
                  'Cart (${_cart.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _openMobileCartSheet(context, activeShift?.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Category Horizontal Selector
  // ==========================================
  Widget _buildCategorySelector(List<ProductType> categories) {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final catId = isAll ? 'all' : categories[index - 1].id;
          final label = isAll ? 'All Items' : categories[index - 1].typeName;
          final isSelected = _selectedCategoryId == catId;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key('category_filter_$catId'),
              selected: isSelected,
              label: Text(label),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black87,
              ),
              backgroundColor: Colors.white,
              selectedColor: AppTheme.accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.accentColor
                      : AppTheme.cardBorderColor,
                ),
              ),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (selected) {
                if (selected) setState(() => _selectedCategoryId = catId);
              },
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // Product Catalog Grid (Tactile POS Cards)
  // ==========================================
  Widget _buildProductGrid(
    List<GroupedPosProduct> products, {
    required int crossAxisCount,
  }) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 10),
            Text(
              'No matching products found',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final groupedProduct = products[index];
        final isMulti = groupedProduct.isMultiVariant;
        final primary = groupedProduct.primaryProduct;
        final isFraction = groupedProduct.sellBy == 'fraction';

        double totalCartQty = 0.0;
        for (final v in groupedProduct.variants) {
          final q = _cartItemQuantities[v.id];
          if (q != null) totalCartQty += q;
        }
        final inCart = totalCartQty > 0;

        return RepaintBoundary(
          child: Material(
            color: inCart
                ? AppTheme.accentColor.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: Key('counter_product_card_${primary.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onGroupedProductTapped(groupedProduct),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: inCart
                        ? AppTheme.accentColor
                        : AppTheme.cardBorderColor,
                    width: inCart ? 2.0 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top badge & In-Cart Quantity Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (isMulti)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.shade400,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '${groupedProduct.variants.length} SIZES',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isFraction
                                  ? AppTheme.accentColor.withValues(alpha: 0.12)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isFraction ? 'WEIGHED' : 'UNIT',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: isFraction
                                    ? AppTheme.accentColor
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        if (inCart)
                          Container(
                            key: Key('product_cart_badge_${primary.id}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isFraction
                                  ? '${totalCartQty.toStringAsFixed(1)}kg'
                                  : 'x${totalCartQty.toInt()}',
                              style: const TextStyle(
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 13,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                      ],
                    ),
                    if (primary.imagePath != null ||
                        primary.imageUrl != null) ...[
                      const SizedBox(height: 4),
                      Expanded(
                        child: Center(
                          child: ProductThumbnail(
                            imagePath: primary.imagePath,
                            imageUrl: primary.imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ] else ...[
                      const Spacer(),
                    ],

                    // Name & Variant
                    Text(
                      groupedProduct.productName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: inCart
                            ? AppTheme.accentColor
                            : AppTheme.primaryColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isMulti) ...[
                      const SizedBox(height: 2),
                      Text(
                        groupedProduct.variants
                            .map(
                              (v) =>
                                  (v.variantName != null &&
                                      v.variantName!.isNotEmpty)
                                  ? v.variantName!
                                  : 'Std',
                            )
                            .join(', '),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        groupedProduct.minPrice == groupedProduct.maxPrice
                            ? '₱${groupedProduct.minPrice.toStringAsFixed(2)} / ${groupedProduct.unit}'
                            : 'From ₱${groupedProduct.minPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ] else ...[
                      if (primary.variantName != null &&
                          primary.variantName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          primary.variantName!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '₱${primary.price.toStringAsFixed(2)} / ${primary.unit}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // Cart Components (Tablet Right Pane & Drawer)
  // ==========================================
  Widget _buildCartHeader({VoidCallback? onMutate}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Current Sale (${_cart.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_cart.isNotEmpty)
            TextButton.icon(
              key: const Key('clear_cart_button'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.outOfStockColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
              onPressed: () {
                _clearCart();
                onMutate?.call();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCartItemList({VoidCallback? onMutate}) {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 10),
            Text(
              'Cart is empty',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan a barcode or tap products on the catalog',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _cart.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 12, color: AppTheme.cardBorderColor),
      itemBuilder: (context, index) {
        final item = _cart[index];
        final step = item.isFractional ? 0.250 : 1.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Product details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.productName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.product.variantName != null &&
                        item.product.variantName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1, bottom: 1),
                        child: Text(
                          item.product.variantName!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 2),
                    InkWell(
                      key: Key('price_override_tap_$index'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        await _openPriceOverride(index);
                        onMutate?.call();
                      },
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '₱${item.unitPrice.toStringAsFixed(2)} / ${item.product.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              color: item.unitPrice != item.product.price
                                  ? AppTheme.accentColor
                                  : Colors.grey.shade600,
                              fontWeight: item.unitPrice != item.product.price
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (item.unitPrice != item.product.price) ...[
                            const SizedBox(width: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'EDITED',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Quantity Stepper with Direct Tappable Input
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('stepper_minus_$index'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 20,
                    ),
                    onPressed: () {
                      _updateQuantity(index, -step);
                      onMutate?.call();
                    },
                  ),
                  InkWell(
                    key: Key('qty_display_$index'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      await _openQuantityInput(index);
                      onMutate?.call();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.cardBorderColor),
                      ),
                      child: Text(
                        item.isFractional
                            ? '${item.quantity.toStringAsFixed(3)} kg'
                            : '${item.quantity.toInt()} pcs',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('stepper_plus_$index'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 20,
                      color: AppTheme.accentColor,
                    ),
                    onPressed: () {
                      _updateQuantity(index, step);
                      onMutate?.call();
                    },
                  ),
                ],
              ),

              // Line total
              SizedBox(
                width: 70,
                child: Text(
                  '₱${item.rawTotal.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Delete button
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16, color: Colors.black38),
                onPressed: () {
                  _removeFromCart(index);
                  onMutate?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCartSummary({
    String? shiftId,
    VoidCallback? onCheckoutTriggered,
    VoidCallback? onMutate,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Subtotal
          _buildSummaryRow('Subtotal', '₱${_cartSubtotal.toStringAsFixed(2)}'),
          if (_cartDiscountTotal > 0)
            _buildSummaryRow(
              _discountType == 'pwd_senior_20'
                  ? 'Discount (Senior/PWD)'
                  : _discountLabel,
              '-₱${_cartDiscountTotal.toStringAsFixed(2)}',
              isDiscount: true,
            ),
          if (_cartTaxTotal > 0)
            _buildSummaryRow(
              'VAT / Tax',
              '+₱${_cartTaxTotal.toStringAsFixed(2)}',
            ),
          const Divider(height: 14),

          // Grand Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Due',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₱${_cartGrandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Discount Selector & Checkout Action Row
          Row(
            children: [
              // Discount button: Quick tap for Senior/PWD, Long press for custom discount
              Tooltip(
                message: _discountType != 'none'
                    ? 'Remove: $_discountLabel'
                    : 'Tap: Senior/PWD (${DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0)}%) | Hold: Custom discount',
                child: IconButton.outlined(
                  key: const Key('discount_toggle_button'),
                  icon: Icon(
                    _discountType != 'none'
                        ? Icons.discount_rounded
                        : Icons.discount_outlined,
                    color: _discountType != 'none'
                        ? AppTheme.accentColor
                        : Colors.black54,
                    size: 20,
                  ),
                  onPressed: () async {
                    if (_discountType != 'none') {
                      setState(() {
                        _discountType = 'none';
                        _overallDiscount = 0.0;
                        _discountLabel = 'Discount';
                      });
                      onMutate?.call();
                      return;
                    }
                    final hasPresetPerm = PermissionService.instance
                        .hasPermission(PosPermissions.posDiscountPreset);
                    if (!hasPresetPerm) {
                      final authorized =
                          await ManagerOverrideDialog.requestOverride(
                            context,
                            widget.db,
                            'Authorize ${DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0)}% Senior/PWD Discount',
                          );
                      if (!authorized || !mounted) return;
                    }
                    setState(() {
                      _discountType = 'pwd_senior_20';
                      _overallDiscount = 0.0;
                      _discountLabel = 'Discount (Senior/PWD)';
                    });
                    onMutate?.call();
                  },
                  onLongPress: () => _openDiscountDialog(onMutate: onMutate),
                ),
              ),
              const SizedBox(width: 8),

              // Charge Button (strictly guarded by posSell permission)
              if (PermissionService.instance.hasPermission(
                PosPermissions.posSell,
              ))
                Expanded(
                  child: ElevatedButton(
                    key: const Key('charge_checkout_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _cart.isNotEmpty
                        ? () {
                            if (onCheckoutTriggered != null) {
                              onCheckoutTriggered();
                            } else {
                              _openCheckoutModal(shiftId);
                            }
                          }
                        : null,
                    child: Text(
                      'Charge ₱${_cartGrandTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    key: const Key('checkout_restricted_notice'),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.cardBorderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Checkout Restricted',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
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
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isDiscount = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDiscount ? AppTheme.inStockColor : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Mobile Sticky Bottom Cart Bar & Drawer
  // ==========================================
  Widget _buildMobileStickyCartBar(String? shiftId) {
    final hasItems = _cart.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Cart badge & total - tapping opens cart sheet!
            Expanded(
              child: InkWell(
                key: const Key('mobile_cart_bar_info'),
                onTap: () => _openMobileCartSheet(context, shiftId),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 14,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hasItems
                                  ? '${_cart.length} item(s)'
                                  : 'Cart empty',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: AppTheme.accentColor,
                          ),
                        ],
                      ),
                      Text(
                        '₱${_cartGrandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Checkout or View Cart Action
            if (hasItems &&
                PermissionService.instance.hasPermission(
                  PosPermissions.posSell,
                ))
              ElevatedButton(
                key: const Key('mobile_checkout_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _openCheckoutModal(shiftId),
                child: const Text(
                  'Checkout',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('mobile_view_empty_cart_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                label: const Text(
                  'View Cart',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openMobileCartSheet(context, shiftId),
              ),
          ],
        ),
      ),
    );
  }
}
