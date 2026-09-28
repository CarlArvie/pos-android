import 'package:flutter/material.dart';
import '../../data/local/database.dart';
import '../../data/local/daos/pos_dao.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../theme/app_theme.dart';
import '../widgets/customers/add_customer_dialog.dart';
import '../widgets/customers/settle_credit_dialog.dart';
import '../widgets/customers/customer_payment_history_dialog.dart';

class CustomersView extends StatefulWidget {
  final AppDatabase db;

  const CustomersView({super.key, required this.db});

  @override
  State<CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<CustomersView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTier = 'All';

  final List<String> _filterTiers = ['All', 'Bronze', 'Silver', 'Gold', 'Platinum'];

  @override
  void initState() {
    super.initState();
    PermissionService.instance.changeNotifier.addListener(_onPermissionsChanged);
  }

  void _onPermissionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PermissionService.instance.changeNotifier.removeListener(_onPermissionsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _openAddCustomerDialog([Customer? customer]) async {
    if (customer == null) {
      if (!PermissionService.instance.hasPermission(PosPermissions.customersAdd)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Denied: You do not have permission to add customers.')),
        );
        return;
      }
    } else {
      if (!PermissionService.instance.hasPermission(PosPermissions.customersEdit)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Denied: You do not have permission to edit customers.')),
        );
        return;
      }
    }
    await showDialog(
      context: context,
      builder: (ctx) => AddCustomerDialog(
        db: widget.db,
        customer: customer,
      ),
    );
  }

  void _openSettleCreditDialog(Customer customer) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.customersCreditSettle)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access Denied: You do not have permission to settle credit balances.')),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => SettleCreditDialog(
        db: widget.db,
        customer: customer,
      ),
    );
  }

  void _openPaymentHistoryDialog(Customer customer) async {
    await showDialog(
      context: context,
      builder: (ctx) => CustomerPaymentHistoryDialog(
        db: widget.db,
        customer: customer,
      ),
    );
  }

  void _confirmDeleteCustomer(Customer customer) {
    if (!PermissionService.instance.hasPermission(PosPermissions.customersDelete)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access Denied: You do not have permission to delete customers.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Archive Customer?'),
          ],
        ),
        content: Text('Are you sure you want to remove ${customer.fullName}? This can be restored later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await PosDao(widget.db).deleteCustomer(customer.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${customer.fullName} removed from customer directory.')),
                );
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'Platinum':
        return const Color(0xFF6366F1); // Indigo
      case 'Gold':
        return const Color(0xFFEAB308); // Amber Gold
      case 'Silver':
        return const Color(0xFF94A3B8); // Slate Silver
      case 'Bronze':
      default:
        return const Color(0xFFD97706); // Bronze Amber
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundColor,
      child: StreamBuilder<List<Customer>>(
        stream: (widget.db.select(widget.db.customers)
              ..where((c) => c.isDeleted.equals(false)))
            .watch(),
        builder: (context, snapshot) {
          final allCustomers = (snapshot.data ?? [])..sort((a, b) => a.fullName.compareTo(b.fullName));

          // KPI Calculations
          final totalCustomers = allCustomers.length;
          final totalPoints = allCustomers.fold(0.0, (sum, c) => sum + c.pointsBalance);
          final totalDue = allCustomers.fold(0.0, (sum, c) => sum + c.dueAmount);

          // Filtering
          final filteredCustomers = allCustomers.where((c) {
            final matchesTier = _selectedTier == 'All' || c.loyaltyTier.toLowerCase() == _selectedTier.toLowerCase();
            final q = _searchQuery.toLowerCase();
            final matchesSearch = q.isEmpty ||
                c.fullName.toLowerCase().contains(q) ||
                (c.phone?.toLowerCase().contains(q) ?? false) ||
                (c.email?.toLowerCase().contains(q) ?? false);
            return matchesTier && matchesSearch;
          }).toList();

          return Stack(
            children: [
              Column(
                children: [
                  // KPI Header Cards
                  Container(
                    padding: const EdgeInsets.all(14),
                    color: Colors.white,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _KpiMiniCard(
                                title: 'Total Customers',
                                value: '$totalCustomers',
                                icon: Icons.people_alt_rounded,
                                color: AppTheme.accentColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _KpiMiniCard(
                                title: 'Loyalty Points',
                                value: totalPoints.toStringAsFixed(0),
                                icon: Icons.stars_rounded,
                                color: const Color(0xFFEAB308),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _KpiMiniCard(
                                title: 'Receivables Due',
                                value: '₱${totalDue.toStringAsFixed(0)}',
                                icon: Icons.account_balance_wallet_rounded,
                                color: totalDue > 0 ? Colors.red : AppTheme.inStockColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Search and Filter Row
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.cardBorderColor),
                                ),
                                child: TextField(
                                  key: const Key('customer_search_input'),
                                  controller: _searchController,
                                  onChanged: (val) => setState(() => _searchQuery = val),
                                  decoration: InputDecoration(
                                    hintText: 'Search customer by name, phone, email...',
                                    hintStyle: const TextStyle(fontSize: 12),
                                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 16),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Loyalty Tier Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _filterTiers.map((tier) {
                              final isSelected = _selectedTier == tier;
                              final count = tier == 'All'
                                  ? allCustomers.length
                                  : allCustomers.where((c) => c.loyaltyTier.toLowerCase() == tier.toLowerCase()).length;

                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  selected: isSelected,
                                  label: Text('$tier ($count)'),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : Colors.black87,
                                  ),
                                  backgroundColor: Colors.white,
                                  selectedColor: tier == 'All' ? AppTheme.accentColor : _getTierColor(tier),
                                  checkmarkColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isSelected ? Colors.transparent : AppTheme.cardBorderColor,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) {
                                    setState(() => _selectedTier = tier);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Customer List
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.people_outline_rounded, size: 36, color: Colors.grey.shade400),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty || _selectedTier != 'All'
                                      ? 'No customers match the filter'
                                      : 'No customers registered yet',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _searchQuery.isNotEmpty || _selectedTier != 'All'
                                      ? 'Try clearing the search query or tier filter'
                                      : 'Add customers to track loyalty points and credit balance',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                if (PermissionService.instance.hasPermission(PosPermissions.customersAdd)) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    key: const Key('add_first_customer_button'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    icon: const Icon(Icons.person_add_rounded, size: 18),
                                    label: const Text('Add Customer', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () => _openAddCustomerDialog(),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                            itemCount: filteredCustomers.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final customer = filteredCustomers[index];
                              final canEdit = PermissionService.instance.hasPermission(PosPermissions.customersEdit);
                              final canDelete = PermissionService.instance.hasPermission(PosPermissions.customersDelete);
                              final canSettle = PermissionService.instance.hasPermission(PosPermissions.customersCreditSettle);
                              return _CustomerCard(
                                customer: customer,
                                tierColor: _getTierColor(customer.loyaltyTier),
                                canEdit: canEdit,
                                canDelete: canDelete,
                                canSettle: canSettle,
                                onEdit: () => _openAddCustomerDialog(customer),
                                onDelete: () => _confirmDeleteCustomer(customer),
                                onSettle: () => _openSettleCreditDialog(customer),
                                onHistory: () => _openPaymentHistoryDialog(customer),
                              );
                            },
                          ),
                  ),
                ],
              ),

              // Floating Action Button
              if (PermissionService.instance.hasPermission(PosPermissions.customersAdd))
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    key: const Key('add_customer_fab'),
                    heroTag: 'customers_fab',
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    icon: const Icon(Icons.person_add_rounded, size: 20),
                    label: const Text('Add Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _openAddCustomerDialog(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiMiniCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiMiniCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final Color tierColor;
  final bool canEdit;
  final bool canDelete;
  final bool canSettle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSettle;
  final VoidCallback onHistory;

  const _CustomerCard({
    required this.customer,
    required this.tierColor,
    required this.canEdit,
    required this.canDelete,
    required this.canSettle,
    required this.onEdit,
    required this.onDelete,
    required this.onSettle,
    required this.onHistory,
  });

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return 'C';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: tierColor.withValues(alpha: 0.15),
                child: Text(
                  _getInitials(customer.fullName),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: tierColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Name & Tier
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.fullName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stars_rounded, size: 12, color: tierColor),
                              const SizedBox(width: 3),
                              Text(
                                customer.loyaltyTier,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: tierColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (customer.phone != null && customer.phone!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_rounded, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(customer.phone!, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                            ],
                          ),
                        if (customer.email != null && customer.email!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.mail_rounded, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(customer.email!, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Menu
              if (canEdit || canDelete || canSettle)
                PopupMenuButton<String>(
                  key: Key('customer_card_menu_${customer.id}'),
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (val) {
                    if (val == 'edit') {
                      onEdit();
                    } else if (val == 'delete') {
                      onDelete();
                    } else if (val == 'settle') {
                      onSettle();
                    } else if (val == 'history') {
                      onHistory();
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16),
                            SizedBox(width: 8),
                            Expanded(child: Text('Edit Customer', style: TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    if (canSettle && customer.dueAmount > 0)
                      const PopupMenuItem(
                        value: 'settle',
                        child: Row(
                          children: [
                            Icon(Icons.payments_outlined, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(child: Text('Settle Due', style: TextStyle(fontSize: 13, color: Colors.red))),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Row(
                        children: [
                          Icon(Icons.history_rounded, size: 16),
                          SizedBox(width: 8),
                          Expanded(child: Text('Payment History', style: TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(child: Text('Archive / Remove', style: TextStyle(fontSize: 13, color: Colors.red))),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),

          if (customer.address != null && customer.address!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customer.address!,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1, color: AppTheme.cardBorderColor),
          const SizedBox(height: 8),

          // Loyalty & Due Details
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Points
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.loyalty_rounded, size: 13, color: AppTheme.accentColor),
                    const SizedBox(width: 4),
                    Text(
                      '${customer.pointsBalance.toStringAsFixed(0)} Points',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Credit / Due
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Due: ₱${customer.dueAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: customer.dueAmount > 0 ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '• Limit: ₱${customer.creditLimit.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  if (customer.dueAmount > 0 && canSettle) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      key: Key('settle_due_button_${customer.id}'),
                      onTap: onSettle,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payments_rounded, size: 12, color: Colors.red),
                            SizedBox(width: 4),
                            Text(
                              'Settle Due',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
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
          ),
        ],
      ),
    );
  }
}
