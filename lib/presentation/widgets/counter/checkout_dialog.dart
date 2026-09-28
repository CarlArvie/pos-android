import 'dart:math';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../models/cart_item.dart';
import '../../theme/app_theme.dart';

class CheckoutDialog extends StatefulWidget {
  final AppDatabase db;
  final List<CartItem> items;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double grandTotal;
  final String? shiftId;
  final Customer? customer;
  final VoidCallback onSaleCompleted;

  const CheckoutDialog({
    super.key,
    required this.db,
    required this.items,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    this.shiftId,
    this.customer,
    required this.onSaleCompleted,
  });

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  String _paymentMethod = 'cash'; // cash, gcash, maya, card, credit
  final TextEditingController _amountTenderedController =
      TextEditingController();
  final TextEditingController _refNoController = TextEditingController();
  bool _isProcessing = false;
  bool _isSuccess = false;
  String _generatedInvoiceNo = '';
  double _finalChangeAmount = 0.0;

  @override
  void initState() {
    super.initState();
    // Default tender to exact amount
    _amountTenderedController.text = widget.grandTotal.toStringAsFixed(2);
    _amountTenderedController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountTenderedController.dispose();
    _refNoController.dispose();
    super.dispose();
  }

  bool get _canChargeCredit {
    return widget.customer != null &&
        PermissionService.instance.hasPermission(
          PosPermissions.customersCreditCharge,
        );
  }

  double get _availableCredit {
    if (widget.customer == null) return 0.0;
    final avail = widget.customer!.creditLimit - widget.customer!.dueAmount;
    return avail > 0 ? avail : 0.0;
  }

  double get _amountTendered {
    return double.tryParse(_amountTenderedController.text.trim()) ?? 0.0;
  }

  double get _changeAmount {
    if (_paymentMethod != 'cash') return 0.0;
    final change = _amountTendered - widget.grandTotal;
    return change >= 0 ? change : 0.0;
  }

  bool get _canSubmit {
    if (_isProcessing) return false;
    if (_paymentMethod == 'cash') {
      return _amountTendered >= widget.grandTotal;
    }
    if (_paymentMethod == 'credit') {
      if (!_canChargeCredit) return false;
      return widget.grandTotal <= _availableCredit;
    }
    return true;
  }

  void _setCashBill(double amount) {
    setState(() {
      _amountTenderedController.text = amount.toStringAsFixed(2);
    });
  }

  List<double> _getSuggestedBills() {
    final total = widget.grandTotal;
    final List<double> bills = [total]; // Exact

    const standardBills = [50.0, 100.0, 200.0, 500.0, 1000.0];
    for (final bill in standardBills) {
      if (bill >= total && !bills.contains(bill)) {
        bills.add(bill);
      }
    }

    // Also round up to next 100 or 500
    final nextHundred = (total / 100).ceil() * 100.0;
    if (nextHundred > total && !bills.contains(nextHundred)) {
      bills.add(nextHundred);
    }
    final nextFiveHundred = (total / 500).ceil() * 500.0;
    if (nextFiveHundred > total && !bills.contains(nextFiveHundred)) {
      bills.add(nextFiveHundred);
    }

    bills.sort();
    return bills.take(5).toList();
  }

  Future<void> _processCheckout() async {
    if (!_canSubmit) return;
    setState(() => _isProcessing = true);

    try {
      final companies = await widget.db.select(widget.db.companies).get();
      final stores = await widget.db.select(widget.db.stores).get();
      final registers = await widget.db.select(widget.db.cashRegisters).get();

      final companyId =
          DevicePrefs.companyId ??
          (companies.isNotEmpty ? companies.first.id : 'default-company-001');
      final storeId =
          DevicePrefs.storeId ??
          (stores.isNotEmpty ? stores.first.id : 'default-store-001');
      final registerId =
          DevicePrefs.registerId ??
          (registers.isNotEmpty ? registers.first.id : 'default-reg-001');

      // Generate realistic readable collision-resistant invoice number
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final randomSeq = (Random().nextInt(900) + 100).toString();
      final invoiceNo = 'INV-$dateStr-$timeStr-$randomSeq';

      final posDao = PosDao(widget.db);

      // Prepare line items
      final transactionItems = widget.items.map((item) {
        return (
          productId: item.product.id,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discountAmount: item.discount,
          taxAmount: item.taxAmount,
        );
      }).toList();

      // Prepare tender payments
      final tendered = _paymentMethod == 'cash'
          ? _amountTendered
          : widget.grandTotal;
      final change = _paymentMethod == 'cash' ? _changeAmount : 0.0;

      final tenderPayments = [
        (
          paymentMethod: _paymentMethod,
          amount: widget.grandTotal,
          amountTendered: tendered,
          changeAmount: change,
          refNo: _refNoController.text.trim().isEmpty
              ? null
              : _refNoController.text.trim(),
        ),
      ];

      // Execute ACID sales transaction in Drift SQLite
      await posDao.createSaleTransaction(
        companyId: companyId,
        storeId: storeId,
        registerId: registerId,
        employeeId: DevicePrefs.currentEmployeeId,
        customerId: widget.customer?.id,
        cashManagementId: widget.shiftId,
        invoiceNo: invoiceNo,
        subtotal: widget.subtotal,
        discountTotal: widget.discountTotal,
        taxTotal: widget.taxTotal,
        grandTotal: widget.grandTotal,
        items: transactionItems,
        tenders: tenderPayments,
      );

      setState(() {
        _isProcessing = false;
        _isSuccess = true;
        _generatedInvoiceNo = invoiceNo;
        _finalChangeAmount = change;
      });

      widget.onSaleCompleted();
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shareReceipt() {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.transactionsReceipt,
    )) {
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln('          SALES RECEIPT         ');
    buffer.writeln('================================');
    buffer.writeln('Invoice: $_generatedInvoiceNo');
    buffer.writeln('Date: ${DateTime.now().toString().substring(0, 19)}');
    if (widget.customer != null) {
      buffer.writeln(
        'Customer: ${widget.customer!.fullName} (${widget.customer!.loyaltyTier})',
      );
    }
    buffer.writeln('--------------------------------');
    for (final item in widget.items) {
      buffer.writeln('${item.product.productName} x ${item.formattedQuantity}');
      buffer.writeln(
        '  @ ₱${item.unitPrice.toStringAsFixed(2)} = ₱${item.rawTotal.toStringAsFixed(2)}',
      );
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Subtotal:       ₱${widget.subtotal.toStringAsFixed(2)}');
    if (widget.discountTotal > 0) {
      buffer.writeln(
        'Discount:      -₱${widget.discountTotal.toStringAsFixed(2)}',
      );
    }
    if (widget.taxTotal > 0) {
      buffer.writeln('VAT / Tax:     +₱${widget.taxTotal.toStringAsFixed(2)}');
    }
    buffer.writeln('TOTAL DUE:      ₱${widget.grandTotal.toStringAsFixed(2)}');
    buffer.writeln('Payment:        ${_paymentMethod.toUpperCase()}');
    if (_paymentMethod == 'cash') {
      buffer.writeln('Tendered:       ₱${_amountTendered.toStringAsFixed(2)}');
      buffer.writeln(
        'Change:         ₱${_finalChangeAmount.toStringAsFixed(2)}',
      );
    }
    buffer.writeln('================================');
    buffer.writeln('      Thank you for shopping!   ');
    buffer.writeln('================================');

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Receipt $_generatedInvoiceNo',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isCompact = screenWidth < 500;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: 20,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: mediaQuery.size.height * 0.90,
        ),
        padding: const EdgeInsets.all(20),
        child: _isSuccess ? _buildReceiptView() : _buildPaymentForm(isCompact),
      ),
    );
  }

  Widget _buildPaymentForm(bool isCompact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.point_of_sale_rounded,
                  color: AppTheme.accentColor,
                  size: 24,
                ),
                SizedBox(width: 10),
                Text(
                  'Complete Sale',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Scrollable tender body
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grand Total Banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AMOUNT DUE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.items.length} item(s)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '₱${widget.grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.customer != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.accentColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Customer: ${widget.customer!.fullName} (${widget.customer!.loyaltyTier})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${widget.customer!.pointsBalance.toStringAsFixed(0)} pts',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor,
                              ),
                            ),
                            Text(
                              '+${(widget.subtotal / 100).floor()} pts to earn',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Payment Method Selector
                const Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    if (isNarrow) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              _buildPaymentMethodTile(
                                'cash',
                                'Cash',
                                Icons.payments_rounded,
                                AppTheme.accentColor,
                              ),
                              const SizedBox(width: 6),
                              _buildPaymentMethodTile(
                                'gcash',
                                'GCash',
                                Icons.account_balance_wallet_rounded,
                                const Color(0xFF007DFE),
                              ),
                              const SizedBox(width: 6),
                              _buildPaymentMethodTile(
                                'maya',
                                'Maya',
                                Icons.credit_card_rounded,
                                const Color(0xFF22C55E),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildPaymentMethodTile(
                                'card',
                                'Card',
                                Icons.credit_score_rounded,
                                const Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 6),
                              if (_canChargeCredit) ...[
                                _buildPaymentMethodTile(
                                  'credit',
                                  'Credit',
                                  Icons.account_balance_rounded,
                                  const Color(0xFFE11D48),
                                ),
                                const SizedBox(width: 6),
                                const Spacer(),
                              ] else ...[
                                const Spacer(),
                                const SizedBox(width: 6),
                                const Spacer(),
                              ],
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        _buildPaymentMethodTile(
                          'cash',
                          'Cash',
                          Icons.payments_rounded,
                          AppTheme.accentColor,
                        ),
                        const SizedBox(width: 6),
                        _buildPaymentMethodTile(
                          'gcash',
                          'GCash',
                          Icons.account_balance_wallet_rounded,
                          const Color(0xFF007DFE),
                        ),
                        const SizedBox(width: 6),
                        _buildPaymentMethodTile(
                          'maya',
                          'Maya',
                          Icons.credit_card_rounded,
                          const Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 6),
                        _buildPaymentMethodTile(
                          'card',
                          'Card',
                          Icons.credit_score_rounded,
                          const Color(0xFF6366F1),
                        ),
                        if (_canChargeCredit) ...[
                          const SizedBox(width: 6),
                          _buildPaymentMethodTile(
                            'credit',
                            'Credit',
                            Icons.account_balance_rounded,
                            const Color(0xFFE11D48),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Cash Specific Controls
                if (_paymentMethod == 'cash') ...[
                  // Tendered Input
                  const Text(
                    'Amount Tendered (₱)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const Key('amount_tendered_input'),
                    controller: _amountTenderedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _amountTenderedController.clear(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Bill Suggestions
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _getSuggestedBills().map((bill) {
                      final isExact = (bill - widget.grandTotal).abs() < 0.01;
                      return ActionChip(
                        key: Key('bill_chip_${bill.toInt()}'),
                        label: Text(
                          isExact
                              ? 'Exact (₱${bill.toStringAsFixed(2)})'
                              : '₱${bill.toStringAsFixed(0)}',
                        ),
                        backgroundColor: isExact
                            ? AppTheme.accentColor.withValues(alpha: 0.12)
                            : null,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isExact
                              ? AppTheme.accentColor
                              : Colors.black87,
                        ),
                        onPressed: () => _setCashBill(bill),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Change Due Banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _amountTendered >= widget.grandTotal
                          ? AppTheme.inStockBg
                          : AppTheme.outOfStockBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _amountTendered >= widget.grandTotal
                            ? AppTheme.inStockColor.withValues(alpha: 0.4)
                            : AppTheme.outOfStockColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _amountTendered >= widget.grandTotal
                              ? 'Change Due:'
                              : 'Insufficient Amount:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _amountTendered >= widget.grandTotal
                                ? AppTheme.inStockColor
                                : AppTheme.outOfStockColor,
                          ),
                        ),
                        Text(
                          _amountTendered >= widget.grandTotal
                              ? '₱${_changeAmount.toStringAsFixed(2)}'
                              : '-₱${(widget.grandTotal - _amountTendered).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _amountTendered >= widget.grandTotal
                                ? AppTheme.inStockColor
                                : AppTheme.outOfStockColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_paymentMethod == 'credit') ...[
                  // Store Credit Specific Controls
                  Container(
                    key: const Key('credit_account_info_box'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.grandTotal <= _availableCredit
                          ? const Color(0xFFE11D48).withValues(alpha: 0.08)
                          : AppTheme.outOfStockBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.grandTotal <= _availableCredit
                            ? const Color(0xFFE11D48).withValues(alpha: 0.3)
                            : AppTheme.outOfStockColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.grandTotal <= _availableCredit
                                  ? Icons.account_balance_rounded
                                  : Icons.warning_amber_rounded,
                              color: widget.grandTotal <= _availableCredit
                                  ? const Color(0xFFE11D48)
                                  : AppTheme.outOfStockColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Customer Store Credit Account',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: widget.grandTotal <= _availableCredit
                                    ? const Color(0xFFE11D48)
                                    : AppTheme.outOfStockColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Credit Limit:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              '₱${widget.customer!.creditLimit.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Current Outstanding Due:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              '₱${widget.customer!.dueAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Available Credit Balance:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              '₱${_availableCredit.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _availableCredit >= widget.grandTotal
                                    ? Colors.green.shade700
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 14),
                        if (widget.grandTotal > _availableCredit)
                          Text(
                            '⚠️ Cannot proceed: Order total (₱${widget.grandTotal.toStringAsFixed(2)}) exceeds customer\'s remaining credit of ₱${_availableCredit.toStringAsFixed(2)}.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'New Due After Purchase:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₱${(widget.customer!.dueAmount + widget.grandTotal).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE11D48),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PO Number / Credit Auth Note (Optional)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const Key('credit_ref_no_input'),
                    controller: _refNoController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. PO-8849 or Authorized by Store Manager',
                      prefixIcon: Icon(Icons.description_outlined, size: 20),
                    ),
                  ),
                ] else ...[
                  // Digital Wallet / Card Reference Number
                  const Text(
                    'Reference / Auth Number (Optional)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const Key('ref_no_input'),
                    controller: _refNoController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 10928340192',
                      prefixIcon: Icon(Icons.tag_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ask customer to scan dynamic QR code or tap terminal, then enter transaction reference.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.blue.shade900,
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
        ),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                key: const Key('confirm_payment_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _canSubmit ? _processCheckout : null,
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Complete Payment',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodTile(
    String id,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _paymentMethod == id;
    return Expanded(
      child: InkWell(
        key: Key('payment_method_$id'),
        onTap: () => setState(() => _paymentMethod = id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.12)
                : AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : AppTheme.cardBorderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? color : Colors.black54, size: 20),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? color : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success Header
        const Center(
          child: CircleAvatar(
            radius: 30,
            backgroundColor: AppTheme.inStockBg,
            child: Icon(
              Icons.check_circle_rounded,
              color: AppTheme.inStockColor,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Payment Successful!',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
        Center(
          child: Text(
            _generatedInvoiceNo,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Receipt Summary Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Column(
            children: [
              _buildReceiptRow(
                'Payment Method',
                _paymentMethod == 'credit'
                    ? 'STORE CREDIT (ON ACCOUNT)'
                    : _paymentMethod.toUpperCase(),
              ),
              if (_paymentMethod == 'credit' && widget.customer != null) ...[
                _buildReceiptRow('Charged To', widget.customer!.fullName),
                _buildReceiptRow(
                  'New Due Balance',
                  '₱${(widget.customer!.dueAmount + widget.grandTotal).toStringAsFixed(2)}',
                  isHighlight: true,
                ),
              ],
              const Divider(height: 14),
              _buildReceiptRow(
                'Subtotal',
                '₱${widget.subtotal.toStringAsFixed(2)}',
              ),
              if (widget.discountTotal > 0)
                _buildReceiptRow(
                  'Discounts',
                  '-₱${widget.discountTotal.toStringAsFixed(2)}',
                ),
              if (widget.taxTotal > 0)
                _buildReceiptRow(
                  'VAT / Tax',
                  '+₱${widget.taxTotal.toStringAsFixed(2)}',
                ),
              const Divider(height: 14),
              _buildReceiptRow(
                'Grand Total',
                '₱${widget.grandTotal.toStringAsFixed(2)}',
                isBold: true,
              ),
              if (_paymentMethod == 'cash') ...[
                _buildReceiptRow(
                  'Cash Tendered',
                  '₱${_amountTendered.toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  'Change',
                  '₱${_finalChangeAmount.toStringAsFixed(2)}',
                  isHighlight: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Actions: Share Receipt & Start Next Sale
        Builder(
          builder: (context) {
            final hasReceipt = PermissionService.instance.hasPermission(
              PosPermissions.transactionsReceipt,
            );
            return Row(
              children: [
                if (hasReceipt) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('share_receipt_button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share Receipt',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _shareReceipt,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: hasReceipt ? 2 : 1,
                  child: ElevatedButton.icon(
                    key: const Key('next_sale_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: const Text(
                      'Start Next Sale',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isBold = false,
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isHighlight ? AppTheme.inStockColor : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isHighlight || isBold ? 14 : 12.5,
                fontWeight: isBold || isHighlight
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isHighlight
                    ? AppTheme.inStockColor
                    : AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
