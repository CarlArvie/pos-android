import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../data/local/database.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/pos_bottom_nav_bar.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/customers/add_customer_dialog.dart';
import 'inventory_screen.dart';
import 'customers_view.dart';
import 'counter_view.dart';
import 'transactions_view.dart';
import 'reports_view.dart';
import 'stores/stores_management_view.dart';
import 'staff/staff_management_view.dart';
import 'settings/settings_view.dart';
import '../widgets/auth/auth_guard.dart';
import '../../core/permissions/pos_permissions.dart';
import '../../core/permissions/permission_service.dart';

class MainShellScreen extends StatefulWidget {
  final AppDatabase database;
  final int initialIndex;

  const MainShellScreen({
    super.key,
    required this.database,
    this.initialIndex = 0,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Guard: ensure initial index is accessible by the current staff member
    if (!PermissionService.instance.canAccessTab(_currentIndex)) {
      _currentIndex = 2; // Default to Counter POS
    }
    PermissionService.instance.changeNotifier.addListener(_onPermissionsChanged);
  }

  @override
  void dispose() {
    PermissionService.instance.changeNotifier.removeListener(_onPermissionsChanged);
    super.dispose();
  }

  void _onPermissionsChanged() {
    if (mounted) {
      if (!PermissionService.instance.canAccessTab(_currentIndex)) {
        setState(() => _currentIndex = 2);
      } else {
        setState(() {});
      }
    }
  }

  void _onSelectTab(int index) {
    if (!PermissionService.instance.canAccessTab(index)) {
      final tabTitle = _getTitleForIndex(index);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: You do not have permission to access $tabTitle.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  void _showAddItemDialog() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.inventoryAdd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add products.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final categories = await (widget.database.select(widget.database.productTypes)
          ..orderBy([(t) => OrderingTerm.asc(t.typeName)]))
        .get();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProductDialog(
        db: widget.database,
        categories: categories,
      ),
    );
  }

  void _showAddCustomerDialog() {
    if (!PermissionService.instance.hasPermission(PosPermissions.customersAdd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to register customers.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddCustomerDialog(db: widget.database),
    );
  }

  String _getTitleForIndex(int idx) {
    switch (idx) {
      case 0:
        return 'Inventory Management';
      case 1:
        return 'Customer Directory';
      case 2:
        return 'Point of Sale';
      case 3:
        return 'Sales & Transactions';
      case 4:
        return 'Reports & Health';
      case 5:
        return 'Stores & Locations';
      case 6:
        return 'Staff & Cashiers';
      case 7:
        return 'System Settings';
      default:
        return 'Point of Sale';
    }
  }

  String _getTitle(bool isCompact) {
    if (isCompact && _currentIndex == 1) return 'Customers';
    switch (_currentIndex) {
      case 0:
        return 'Inventory Management';
      case 1:
        return 'Customer Directory';
      case 2:
        return 'Point of Sale';
      case 3:
        return 'Sales & Transactions';
      case 4:
        return 'Reports & Health';
      case 5:
        return 'Stores & Locations';
      case 6:
        return 'Staff & Cashiers';
      case 7:
        return 'System Settings';
      default:
        return 'POS System';
    }
  }

  String get _currentSubtitle {
    switch (_currentIndex) {
      case 0:
        return 'Manage products, categories, and stock limits';
      case 1:
        return 'Track loyalty points and store credit';
      case 2:
        return 'Speed checkout and cart operations';
      case 3:
        return 'View historical receipts and process refunds';
      case 4:
        return 'Business analytics and inventory valuation';
      case 5:
        return 'Manage branches and hardware registers';
      case 6:
        return 'Manage employee accounts and PIN codes';
      case 7:
        return 'Business profile and device configuration';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;

    return PopScope(
      canPop: false,
      child: AuthGuard(
        db: widget.database,
        featureName: 'POS System',
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.backgroundColor,
          drawer: AdminDrawer(
            db: widget.database,
            currentIndex: _currentIndex,
            onSelectTab: _onSelectTab,
          ),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, size: 26),
              tooltip: 'Navigation Menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getTitle(isCompact),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCompact || _currentIndex != 1)
                  Text(
                    _currentSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            actions: [
              if (_currentIndex == 0 &&
                  PermissionService.instance.hasPermission(PosPermissions.inventoryAdd))
                Padding(
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
                    onPressed: _showAddItemDialog,
                  ),
                ),
              if (_currentIndex == 1 &&
                  PermissionService.instance.hasPermission(PosPermissions.customersAdd))
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: ElevatedButton.icon(
                    key: const Key('header_add_customer_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth < 380 ? 10 : 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: Text(
                      screenWidth < 380 ? 'Add' : 'Add Customer',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _showAddCustomerDialog,
                  ),
                ),
            ],
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: [
              // 0: Inventory
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.inventoryView,
                featureName: 'Inventory Management',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: InventoryScreen(
                  db: widget.database,
                  showScaffold: false,
                ),
              ),

              // 1: Customer Management
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.customersView,
                featureName: 'Customer Directory',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: CustomersView(db: widget.database),
              ),

              // 2: POS Counter
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.posView,
                featureName: 'Point of Sale',
                child: CounterView(db: widget.database),
              ),

              // 3: Transactions
              AuthGuard(
                db: widget.database,
                anyOfPermissions: const [
                  PosPermissions.transactionsViewOwn,
                  PosPermissions.transactionsViewAll,
                ],
                featureName: 'Sales & Transactions',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: TransactionsView(db: widget.database),
              ),

              // 4: Reports
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.reportsView,
                featureName: 'Reports & Analytics',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: ReportsView(db: widget.database),
              ),

              // 5: Stores Management
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.storesView,
                featureName: 'Stores & Registers',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: StoresManagementView(db: widget.database),
              ),

              // 6: Staff Management
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.staffView,
                featureName: 'Staff & Cashiers',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: StaffManagementView(db: widget.database),
              ),

              // 7: Settings
              AuthGuard(
                db: widget.database,
                requiredPermission: PosPermissions.settingsView,
                featureName: 'System Settings',
                onReturnToTerminal: () => setState(() => _currentIndex = 2),
                child: SettingsView(db: widget.database),
              ),
            ],
          ),
          bottomNavigationBar: PosBottomNavBar(
            currentIndex: _currentIndex,
            onTabSelected: _onSelectTab,
            onMorePressed: () {
              _scaffoldKey.currentState?.openDrawer();
            },
          ),
        ),
      ),
    );
  }
}
