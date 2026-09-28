import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../theme/app_theme.dart';
import '../../../services/transaction_export_service.dart';
import '../../../core/device_prefs.dart';
import '../auth/manager_override_dialog.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';

class TransactionDetailDialog extends StatefulWidget {
  final TransactionDetail transactionDetail;
  final dynamic
  db; // dynamic to avoid drift import conflict temporarily, we'll fix it if needed

  const TransactionDetailDialog({
    super.key,
    required this.transactionDetail,
    required this.db,
  });

  @override
  State<TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  bool _isExporting = false;

  void _copyInvoiceNumber() {
    Clipboard.setData(
      ClipboardData(text: widget.transactionDetail.transaction.invoiceNo),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Invoice ${widget.transactionDetail.transaction.invoiceNo} copied!',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportSingleReceipt() async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.transactionsReceipt,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to reprint or share receipts.',
          ),
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final bytes = TransactionExportService.generateExcelWorkbook(
        transactions: [widget.transactionDetail],
        companyName: 'Apex Supermarket & POS',
        storeName: 'Main Retail Branch',
      );
      final file = await TransactionExportService.saveReportFile(
        bytes: bytes,
        extension: 'xlsx',
        baseName: 'Receipt_${widget.transactionDetail.transaction.invoiceNo}',
      );
      if (mounted) {
        await TransactionExportService.shareFile(
          file,
          subject: 'Receipt ${widget.transactionDetail.transaction.invoiceNo}',
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
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.transactionDetail;
    final tx = detail.transaction;
    final tender = detail.tenders.isNotEmpty ? detail.tenders.first : null;
    final isCash = (tender?.paymentMethod.toLowerCase() ?? 'cash') == 'cash';
    final isGCash = (tender?.paymentMethod.toLowerCase() ?? '') == 'gcash';
    final isMaya = (tender?.paymentMethod.toLowerCase() ?? '') == 'maya';
    final isCredit = (tender?.paymentMethod.toLowerCase() ?? '') == 'credit';
    final hasReceipt = PermissionService.instance.hasPermission(
      PosPermissions.transactionsReceipt,
    );
    final hasRefund = PermissionService.instance.hasPermission(
      PosPermissions.transactionsRefund,
    );

    Color tenderColor = Colors.teal;
    IconData tenderIcon = Icons.money_rounded;
    if (isGCash) {
      tenderColor = Colors.blue.shade700;
      tenderIcon = Icons.phone_android_rounded;
    } else if (isMaya) {
      tenderColor = Colors.green.shade700;
      tenderIcon = Icons.account_balance_wallet_rounded;
    } else if (isCredit) {
      tenderColor = const Color(0xFFE11D48);
      tenderIcon = Icons.account_balance_rounded;
    } else if (!isCash) {
      tenderColor = Colors.indigo;
      tenderIcon = Icons.credit_card_rounded;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 500;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
      ),
      insetPadding: isSmallScreen
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: isSmallScreen ? screenHeight * 0.92 : 680,
        ),
        child: Column(
          children: [
            // Receipt Header Banner
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 14 : 20,
                vertical: isSmallScreen ? 12 : 16,
              ),
              decoration: const BoxDecoration(color: AppTheme.primaryColor),
              child: Row(
                children: [
                  Container(
                    width: isSmallScreen ? 38 : 44,
                    height: isSmallScreen ? 38 : 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: isSmallScreen ? 20 : 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transaction Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Apex Supermarket • Main Checkout #1',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
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

            // Scrollable Content
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(isSmallScreen ? 12 : 18),
                children: [
                  // Invoice & Date Row
                  Container(
                    padding: const EdgeInsets.all(12),
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
                            Row(
                              children: [
                                Text(
                                  tx.invoiceNo,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _copyInvoiceNumber,
                                  child: const Icon(
                                    Icons.copy_rounded,
                                    size: 14,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tx.transactionDatetime
                                  .toLocal()
                                  .toString()
                                  .substring(0, 16),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.inStockBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tx.status.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.inStockColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'PURCHASED ITEMS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Itemized List
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorderColor),
                    ),
                    child: Column(
                      children: [
                        for (int idx = 0; idx < detail.items.length; idx++) ...[
                          if (idx > 0)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: AppTheme.cardBorderColor,
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              detail
                                                  .items[idx]
                                                  .product
                                                  .productName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primaryColor,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (detail
                                                      .items[idx]
                                                      .product
                                                      .variantName !=
                                                  null &&
                                              detail
                                                  .items[idx]
                                                  .product
                                                  .variantName!
                                                  .isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.amber.shade200,
                                                ),
                                              ),
                                              child: Text(
                                                detail
                                                    .items[idx]
                                                    .product
                                                    .variantName!,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  detail
                                                          .items[idx]
                                                          .product
                                                          .sellBy ==
                                                      'fraction'
                                                  ? Colors.teal.shade50
                                                  : Colors.blue.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              detail
                                                          .items[idx]
                                                          .product
                                                          .sellBy ==
                                                      'fraction'
                                                  ? '${detail.items[idx].item.quantity.toStringAsFixed(3)} kg'
                                                  : '${detail.items[idx].item.quantity.toInt()} pcs',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    detail
                                                            .items[idx]
                                                            .product
                                                            .sellBy ==
                                                        'fraction'
                                                    ? Colors.teal.shade800
                                                    : Colors.blue.shade800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '@ ₱${detail.items[idx].item.unitPrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₱${detail.items[idx].item.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'PAYMENT & TOTALS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Financial Breakdown
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorderColor),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow(
                          'Subtotal',
                          '₱${tx.subtotal.toStringAsFixed(2)}',
                        ),
                        if (tx.discountTotal > 0)
                          _buildSummaryRow(
                            'Discounts (Senior/PWD)',
                            '-₱${tx.discountTotal.toStringAsFixed(2)}',
                            color: Colors.green.shade700,
                          ),
                        if (tx.taxTotal > 0)
                          _buildSummaryRow(
                            'VAT (12%)',
                            '₱${tx.taxTotal.toStringAsFixed(2)}',
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: AppTheme.cardBorderColor,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Grand Total',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            Text(
                              '₱${tx.grandTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Payment Tender Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tenderColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tenderColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: tenderColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(tenderIcon, color: tenderColor, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCredit
                                    ? 'STORE CREDIT (ON ACCOUNT)'
                                    : '${tender?.paymentMethod.toUpperCase() ?? "CASH"} PAYMENT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: tenderColor,
                                ),
                              ),
                              Text(
                                isCredit
                                    ? (tender?.referenceNo != null &&
                                              tender!.referenceNo!.isNotEmpty
                                          ? 'PO / Ref: ${tender.referenceNo}'
                                          : 'Charged to customer account')
                                    : (tender?.referenceNo != null &&
                                              tender!.referenceNo!.isNotEmpty
                                          ? 'Ref: ${tender.referenceNo}'
                                          : 'Tendered: ₱${(tender?.amountTendered ?? tx.grandTotal).toStringAsFixed(2)}'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (tender != null && tender.changeAmount > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '₱${tender.changeAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer Actions
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 10 : 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              child: Row(
                children: [
                  if (hasReceipt) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('export_share_receipt_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(
                            color: AppTheme.cardBorderColor,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _isExporting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.share_rounded, size: 16),
                        label: const Text(
                          'Export / Share Receipt',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isExporting ? null : _exportSingleReceipt,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasRefund) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('transaction_refund_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Refund',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          final isCashier =
                              DevicePrefs.currentEmployeeRole?.toLowerCase() !=
                              'admin';
                          if (isCashier && DevicePrefs.requirePinForUnlock) {
                            final authorized =
                                await ManagerOverrideDialog.requestOverride(
                                  context,
                                  widget.db,
                                  'Authorize Refund for Invoice ${widget.transactionDetail.transaction.invoiceNo}',
                                );
                            if (!authorized) return;
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Refund authorized! (Feature in development)',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  (hasReceipt || hasRefund)
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildSummaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
