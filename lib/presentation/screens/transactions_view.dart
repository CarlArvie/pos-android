import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import '../../data/local/database.dart';
import '../../data/local/daos/pos_dao.dart';
import '../../core/device_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/transactions/transaction_detail_dialog.dart';
import '../widgets/transactions/export_transactions_dialog.dart';
import '../../core/permissions/pos_permissions.dart';
import '../../core/permissions/permission_service.dart';

class TransactionsView extends StatefulWidget {
  final AppDatabase db;

  const TransactionsView({super.key, required this.db});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _datePreset =
      'all'; // 'all', 'today', 'yesterday', '7days', 'month', 'custom'
  DateTimeRange? _customDateRange;
  String _paymentMethodFilter = 'all'; // 'all', 'cash', 'gcash', 'maya', 'card'
  String _sortBy = 'newest'; // 'newest', 'oldest', 'highest', 'lowest'

  // Dedicated persistent streams initialized once (not re-created in build())
  late Stream<List<SalesTransaction>> _transactionsStream;
  late Stream<List<TenderPayment>> _tenderPaymentsStream;
  late Stream<List<TransactionItem>> _transactionItemsStream;

  // Memoized maps to prevent O(N) re-indexing on every search character or filter change
  List<TenderPayment>? _lastTenders;
  Map<String, TenderPayment> _tenderMap = const {};

  List<TransactionItem>? _lastItems;
  Map<String, int> _itemCountMap = const {};

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    _transactionsStream = (widget.db.select(
      widget.db.salesTransactions,
    )..orderBy([(t) => OrderingTerm.desc(t.transactionDatetime)])).watch();
    _tenderPaymentsStream = widget.db.select(widget.db.tenderPayments).watch();
    _transactionItemsStream = widget.db
        .select(widget.db.transactionItems)
        .watch();
  }

  @override
  void didUpdateWidget(covariant TransactionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) {
      _initStreams();
      _lastTenders = null;
      _lastItems = null;
      _tenderMap = const {};
      _itemCountMap = const {};
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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

  void _syncTenderMap(List<TenderPayment> tenders) {
    if (identical(_lastTenders, tenders)) return;
    _lastTenders = tenders;
    final map = <String, TenderPayment>{};
    for (final tender in tenders) {
      map[tender.salesTransactionId] = tender;
    }
    _tenderMap = map;
  }

  void _syncItemCountMap(List<TransactionItem> items) {
    if (identical(_lastItems, items)) return;
    _lastItems = items;
    final map = <String, int>{};
    for (final item in items) {
      map[item.salesTransactionId] = (map[item.salesTransactionId] ?? 0) + 1;
    }
    _itemCountMap = map;
  }

  DateTimeRange? _getDateRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (_datePreset) {
      case 'today':
        return DateTimeRange(start: startOfToday, end: endOfToday);
      case 'yesterday':
        final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
        final endOfYesterday = DateTime(
          startOfYesterday.year,
          startOfYesterday.month,
          startOfYesterday.day,
          23,
          59,
          59,
          999,
        );
        return DateTimeRange(start: startOfYesterday, end: endOfYesterday);
      case '7days':
        final sevenDaysAgo = startOfToday.subtract(const Duration(days: 6));
        return DateTimeRange(start: sevenDaysAgo, end: endOfToday);
      case 'month':
        final startOfMonth = DateTime(now.year, now.month, 1);
        return DateTimeRange(start: startOfMonth, end: endOfToday);
      case 'custom':
        return _customDateRange;
      default:
        return null;
    }
  }

  bool _isFilterActive() {
    return _searchQuery.isNotEmpty ||
        _datePreset != 'all' ||
        _paymentMethodFilter != 'all' ||
        _sortBy != 'newest';
  }

  void _resetFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _datePreset = 'all';
      _customDateRange = null;
      _paymentMethodFilter = 'all';
      _sortBy = 'newest';
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange:
          _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.accentColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _datePreset = 'custom';
        _customDateRange = DateTimeRange(
          start: DateTime(
            picked.start.year,
            picked.start.month,
            picked.start.day,
          ),
          end: DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
            999,
          ),
        );
      });
    }
  }

  Future<void> _openTransactionDetail(String transactionId) async {
    final dao = PosDao(widget.db);
    final detail = await dao.getTransactionDetail(transactionId);
    if (detail != null && mounted) {
      showDialog(
        context: context,
        builder: (ctx) =>
            TransactionDetailDialog(transactionDetail: detail, db: widget.db),
      );
    }
  }

  Future<void> _openExportModal(
    List<SalesTransaction> filteredTxs,
    List<SalesTransaction> allTxs,
  ) async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.transactionsExport,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to export transactions.',
          ),
        ),
      );
      return;
    }

    final dao = PosDao(widget.db);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ),
    );
    final hasViewAll = PermissionService.instance.hasPermission(
      PosPermissions.transactionsViewAll,
    );
    final hasViewOwn = PermissionService.instance.hasPermission(
      PosPermissions.transactionsViewOwn,
    );
    final empId = DevicePrefs.currentEmployeeId;
    final allDetails = await dao.getAllTransactionDetails(
      employeeId: hasViewAll ? null : (hasViewOwn ? empId : '__none__'),
    );
    final filteredIds = filteredTxs.map((t) => t.id).toSet();
    final filteredDetails = allDetails
        .where((d) => filteredIds.contains(d.transaction.id))
        .toList();

    if (mounted) {
      Navigator.of(context).pop(); // dismiss loading
      showDialog(
        context: context,
        builder: (ctx) => ExportTransactionsDialog(
          filteredTransactions: filteredDetails,
          allTransactions: allDetails,
          activeDateRange: _getDateRange(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundColor,
      child: StreamBuilder<List<SalesTransaction>>(
        stream: _transactionsStream,
        builder: (context, txSnapshot) {
          return StreamBuilder<List<TenderPayment>>(
            stream: _tenderPaymentsStream,
            builder: (context, tenderSnapshot) {
              return StreamBuilder<List<TransactionItem>>(
                stream: _transactionItemsStream,
                builder: (context, itemSnapshot) {
                  final allTxs = txSnapshot.data ?? const [];
                  final allTenders = tenderSnapshot.data ?? const [];
                  final allItems = itemSnapshot.data ?? const [];

                  // Sync memoized maps (avoids rebuilding maps if lists didn't change)
                  _syncTenderMap(allTenders);
                  _syncItemCountMap(allItems);

                  // Apply Filters
                  final range = _getDateRange();
                  final hasViewAll = PermissionService.instance.hasPermission(
                    PosPermissions.transactionsViewAll,
                  );
                  final hasViewOwn = PermissionService.instance.hasPermission(
                    PosPermissions.transactionsViewOwn,
                  );
                  final hasExport = PermissionService.instance.hasPermission(
                    PosPermissions.transactionsExport,
                  );
                  final empId = DevicePrefs.currentEmployeeId;

                  final filteredTxs = allTxs.where((tx) {
                    final tender = _tenderMap[tx.id];

                    // Employee View Permission Restriction
                    if (!hasViewAll) {
                      if (!hasViewOwn || tx.employeeId != empId) return false;
                    }

                    // Search Query
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery.toLowerCase();
                      final matchInvoice = tx.invoiceNo.toLowerCase().contains(
                        q,
                      );
                      final matchRef =
                          tender?.referenceNo?.toLowerCase().contains(q) ??
                          false;
                      if (!matchInvoice && !matchRef) return false;
                    }

                    // Date Range
                    if (range != null) {
                      if (tx.transactionDatetime.isBefore(range.start) ||
                          tx.transactionDatetime.isAfter(range.end)) {
                        return false;
                      }
                    }

                    // Payment Method
                    if (_paymentMethodFilter != 'all') {
                      final method = (tender?.paymentMethod ?? 'cash')
                          .toLowerCase();
                      if (method != _paymentMethodFilter.toLowerCase()) {
                        return false;
                      }
                    }

                    return true;
                  }).toList();

                  // Sort
                  switch (_sortBy) {
                    case 'oldest':
                      filteredTxs.sort(
                        (a, b) => a.transactionDatetime.compareTo(
                          b.transactionDatetime,
                        ),
                      );
                      break;
                    case 'highest':
                      filteredTxs.sort(
                        (a, b) => b.grandTotal.compareTo(a.grandTotal),
                      );
                      break;
                    case 'lowest':
                      filteredTxs.sort(
                        (a, b) => a.grandTotal.compareTo(b.grandTotal),
                      );
                      break;
                    case 'newest':
                    default:
                      filteredTxs.sort(
                        (a, b) => b.transactionDatetime.compareTo(
                          a.transactionDatetime,
                        ),
                      );
                      break;
                  }

                  // Compute KPI metrics for filtered set
                  double totalRevenue = 0.0;
                  int cashCount = 0;
                  int gcashCount = 0;
                  int mayaCount = 0;
                  int cardCount = 0;
                  int creditCount = 0;

                  for (final tx in filteredTxs) {
                    totalRevenue += tx.grandTotal;
                    final m = (_tenderMap[tx.id]?.paymentMethod ?? 'cash')
                        .toLowerCase();
                    if (m == 'cash') {
                      cashCount++;
                    } else if (m == 'gcash') {
                      gcashCount++;
                    } else if (m == 'maya') {
                      mayaCount++;
                    } else if (m == 'credit') {
                      creditCount++;
                    } else {
                      cardCount++;
                    }
                  }

                  final double aov = filteredTxs.isNotEmpty
                      ? totalRevenue / filteredTxs.length
                      : 0.0;

                  return Column(
                    children: [
                      // Unified Control Deck (Header + KPIs + Search + Filters)
                      _buildUnifiedControlDeck(
                        filteredTxs: filteredTxs,
                        allTxs: allTxs,
                        hasExport: hasExport,
                        totalRevenue: totalRevenue,
                        orderCount: filteredTxs.length,
                        aov: aov,
                        cashCount: cashCount,
                        gcashCount: gcashCount,
                        mayaCount: mayaCount,
                        cardCount: cardCount,
                        creditCount: creditCount,
                      ),

                      // Transactions List or Empty State
                      Expanded(
                        child: filteredTxs.isEmpty
                            ? _buildEmptyState(allTxs.isNotEmpty)
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(),
                                cacheExtent: 300,
                                addRepaintBoundaries: true,
                                addAutomaticKeepAlives: false,
                                itemCount: filteredTxs.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final tx = filteredTxs[index];
                                  final tender = _tenderMap[tx.id];
                                  final itemCount = _itemCountMap[tx.id] ?? 0;
                                  return _buildTransactionCard(
                                    tx,
                                    tender,
                                    itemCount,
                                  );
                                },
                              ),
                      ),
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

  // ==========================================
  // Unified Control Deck (Decluttered Surface)
  // ==========================================
  Widget _buildUnifiedControlDeck({
    required List<SalesTransaction> filteredTxs,
    required List<SalesTransaction> allTxs,
    required bool hasExport,
    required double totalRevenue,
    required int orderCount,
    required double aov,
    required int cashCount,
    required int gcashCount,
    required int mayaCount,
    required int cardCount,
    required int creditCount,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: Column(
        children: [
          // Row 1: Header & Export
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transaction Ledger',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Live offline ledger • ${allTxs.length} total orders recorded',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasExport)
                  ElevatedButton.icon(
                    key: const Key('export_transactions_button'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: const Text(
                      'Export Excel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _openExportModal(filteredTxs, allTxs),
                  ),
              ],
            ),
          ),

          // Row 2: KPI Metrics Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    // Revenue KPI
                    Expanded(
                      child: _buildMetricCard(
                        label: 'Filtered Revenue',
                        value: '₱${totalRevenue.toStringAsFixed(2)}',
                        icon: Icons.payments_rounded,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Orders KPI
                    Expanded(
                      child: _buildMetricCard(
                        label: 'Total Orders',
                        value: '$orderCount txs',
                        icon: Icons.receipt_rounded,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // AOV KPI
                    Expanded(
                      child: _buildMetricCard(
                        label: 'Avg Ticket',
                        value: '₱${aov.toStringAsFixed(0)}',
                        icon: Icons.query_stats_rounded,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Payment Breakdown Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildMethodPill('Cash', cashCount, Colors.teal),
                      const SizedBox(width: 6),
                      _buildMethodPill(
                        'GCash',
                        gcashCount,
                        Colors.blue.shade700,
                      ),
                      const SizedBox(width: 6),
                      _buildMethodPill(
                        'Maya',
                        mayaCount,
                        Colors.green.shade700,
                      ),
                      const SizedBox(width: 6),
                      _buildMethodPill('Card', cardCount, Colors.indigo),
                      if (creditCount > 0) ...[
                        const SizedBox(width: 6),
                        _buildMethodPill(
                          'Credit',
                          creditCount,
                          const Color(0xFFE11D48),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Row 3: Search Bar with Debounce
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorderColor),
              ),
              child: TextField(
                key: const Key('transaction_search_input'),
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Search by Invoice No (e.g. INV-2026-)...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.accentColor,
                    size: 18,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),

          // Row 4: Horizontal Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  // Date Presets
                  _buildFilterChip(
                    'All Time',
                    _datePreset == 'all',
                    () => setState(() => _datePreset = 'all'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Today',
                    _datePreset == 'today',
                    () => setState(() => _datePreset = 'today'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Yesterday',
                    _datePreset == 'yesterday',
                    () => setState(() => _datePreset = 'yesterday'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Last 7 Days',
                    _datePreset == '7days',
                    () => setState(() => _datePreset = '7days'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'This Month',
                    _datePreset == 'month',
                    () => setState(() => _datePreset = 'month'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    _customDateRange != null
                        ? '${_customDateRange!.start.month}/${_customDateRange!.start.day}-${_customDateRange!.end.month}/${_customDateRange!.end.day}'
                        : 'Custom...',
                    _datePreset == 'custom',
                    _pickCustomDateRange,
                    icon: Icons.calendar_month_rounded,
                  ),

                  const SizedBox(width: 10),
                  Container(width: 1, height: 18, color: Colors.grey.shade300),
                  const SizedBox(width: 10),

                  // Payment Method Filter
                  _buildFilterChip(
                    'All Methods',
                    _paymentMethodFilter == 'all',
                    () => setState(() => _paymentMethodFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    '💵 Cash',
                    _paymentMethodFilter == 'cash',
                    () => setState(() => _paymentMethodFilter = 'cash'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    '📱 GCash',
                    _paymentMethodFilter == 'gcash',
                    () => setState(() => _paymentMethodFilter = 'gcash'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    '💳 Maya',
                    _paymentMethodFilter == 'maya',
                    () => setState(() => _paymentMethodFilter = 'maya'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    '💳 Card',
                    _paymentMethodFilter == 'card',
                    () => setState(() => _paymentMethodFilter = 'card'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    '🏦 Credit',
                    _paymentMethodFilter == 'credit',
                    () => setState(() => _paymentMethodFilter = 'credit'),
                  ),

                  const SizedBox(width: 10),
                  Container(width: 1, height: 18, color: Colors.grey.shade300),
                  const SizedBox(width: 10),

                  // Sort Choices
                  _buildFilterChip(
                    'Newest',
                    _sortBy == 'newest',
                    () => setState(() => _sortBy = 'newest'),
                    icon: Icons.arrow_downward_rounded,
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Oldest',
                    _sortBy == 'oldest',
                    () => setState(() => _sortBy = 'oldest'),
                    icon: Icons.arrow_upward_rounded,
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Highest ₱',
                    _sortBy == 'highest',
                    () => setState(() => _sortBy = 'highest'),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    'Lowest ₱',
                    _sortBy == 'lowest',
                    () => setState(() => _sortBy = 'lowest'),
                  ),
                ],
              ),
            ),
          ),

          // Row 5: Active Filter Indicator Banner
          if (_isFilterActive())
            _buildActiveFilterIndicator(filteredTxs.length, allTxs.length),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodPill(String name, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$name: $count',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentColor.withValues(alpha: 0.12)
              : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : AppTheme.cardBorderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: isSelected ? AppTheme.accentColor : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? AppTheme.accentColor
                    : AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterIndicator(int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: Colors.amber.shade50,
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 14,
            color: Colors.amber.shade900,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing $filteredCount of $totalCount orders (Filters active)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
              ),
            ),
          ),
          InkWell(
            onTap: _resetFilters,
            child: Text(
              'Reset',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Transaction Card (Optimized for Mobile Ergonomics & Low-End GPU)
  // ==========================================
  Widget _buildTransactionCard(
    SalesTransaction tx,
    TenderPayment? tender,
    int itemCount,
  ) {
    final isCash = (tender?.paymentMethod.toLowerCase() ?? 'cash') == 'cash';
    final isGCash = (tender?.paymentMethod.toLowerCase() ?? '') == 'gcash';
    final isMaya = (tender?.paymentMethod.toLowerCase() ?? '') == 'maya';
    final isCredit = (tender?.paymentMethod.toLowerCase() ?? '') == 'credit';

    Color methodBg = Colors.teal.shade50;
    Color methodColor = Colors.teal.shade800;
    String methodLabel = 'CASH';

    if (isGCash) {
      methodBg = Colors.blue.shade50;
      methodColor = Colors.blue.shade800;
      methodLabel = 'GCASH';
    } else if (isMaya) {
      methodBg = Colors.green.shade50;
      methodColor = Colors.green.shade800;
      methodLabel = 'MAYA';
    } else if (isCredit) {
      methodBg = const Color(0xFFE11D48).withValues(alpha: 0.1);
      methodColor = const Color(0xFFE11D48);
      methodLabel = 'CREDIT';
    } else if (!isCash) {
      methodBg = Colors.indigo.shade50;
      methodColor = Colors.indigo.shade800;
      methodLabel = 'CARD';
    }

    return RepaintBoundary(
      child: InkWell(
        onTap: () => _openTransactionDetail(tx.id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Row(
            children: [
              // Receipt Icon Box
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.primaryColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),

              // Middle: Invoice & Meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tx.invoiceNo,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: methodBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            methodLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: methodColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tx.transactionDatetime
                                .toLocal()
                                .toString()
                                .substring(0, 16),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '• $itemCount items',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Right: Amount & Status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${tx.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.inStockBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tx.status.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.inStockColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Empty State
  // ==========================================
  Widget _buildEmptyState(bool hasTransactionsInDb) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              hasTransactionsInDb
                  ? 'No Matching Transactions'
                  : 'No Transactions Recorded',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasTransactionsInDb
                  ? 'Try adjusting your search or date filter presets'
                  : 'Completed sales transactions will appear here',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            if (hasTransactionsInDb && _isFilterActive()) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  side: const BorderSide(color: AppTheme.accentColor),
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 14),
                label: const Text(
                  'Reset Filters',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _resetFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
