import 'package:flutter/material.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/permissions/pos_permissions.dart';
import '../../data/local/database.dart';
import '../../data/local/daos/pos_dao.dart';
import '../../services/transaction_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/reports/add_expense_dialog.dart';

class ReportsView extends StatefulWidget {
  final AppDatabase db;

  const ReportsView({super.key, required this.db});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  String _selectedPreset = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  int _refreshKey = 0;
  int _activeTab = 0; // 0: Sales & Profit, 1: Inventory Health

  final List<String> _presets = [
    'Today',
    'Yesterday',
    'Last 7 Days',
    'This Month',
    'All Time',
    'Custom',
  ];

  late Stream<List<Product>> _productsStream;
  late Stream<List<Inventory>> _inventoriesStream;
  Future<SalesReportData>? _salesReportFuture;

  @override
  void initState() {
    super.initState();
    _initStreams();
    _applyPreset('All Time');
  }

  void _initStreams() {
    _productsStream = widget.db.select(widget.db.products).watch();
    _inventoriesStream = widget.db.select(widget.db.inventories).watch();
  }

  @override
  void didUpdateWidget(covariant ReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) {
      _initStreams();
      _fetchReport();
    }
  }

  void _fetchReport() {
    _salesReportFuture = PosDao(
      widget.db,
    ).getSalesReportData(startDate: _startDate, endDate: _endDate);
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'Today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
          break;
        case 'Yesterday':
          final y = now.subtract(const Duration(days: 1));
          _startDate = DateTime(y.year, y.month, y.day);
          _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59, 999);
          break;
        case 'Last 7 Days':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case 'This Month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        case 'All Time':
        default:
          _startDate = null;
          _endDate = null;
          break;
      }
      _fetchReport();
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
    );

    if (picked != null) {
      setState(() {
        _selectedPreset = 'Custom';
        _startDate = picked.start;
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        );
        _fetchReport();
      });
    }
  }

  void _openAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddExpenseDialog(
        db: widget.db,
        onExpenseAdded: () {
          setState(() {
            _refreshKey++;
            _fetchReport();
          });
        },
      ),
    );
  }

  String get _periodLabel {
    if (_startDate == null || _endDate == null) return 'All Time Sales';
    final s =
        '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}';
    final e =
        '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}';
    return '$s to $e';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;

    return Container(
      color: AppTheme.backgroundColor,
      child: FutureBuilder<SalesReportData>(
        future: _salesReportFuture,
        builder: (context, snapshot) {
          final report = snapshot.data;
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
              report == null;

          return StreamBuilder<List<Product>>(
            stream: _productsStream,
            builder: (context, prodSnap) {
              final products = prodSnap.data ?? [];

              return StreamBuilder<List<Inventory>>(
                stream: _inventoriesStream,
                builder: (context, invSnap) {
                  final inventories = invSnap.data ?? [];

                  int inStockCount = 0;
                  int lowStockCount = 0;
                  int outOfStockCount = 0;
                  double totalValuation = 0.0;

                  if (_activeTab == 1) {
                    final prodPriceMap = <String, double>{
                      for (final p in products) p.id: p.price,
                    };
                    for (final inv in inventories) {
                      final q = inv.quantityOnHand;
                      if (q > 10) {
                        inStockCount++;
                      } else if (q > 0) {
                        lowStockCount++;
                      } else {
                        outOfStockCount++;
                      }
                      final price = prodPriceMap[inv.productId];
                      if (price != null) {
                        totalValuation += price * q;
                      }
                    }
                  }

                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    children: [
                      // 0. Top Report Tab Switcher
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _TabPill(
                                label:
                                    PermissionService.instance.hasPermission(
                                      PosPermissions.reportsPlFinancials,
                                    )
                                    ? 'Sales & Profit'
                                    : 'Sales Overview',
                                icon: Icons.trending_up_rounded,
                                isSelected: _activeTab == 0,
                                onTap: () => setState(() => _activeTab = 0),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _TabPill(
                                label: 'Inventory Health',
                                icon: Icons.inventory_2_rounded,
                                isSelected: _activeTab == 1,
                                onTap: () => setState(() => _activeTab = 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_activeTab == 0) ...[
                        // 1. Date Filter & Export Header
                        _buildHeaderFilterBar(report),
                        const SizedBox(height: 12),

                        if (isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (report != null) ...[
                          // 2. Profit & Loss (P&L) Master Card (Sales, Gross Profit, Expenses, Net Profit)
                          _buildPnlCard(report, isCompact),
                          const SizedBox(height: 14),

                          // 3. Transaction KPI Row (Receipt Count, AOV, Tax, Discounts)
                          _buildTransactionMetricsGrid(report, isCompact),
                          const SizedBox(height: 14),

                          // 4. Dual Section: Top Stocks (Best-Sellers) & Top Categories
                          if (isCompact) ...[
                            _buildTopStocksCard(report),
                            const SizedBox(height: 14),
                            _buildTopCategoriesCard(report),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildTopStocksCard(report)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildTopCategoriesCard(report),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),

                          // 5. Dual Section: Payment Modes & Top Customers
                          if (isCompact) ...[
                            _buildPaymentModesCard(report),
                            const SizedBox(height: 14),
                            _buildTopCustomersCard(report),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildPaymentModesCard(report)),
                                const SizedBox(width: 14),
                                Expanded(child: _buildTopCustomersCard(report)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),

                          // 6. Sold By (Staff Leaderboard)
                          if (PermissionService.instance.hasPermission(
                            PosPermissions.reportsStaffAudit,
                          )) ...[
                            _buildSoldByCard(report),
                            const SizedBox(height: 14),
                          ],

                          // 7. Operating Expenses Log
                          if (PermissionService.instance.hasPermission(
                            PosPermissions.reportsExpenses,
                          )) ...[
                            _buildExpensesLogCard(report),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ] else ...[
                        // Inventory Health & Stock Valuation
                        _buildInventoryHealthCard(
                          productsCount: products.length,
                          totalValuation: totalValuation,
                          inStockCount: inStockCount,
                          lowStockCount: lowStockCount,
                          outOfStockCount: outOfStockCount,
                          inventoriesCount: inventories.length,
                          isCompact: isCompact,
                        ),
                      ],
                      const SizedBox(height: 30),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // --- HEADER & FILTER BAR ---
  Widget _buildHeaderFilterBar(SalesReportData? report) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                size: 20,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _periodLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (report != null &&
                  PermissionService.instance.hasPermission(
                    PosPermissions.reportsExport,
                  ))
                ElevatedButton.icon(
                  key: const Key('export_report_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 15),
                  label: const Text(
                    'Export Excel',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    TransactionExportService.exportSalesReport(
                      context: context,
                      reportData: report,
                      periodLabel: _periodLabel,
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((preset) {
                final isSelected = _selectedPreset == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(preset),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                    backgroundColor: AppTheme.backgroundColor,
                    selectedColor: AppTheme.accentColor,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : AppTheme.cardBorderColor,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      if (preset == 'Custom') {
                        _pickCustomDateRange();
                      } else {
                        _applyPreset(preset);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- PROFIT & LOSS MASTER CARD ---
  Widget _buildPnlCard(SalesReportData r, bool isCompact) {
    final hasPl = PermissionService.instance.hasPermission(
      PosPermissions.reportsPlFinancials,
    );
    final hasExpenses = PermissionService.instance.hasPermission(
      PosPermissions.reportsExpenses,
    );

    return Container(
      key: const Key('pnl_financial_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      hasPl
                          ? Icons.account_balance_rounded
                          : Icons.trending_up_rounded,
                      size: 18,
                      color: AppTheme.accentColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasPl
                            ? 'Profit & Loss (P&L) Statement'
                            : 'Sales Revenue Overview',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasExpenses) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('add_expense_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text(
                    'Add Expense',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _openAddExpenseDialog,
                ),
              ],
            ],
          ),
          const Divider(
            height: 20,
            thickness: 1,
            color: AppTheme.cardBorderColor,
          ),

          if (!hasPl) ...[
            // Simplified Sales Overview without sensitive COGS or Profit Margins
            Row(
              children: [
                Expanded(
                  child: _buildFinanceMetric(
                    title: 'Total Sales (Net)',
                    value: '₱${r.netSales.toStringAsFixed(2)}',
                    subtitle: 'Tax-exclusive sales',
                    color: AppTheme.primaryColor,
                    icon: Icons.payments_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFinanceMetric(
                    title: 'Gross Sales',
                    value: '₱${r.grossSales.toStringAsFixed(2)}',
                    subtitle: 'Total tender collected',
                    color: const Color(0xFF6366F1),
                    icon: Icons.point_of_sale_rounded,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Full P&L statement
            Row(
              children: [
                Expanded(
                  child: _buildFinanceMetric(
                    title: 'Total Sales (Net)',
                    value: '₱${r.netSales.toStringAsFixed(2)}',
                    subtitle: 'Gross: ₱${r.grossSales.toStringAsFixed(2)}',
                    color: AppTheme.primaryColor,
                    icon: Icons.payments_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFinanceMetric(
                    title: 'COGS (Cost of Goods)',
                    value: '₱${r.totalCogs.toStringAsFixed(2)}',
                    subtitle: 'Product unit cost',
                    color: Colors.blueGrey,
                    icon: Icons.inventory_rounded,
                  ),
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFinanceMetric(
                      title: 'Gross Profit',
                      value: '₱${r.grossProfit.toStringAsFixed(2)}',
                      subtitle:
                          'Margin: ${r.grossMarginPercent.toStringAsFixed(1)}%',
                      color: AppTheme.inStockColor,
                      icon: Icons.trending_up_rounded,
                      isHighlight: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFinanceMetric(
                      title: 'Store Expenses',
                      value: '₱${r.totalExpenses.toStringAsFixed(2)}',
                      subtitle: '${r.recentExpenses.length} expense entries',
                      color: Colors.red.shade600,
                      icon: Icons.money_off_rounded,
                    ),
                  ),
                ],
              ],
            ),
            if (isCompact) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildFinanceMetric(
                      title: 'Gross Profit',
                      value: '₱${r.grossProfit.toStringAsFixed(2)}',
                      subtitle:
                          'Margin: ${r.grossMarginPercent.toStringAsFixed(1)}%',
                      color: AppTheme.inStockColor,
                      icon: Icons.trending_up_rounded,
                      isHighlight: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFinanceMetric(
                      title: 'Store Expenses',
                      value: '₱${r.totalExpenses.toStringAsFixed(2)}',
                      subtitle: '${r.recentExpenses.length} expense entries',
                      color: Colors.red.shade600,
                      icon: Icons.money_off_rounded,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),

            // Net Profit (Full-Width Bottom Line Highlight Banner)
            _buildFinanceMetric(
              title: 'Net Profit',
              value: '₱${r.netProfit.toStringAsFixed(2)}',
              subtitle:
                  'Net Margin: ${r.netMarginPercent.toStringAsFixed(1)}% • (Sales - Cost - Expenses)',
              color: r.netProfit >= 0 ? const Color(0xFF059669) : Colors.red,
              icon: Icons.monetization_on_rounded,
              isHighlight: true,
              isWide: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinanceMetric({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isHighlight = false,
    bool isWide = false,
  }) {
    return Container(
      width: isWide ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 14 : 12,
        vertical: isWide ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: isHighlight
            ? color.withValues(alpha: 0.08)
            : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight
              ? color.withValues(alpha: 0.3)
              : AppTheme.cardBorderColor,
        ),
      ),
      child: isWide
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }

  // --- TRANSACTION METRICS GRID ---
  Widget _buildTransactionMetricsGrid(SalesReportData r, bool isCompact) {
    if (isCompact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  title: 'Receipts',
                  value: '${r.totalReceipts}',
                  unit: 'Orders',
                  icon: Icons.receipt_rounded,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  title: 'Avg Order (AOV)',
                  value: '₱${r.avgSalesValue.toStringAsFixed(0)}',
                  unit: 'Per receipt',
                  icon: Icons.auto_graph_rounded,
                  color: const Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  title: 'VAT (12%)',
                  value: '₱${r.taxTotal.toStringAsFixed(0)}',
                  unit: 'Tax collected',
                  icon: Icons.account_balance_outlined,
                  color: const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  title: 'Discounts',
                  value: '₱${r.discountTotal.toStringAsFixed(0)}',
                  unit: 'Senior/PWD',
                  icon: Icons.discount_outlined,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildMiniStat(
            title: 'Receipts',
            value: '${r.totalReceipts}',
            unit: 'Orders',
            icon: Icons.receipt_rounded,
            color: AppTheme.accentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMiniStat(
            title: 'Avg Order (AOV)',
            value: '₱${r.avgSalesValue.toStringAsFixed(0)}',
            unit: 'Per receipt',
            icon: Icons.auto_graph_rounded,
            color: const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMiniStat(
            title: 'VAT (12%)',
            value: '₱${r.taxTotal.toStringAsFixed(0)}',
            unit: 'Tax collected',
            icon: Icons.account_balance_outlined,
            color: const Color(0xFF0284C7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMiniStat(
            title: 'Discounts',
            value: '₱${r.discountTotal.toStringAsFixed(0)}',
            unit: 'Senior/PWD',
            icon: Icons.discount_outlined,
            color: Colors.orange.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- TOP STOCKS CARD ---
  Widget _buildTopStocksCard(SalesReportData r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star_rounded, size: 18, color: Color(0xFFEAB308)),
              SizedBox(width: 6),
              Text(
                'Top Stocks (Best-Sellers)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.topProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No stock sales recorded in this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.topProducts.take(5).length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 12, thickness: 0.5),
              itemBuilder: (context, index) {
                final p = r.topProducts[index];
                return Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? const Color(0xFFEAB308)
                            : index == 1
                            ? const Color(0xFF94A3B8)
                            : index == 2
                            ? const Color(0xFFD97706)
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: index < 3 ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.productName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (p.variantName != null)
                            Text(
                              'Variant: ${p.variantName}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final hasPl = PermissionService.instance.hasPermission(
                          PosPermissions.reportsPlFinancials,
                        );
                        final qtyText =
                            '${p.quantitySold.toStringAsFixed(p.quantitySold % 1 == 0 ? 0 : 3)} sold';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₱${p.totalRevenue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            Text(
                              hasPl
                                  ? '$qtyText • Profit: ₱${p.profit.toStringAsFixed(0)}'
                                  : qtyText,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // --- TOP CATEGORIES CARD ---
  Widget _buildTopCategoriesCard(SalesReportData r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.category_rounded,
                size: 18,
                color: AppTheme.accentColor,
              ),
              SizedBox(width: 6),
              Text(
                'Top Categories',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.topCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No category sales in this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.topCategories.take(5).length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final cat = r.topCategories[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          cat.categoryName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₱${cat.totalRevenue.toStringAsFixed(2)} (${cat.sharePercentage.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (cat.sharePercentage / 100).clamp(0.0, 1.0),
                        backgroundColor: AppTheme.accentColor.withValues(
                          alpha: 0.12,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.accentColor,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // --- PAYMENT MODES CARD ---
  Widget _buildPaymentModesCard(SalesReportData r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.credit_card_rounded,
                size: 18,
                color: Color(0xFF6366F1),
              ),
              SizedBox(width: 6),
              Text(
                'Payment Modes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.paymentModes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No payment data in this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: r.paymentModes.map((pm) {
                return Container(
                  width: 135,
                  padding: const EdgeInsets.all(10),
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
                          Text(
                            pm.displayName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${pm.sharePercentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₱${pm.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      Text(
                        '${pm.count} tenders',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // --- TOP CUSTOMERS CARD ---
  Widget _buildTopCustomersCard(SalesReportData r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: Color(0xFF0284C7),
              ),
              SizedBox(width: 6),
              Text(
                'Top Customers',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.topCustomers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No customer sales in this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.topCustomers.take(5).length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 10, thickness: 0.5),
              itemBuilder: (context, index) {
                final c = r.topCustomers[index];
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppTheme.accentColor.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        c.customerName.isNotEmpty
                            ? c.customerName[0].toUpperCase()
                            : 'C',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.customerName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${c.ordersCount} orders • Tier: ${c.loyaltyTier}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₱${c.totalSpend.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // --- SOLD BY (STAFF LEADERBOARD) ---
  Widget _buildSoldByCard(SalesReportData r) {
    return Container(
      key: const Key('staff_sales_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_rounded, size: 18, color: AppTheme.primaryColor),
              SizedBox(width: 6),
              Text(
                'Sales by Staff (Sold By)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.soldBy.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No cashier sales recorded in this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.soldBy.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 10, thickness: 0.5),
              itemBuilder: (context, index) {
                final s = r.soldBy[index];
                return Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.employeeName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${s.position} • ${s.receiptCount} receipts • Avg: ₱${s.averageTicket.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₱${s.totalSales.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // --- OPERATING EXPENSES LOG CARD ---
  Widget _buildExpensesLogCard(SalesReportData r) {
    return Container(
      key: const Key('expenses_log_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 18,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Operating Expenses (₱${r.totalExpenses.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add, size: 14, color: Colors.red),
                label: const Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _openAddExpenseDialog,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (r.recentExpenses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  'No store expenses recorded for this period',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.recentExpenses.take(5).length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 8, thickness: 0.5),
              itemBuilder: (context, index) {
                final exp = r.recentExpenses[index];
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exp.category,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${exp.createdAt.toLocal().toString().substring(0, 10)}${exp.description != null ? ' • ${exp.description}' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₱${exp.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                    if (PermissionService.instance.hasPermission(
                      PosPermissions.reportsExpenses,
                    ))
                      IconButton(
                        key: Key('delete_expense_${exp.id}'),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.grey,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete Expense',
                        onPressed: () async {
                          await PosDao(widget.db).deleteExpense(exp.id);
                          setState(() => _refreshKey++);
                        },
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // --- INVENTORY HEALTH & VALUATION CARD (PRESERVED) ---
  Widget _buildInventoryHealthCard({
    required int productsCount,
    required double totalValuation,
    required int inStockCount,
    required int lowStockCount,
    required int outOfStockCount,
    required int inventoriesCount,
    required bool isCompact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Overview Cards
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Total Catalog',
                value: '$productsCount',
                unit: 'SKUs',
                icon: Icons.inventory_2_rounded,
                color: AppTheme.accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                title: 'Stock Valuation',
                value: '₱${totalValuation.toStringAsFixed(0)}',
                unit: 'Est. Retail',
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.inStockColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Stock Health Status
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inventory Health',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              _HealthBarRow(
                label: 'Optimal In Stock',
                count: inStockCount,
                total: inventoriesCount == 0 ? 1 : inventoriesCount,
                color: AppTheme.inStockColor,
              ),
              const SizedBox(height: 8),
              _HealthBarRow(
                label: 'Low Stock Alerts',
                count: lowStockCount,
                total: inventoriesCount == 0 ? 1 : inventoriesCount,
                color: AppTheme.lowStockColor,
              ),
              const SizedBox(height: 8),
              _HealthBarRow(
                label: 'Out of Stock',
                count: outOfStockCount,
                total: inventoriesCount == 0 ? 1 : inventoriesCount,
                color: AppTheme.outOfStockColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Text(
            unit,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HealthBarRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _HealthBarRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (count / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$count items',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
