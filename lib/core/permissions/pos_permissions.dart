import 'package:flutter/material.dart';

/// Single source of truth for all granular permission keys across the POS system.
class PosPermissions {
  // --- Module 1: Point of Sale (Counter) ---
  static const String posView = 'pos.view';
  static const String posSell = 'pos.sell';
  static const String posDiscountPreset = 'pos.discount_preset';
  static const String posDiscountCustom = 'pos.discount_custom';
  static const String posVoidCart = 'pos.void_cart';
  static const String posHoldCart = 'pos.hold_cart';
  static const String posPriceOverride = 'pos.price_override';
  static const String posShiftOpen = 'pos.shift.open';
  static const String posShiftClose = 'pos.shift.close';
  static const String posShiftBlindClose = 'pos.shift.blind_close';

  // --- Module 2: Inventory ---
  static const String inventoryView = 'inventory.view';
  static const String inventoryAdd = 'inventory.add';
  static const String inventoryEdit = 'inventory.edit';
  static const String inventoryAdjustStock = 'inventory.adjust_stock';
  static const String inventoryDelete = 'inventory.delete';
  static const String inventoryCategories = 'inventory.categories';

  // --- Module 3: Customers ---
  static const String customersView = 'customers.view';
  static const String customersAdd = 'customers.add';
  static const String customersEdit = 'customers.edit';
  static const String customersCreditCharge = 'customers.credit_charge';
  static const String customersCreditSettle = 'customers.credit_settle';
  static const String customersDelete = 'customers.delete';

  // --- Module 4: Transactions ---
  static const String transactionsViewOwn = 'transactions.view_own';
  static const String transactionsViewAll = 'transactions.view_all';
  static const String transactionsReceipt = 'transactions.receipt';
  static const String transactionsRefund = 'transactions.refund';
  static const String transactionsExport = 'transactions.export';

  // --- Module 5: Reports ---
  static const String reportsView = 'reports.view';
  static const String reportsPlFinancials = 'reports.pl_financials';
  static const String reportsExpenses = 'reports.expenses';
  static const String reportsStaffAudit = 'reports.staff_audit';
  static const String reportsExport = 'reports.export';

  // --- Module 6: Stores ---
  static const String storesView = 'stores.view';
  static const String storesManage = 'stores.manage';
  static const String storesSwitch = 'stores.switch';

  // --- Module 7: Staff ---
  static const String staffView = 'staff.view';
  static const String staffManage = 'staff.manage';
  static const String staffPermissions = 'staff.permissions';
  static const String staffResetPin = 'staff.reset_pin';

  // --- Module 8: Settings ---
  static const String settingsView = 'settings.view';
  static const String settingsCompanyProfile = 'settings.company_profile';
  static const String settingsSecurityPolicy = 'settings.security_policy';
  static const String settingsDiscounts = 'settings.discounts';
  static const String settingsSyncRepair = 'settings.sync_repair';

  /// Predefined default roles
  static const String roleAdmin = 'Admin';
  static const String roleManager = 'Store Manager';
  static const String roleCashier = 'Cashier';
  static const String roleInventory = 'Inventory Specialist';

  /// Standard list of system built-in roles
  static const List<String> systemRoles = [
    roleAdmin,
    roleManager,
    roleCashier,
    roleInventory,
  ];

  /// All registered modules metadata
  static const List<PosModuleInfo> modules = [
    PosModuleInfo(
      id: 'pos',
      title: 'Point of Sale & Register',
      icon: Icons.point_of_sale_rounded,
      description: 'Counter checkout, orders, discounts, shifts, and cash drawer balancing.',
    ),
    PosModuleInfo(
      id: 'inventory',
      title: 'Inventory Management',
      icon: Icons.inventory_2_rounded,
      description: 'Product catalog, stock adjustments, supplier costs, and categories.',
    ),
    PosModuleInfo(
      id: 'customers',
      title: 'Customers & Credit Accounts',
      icon: Icons.people_alt_rounded,
      description: 'Customer profiles, loyalty points, receivables, and credit settlements.',
    ),
    PosModuleInfo(
      id: 'transactions',
      title: 'Sales & Receipts',
      icon: Icons.receipt_long_rounded,
      description: 'Order history, transaction audit, receipt reprinting, and refunds.',
    ),
    PosModuleInfo(
      id: 'reports',
      title: 'Reports & Analytics',
      icon: Icons.bar_chart_rounded,
      description: 'Profit & loss, sales rankings, expense tracking, and spreadsheet export.',
    ),
    PosModuleInfo(
      id: 'stores',
      title: 'Stores & Terminals',
      icon: Icons.store_mall_directory_rounded,
      description: 'Branch profiles, POS registers, and terminal switching.',
    ),
    PosModuleInfo(
      id: 'staff',
      title: 'Staff & Cashiers',
      icon: Icons.badge_rounded,
      description: 'Employee directory, PIN codes, role templates, and permission matrix.',
    ),
    PosModuleInfo(
      id: 'settings',
      title: 'System Settings',
      icon: Icons.settings_rounded,
      description: 'Company profile, security timeouts, and database sync diagnostics.',
    ),
  ];

  /// Complete list of granular permissions
  static const List<PosPermissionItem> allPermissions = [
    // POS
    PosPermissionItem(
      key: posView,
      title: 'Access Counter Screen',
      description: 'Open the register interface, catalog grid, and search items.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posSell,
      title: 'Process Checkout',
      description: 'Complete sales and accept Cash, GCash, Maya, or Card tenders.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posDiscountPreset,
      title: 'Apply Preset Discounts',
      description: 'Apply statutory Senior Citizen and PWD 20% discounts.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posDiscountCustom,
      title: 'Apply Custom Discounts',
      description: 'Apply custom cash or percentage discounts to cart totals.',
      moduleId: 'pos',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: posVoidCart,
      title: 'Clear / Void Cart',
      description: 'Empty an active shopping cart with existing items.',
      moduleId: 'pos',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: posHoldCart,
      title: 'Hold & Recall Orders',
      description: 'Park pending transactions and recall held carts.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posPriceOverride,
      title: 'Price Override',
      description: 'Manually edit the unit selling price of an item during checkout.',
      moduleId: 'pos',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: posShiftOpen,
      title: 'Open Shift',
      description: 'Start register shift and record beginning cash float.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posShiftClose,
      title: 'Close Shift',
      description: 'Submit cash drawer drop and finalize register shift.',
      moduleId: 'pos',
    ),
    PosPermissionItem(
      key: posShiftBlindClose,
      title: 'Blind Drawer Balancing',
      description: 'Hide expected drawer total during shift close to prevent theft.',
      moduleId: 'pos',
    ),

    // INVENTORY
    PosPermissionItem(
      key: inventoryView,
      title: 'View Inventory',
      description: 'View catalog products, current stock levels, and selling prices.',
      moduleId: 'inventory',
    ),
    PosPermissionItem(
      key: inventoryAdd,
      title: 'Add Products',
      description: 'Create new catalog products, barcodes, and variants.',
      moduleId: 'inventory',
    ),
    PosPermissionItem(
      key: inventoryEdit,
      title: 'Edit Products',
      description: 'Modify product names, categories, barcodes, and selling prices.',
      moduleId: 'inventory',
    ),
    PosPermissionItem(
      key: inventoryAdjustStock,
      title: 'Adjust Stock',
      description: 'Record stock in, damaged goods, waste write-offs, and audits.',
      moduleId: 'inventory',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: inventoryDelete,
      title: 'Delete Products',
      description: 'Deactivate or permanently remove products from the catalog.',
      moduleId: 'inventory',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: inventoryCategories,
      title: 'Manage Categories',
      description: 'Create, rename, pin, and organize product categories.',
      moduleId: 'inventory',
    ),

    // CUSTOMERS
    PosPermissionItem(
      key: customersView,
      title: 'View Customer Directory',
      description: 'View customer names, contact info, and loyalty point balances.',
      moduleId: 'customers',
    ),
    PosPermissionItem(
      key: customersAdd,
      title: 'Add Customers',
      description: 'Register new customer profiles at counter or in directory.',
      moduleId: 'customers',
    ),
    PosPermissionItem(
      key: customersEdit,
      title: 'Edit Customers',
      description: 'Update customer contact info, addresses, and credit limits.',
      moduleId: 'customers',
    ),
    PosPermissionItem(
      key: customersCreditCharge,
      title: 'Charge to Store Credit',
      description: 'Allow customers to charge purchases to receivable accounts.',
      moduleId: 'customers',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: customersCreditSettle,
      title: 'Settle Credit Balances',
      description: 'Receive payments against outstanding customer debts.',
      moduleId: 'customers',
    ),
    PosPermissionItem(
      key: customersDelete,
      title: 'Delete Customers',
      description: 'Archive or remove customer records from the system.',
      moduleId: 'customers',
      isSensitive: true,
    ),

    // TRANSACTIONS
    PosPermissionItem(
      key: transactionsViewOwn,
      title: 'View Own Sales History',
      description: 'View receipts processed by the currently logged-in staff member.',
      moduleId: 'transactions',
    ),
    PosPermissionItem(
      key: transactionsViewAll,
      title: 'View All Staff Sales',
      description: 'View transactions processed across all registers and staff.',
      moduleId: 'transactions',
    ),
    PosPermissionItem(
      key: transactionsReceipt,
      title: 'Reprint Receipts',
      description: 'Reprint physical receipts or share digital receipt copies.',
      moduleId: 'transactions',
    ),
    PosPermissionItem(
      key: transactionsRefund,
      title: 'Process Refunds',
      description: 'Process product returns and return cash from the drawer.',
      moduleId: 'transactions',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: transactionsExport,
      title: 'Export Sales Data',
      description: 'Export transaction receipts to Excel (.xlsx) and CSV.',
      moduleId: 'transactions',
    ),

    // REPORTS
    PosPermissionItem(
      key: reportsView,
      title: 'Access Reports Screen',
      description: 'View daily sales totals and business analytics overview.',
      moduleId: 'reports',
    ),
    PosPermissionItem(
      key: reportsPlFinancials,
      title: 'Financial Profit & Loss',
      description: 'View Net Profit, Gross Margins, and Cost of Goods Sold.',
      moduleId: 'reports',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: reportsExpenses,
      title: 'Manage Operating Expenses',
      description: 'Record, view, and delete daily store operating expenses.',
      moduleId: 'reports',
    ),
    PosPermissionItem(
      key: reportsStaffAudit,
      title: 'Staff Sales Rankings',
      description: 'View comparative sales performance and transaction counts per staff.',
      moduleId: 'reports',
    ),
    PosPermissionItem(
      key: reportsExport,
      title: 'Export Financial Reports',
      description: 'Download multi-sheet financial Excel files.',
      moduleId: 'reports',
      isSensitive: true,
    ),

    // STORES
    PosPermissionItem(
      key: storesView,
      title: 'View Stores & Terminals',
      description: 'View store locations, contact info, and active terminals.',
      moduleId: 'stores',
    ),
    PosPermissionItem(
      key: storesManage,
      title: 'Manage Store Branches',
      description: 'Create new branches and configure terminal hardware.',
      moduleId: 'stores',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: storesSwitch,
      title: 'Switch POS Terminal',
      description: 'Reassign this device to a different branch or register.',
      moduleId: 'stores',
    ),

    // STAFF
    PosPermissionItem(
      key: staffView,
      title: 'View Staff Directory',
      description: 'View employee accounts, job titles, and status.',
      moduleId: 'staff',
    ),
    PosPermissionItem(
      key: staffManage,
      title: 'Add & Edit Staff Accounts',
      description: 'Create employee logins, change passwords, and update profiles.',
      moduleId: 'staff',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: staffPermissions,
      title: 'Manage Roles & Permissions',
      description: 'Configure role permission matrices and individual overrides.',
      moduleId: 'staff',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: staffResetPin,
      title: 'Reset Employee PINs',
      description: 'Update quick-unlock PIN codes for employees.',
      moduleId: 'staff',
    ),

    // SETTINGS
    PosPermissionItem(
      key: settingsView,
      title: 'Access Settings Screen',
      description: 'View system configuration and device settings.',
      moduleId: 'settings',
    ),
    PosPermissionItem(
      key: settingsCompanyProfile,
      title: 'Edit Company Profile',
      description: 'Update business name, tax ID (TIN), address, and receipts info.',
      moduleId: 'settings',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: settingsSecurityPolicy,
      title: 'Security Policies',
      description: 'Toggle PIN requirements, auto-lock timeouts, and override rules.',
      moduleId: 'settings',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: settingsDiscounts,
      title: 'Discount & Promotion Rules',
      description: 'Configure Senior/PWD discount rates, max discount limits, and custom presets.',
      moduleId: 'settings',
      isSensitive: true,
    ),
    PosPermissionItem(
      key: settingsSyncRepair,
      title: 'Cloud Sync Diagnostics',
      description: 'Trigger manual cloud sync cycles and database repairs.',
      moduleId: 'settings',
    ),
  ];

  /// Default permission sets for built-in roles
  static Set<String> getDefaultPermissions(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'admin':
        // Superadmin has all permissions
        return allPermissions.map((p) => p.key).toSet();

      case 'store manager':
      case 'manager':
        return {
          // POS (all except price override)
          posView,
          posSell,
          posDiscountPreset,
          posDiscountCustom,
          posVoidCart,
          posHoldCart,
          posShiftOpen,
          posShiftClose,
          posShiftBlindClose,
          // Inventory (all except permanent delete)
          inventoryView,
          inventoryAdd,
          inventoryEdit,
          inventoryAdjustStock,
          inventoryCategories,
          // Customers (all except delete)
          customersView,
          customersAdd,
          customersEdit,
          customersCreditCharge,
          customersCreditSettle,
          // Transactions (all except export)
          transactionsViewOwn,
          transactionsViewAll,
          transactionsReceipt,
          transactionsRefund,
          // Reports (expenses and staff audit)
          reportsView,
          reportsExpenses,
          reportsStaffAudit,
          // Stores
          storesView,
          storesSwitch,
          // Staff
          staffView,
          staffManage,
          staffResetPin,
          // Settings
          settingsView,
          settingsSyncRepair,
        };

      case 'cashier':
        return {
          // POS
          posView,
          posSell,
          posDiscountPreset,
          posHoldCart,
          posShiftOpen,
          posShiftClose,
          posShiftBlindClose,
          // Customers
          customersView,
          customersAdd,
          // Transactions
          transactionsViewOwn,
          transactionsReceipt,
        };

      case 'inventory specialist':
      case 'inventory':
        return {
          inventoryView,
          inventoryAdd,
          inventoryEdit,
          inventoryAdjustStock,
          inventoryCategories,
          storesView,
        };

      default:
        // Cashier fallback
        return {
          posView,
          posSell,
          posDiscountPreset,
          posHoldCart,
          transactionsViewOwn,
          transactionsReceipt,
        };
    }
  }
}

/// Metadata for a module
class PosModuleInfo {
  final String id;
  final String title;
  final IconData icon;
  final String description;

  const PosModuleInfo({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
  });
}

/// Metadata for a single granular permission
class PosPermissionItem {
  final String key;
  final String title;
  final String description;
  final String moduleId;
  final bool isSensitive;

  const PosPermissionItem({
    required this.key,
    required this.title,
    required this.description,
    required this.moduleId,
    this.isSensitive = false,
  });
}
