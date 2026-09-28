import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../theme/app_theme.dart';
import '../../../services/transaction_export_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';

class ExportTransactionsDialog extends StatefulWidget {
  final List<TransactionDetail> filteredTransactions;
  final List<TransactionDetail> allTransactions;
  final DateTimeRange? activeDateRange;

  const ExportTransactionsDialog({
    super.key,
    required this.filteredTransactions,
    required this.allTransactions,
    this.activeDateRange,
  });

  @override
  State<ExportTransactionsDialog> createState() =>
      _ExportTransactionsDialogState();
}

class _ExportTransactionsDialogState extends State<ExportTransactionsDialog> {
  String _selectedFormat = 'xlsx'; // 'xlsx' or 'csv'
  String _selectedScope = 'filtered'; // 'filtered' or 'all'
  final bool _includeItemDetails = true;
  bool _isProcessing = false;
  String? _statusMessage;
  File? _savedFile;
  List<int>? _cachedBytes;

  List<TransactionDetail> get _targetList => _selectedScope == 'filtered'
      ? widget.filteredTransactions
      : widget.allTransactions;

  double get _targetTotalRevenue =>
      _targetList.fold(0.0, (sum, t) => sum + t.transaction.grandTotal);

  Future<void> _handleSaveToDevice() async {
    if (_targetList.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Generating $_selectedFormat report...';
    });

    try {
      final List<int> bytes;
      if (_selectedFormat == 'xlsx') {
        bytes = TransactionExportService.generateExcelWorkbook(
          transactions: _targetList,
          companyName: 'Apex Supermarket & POS',
          storeName: 'Main Retail Branch',
          dateRange: _selectedScope == 'filtered'
              ? widget.activeDateRange
              : null,
        );
      } else {
        final csvString = TransactionExportService.generateCsvReport(
          transactions: _targetList,
          companyName: 'Apex Supermarket & POS',
          dateRange: _selectedScope == 'filtered'
              ? widget.activeDateRange
              : null,
          includeItemDetails: _includeItemDetails,
        );
        bytes = csvString.codeUnits;
      }
      _cachedBytes = bytes;

      final file = await TransactionExportService.saveReportFile(
        bytes: bytes,
        extension: _selectedFormat,
        baseName: 'POS_Sales_Report',
      );

      setState(() {
        _savedFile = file;
        _statusMessage = 'Saved to Downloads:\n${file.path}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.download_done_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Saved to Downloads:\n${file.path}')),
              ],
            ),
            backgroundColor: AppTheme.inStockColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleShare() async {
    if (_targetList.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Preparing for share...';
    });

    try {
      List<int>? bytes = _cachedBytes;
      if (bytes == null) {
        if (_selectedFormat == 'xlsx') {
          bytes = TransactionExportService.generateExcelWorkbook(
            transactions: _targetList,
            companyName: 'Apex Supermarket & POS',
            storeName: 'Main Retail Branch',
            dateRange: _selectedScope == 'filtered'
                ? widget.activeDateRange
                : null,
          );
        } else {
          final csvString = TransactionExportService.generateCsvReport(
            transactions: _targetList,
            companyName: 'Apex Supermarket & POS',
            dateRange: _selectedScope == 'filtered'
                ? widget.activeDateRange
                : null,
            includeItemDetails: _includeItemDetails,
          );
          bytes = csvString.codeUnits;
        }
        _cachedBytes = bytes;
      }

      File file =
          _savedFile ??
          await TransactionExportService.saveReportFile(
            bytes: bytes,
            extension: _selectedFormat,
            baseName: 'POS_Sales_Report',
          );
      _savedFile = file;

      await TransactionExportService.shareFile(
        file,
        subject:
            'Apex POS Sales Transactions Report (${_targetList.length} orders)',
        fallbackBytes: bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.transactionsExport,
    )) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'You do not have permission to export transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 500;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
      ),
      insetPadding: isSmallScreen
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modal Header
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 14 : 20,
                vertical: isSmallScreen ? 12 : 16,
              ),
              decoration: const BoxDecoration(color: AppTheme.primaryColor),
              child: Row(
                children: [
                  Container(
                    width: isSmallScreen ? 38 : 42,
                    height: isSmallScreen ? 38 : 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.table_view_rounded,
                      color: Colors.white,
                      size: isSmallScreen ? 20 : 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Transactions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Advanced Excel (.xlsx) & CSV format',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Modal Body
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scope Preview Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Dataset',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_targetList.length} Transactions',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Total Revenue',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₱${_targetTotalRevenue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'EXPORT FORMAT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Format Selector (Radio tiles)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() {
                            _selectedFormat = 'xlsx';
                            _savedFile = null;
                            _cachedBytes = null;
                            _statusMessage = null;
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _selectedFormat == 'xlsx'
                                  ? Colors.green.shade50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedFormat == 'xlsx'
                                    ? Colors.green.shade600
                                    : AppTheme.cardBorderColor,
                                width: _selectedFormat == 'xlsx' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.grid_on_rounded,
                                      color: _selectedFormat == 'xlsx'
                                          ? Colors.green.shade700
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Excel (.xlsx)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedFormat == 'xlsx'
                                              ? Colors.green.shade900
                                              : AppTheme.primaryColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Multi-sheet formatted workbook with KPI cards',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() {
                            _selectedFormat = 'csv';
                            _savedFile = null;
                            _cachedBytes = null;
                            _statusMessage = null;
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _selectedFormat == 'csv'
                                  ? Colors.blue.shade50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedFormat == 'csv'
                                    ? Colors.blue.shade600
                                    : AppTheme.cardBorderColor,
                                width: _selectedFormat == 'csv' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.text_snippet_rounded,
                                      color: _selectedFormat == 'csv'
                                          ? Colors.blue.shade700
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'CSV (.csv)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedFormat == 'csv'
                                              ? Colors.blue.shade900
                                              : AppTheme.primaryColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Excel-ready UTF-8 BOM spreadsheet',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'EXPORT SCOPE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Scope Choices
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text(
                            'Filtered (${widget.filteredTransactions.length})',
                          ),
                          selected: _selectedScope == 'filtered',
                          onSelected: (val) => setState(() {
                            _selectedScope = 'filtered';
                            _savedFile = null;
                            _cachedBytes = null;
                            _statusMessage = null;
                          }),
                          selectedColor: AppTheme.accentColor.withValues(
                            alpha: 0.15,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedScope == 'filtered'
                                ? AppTheme.accentColor
                                : AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('All (${widget.allTransactions.length})'),
                          selected: _selectedScope == 'all',
                          onSelected: (val) => setState(() {
                            _selectedScope = 'all';
                            _savedFile = null;
                            _cachedBytes = null;
                            _statusMessage = null;
                          }),
                          selectedColor: AppTheme.accentColor.withValues(
                            alpha: 0.15,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedScope == 'all'
                                ? AppTheme.accentColor
                                : AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppTheme.accentColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('save_report_to_device_button'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.cardBorderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt_rounded, size: 18),
                      label: const Text(
                        'Save to Device',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isProcessing || _targetList.isEmpty
                          ? null
                          : _handleSaveToDevice,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      key: const Key('share_report_button'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share / Open',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isProcessing || _targetList.isEmpty
                          ? null
                          : _handleShare,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
