import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../../core/device_prefs.dart';
import '../../theme/app_theme.dart';

class SettleCreditDialog extends StatefulWidget {
  final AppDatabase db;
  final Customer customer;

  const SettleCreditDialog({
    super.key,
    required this.db,
    required this.customer,
  });

  @override
  State<SettleCreditDialog> createState() => _SettleCreditDialogState();
}

class _SettleCreditDialogState extends State<SettleCreditDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _paymentMethod = 'cash'; // cash, gcash, maya, bank_transfer
  bool _isProcessing = false;

  final List<({String id, String label, IconData icon, Color color})> _paymentMethods = [
    (id: 'cash', label: 'Cash', icon: Icons.payments_rounded, color: AppTheme.accentColor),
    (id: 'gcash', label: 'GCash', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF007DFE)),
    (id: 'maya', label: 'Maya', icon: Icons.credit_card_rounded, color: const Color(0xFF22C55E)),
    (id: 'bank_transfer', label: 'Bank', icon: Icons.account_balance_rounded, color: const Color(0xFF6366F1)),
  ];

  @override
  void initState() {
    super.initState();
    // Default to paying full outstanding due amount
    _amountController.text = widget.customer.dueAmount.toStringAsFixed(2);
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _enteredAmount {
    return double.tryParse(_amountController.text.trim()) ?? 0.0;
  }

  double get _remainingDue {
    final rem = widget.customer.dueAmount - _enteredAmount;
    return rem >= 0 ? rem : 0.0;
  }

  List<double> _getQuickAmounts() {
    final due = widget.customer.dueAmount;
    final List<double> list = [due]; // Full payoff

    const presetAmounts = [200.0, 500.0, 1000.0, 2000.0, 5000.0];
    for (final p in presetAmounts) {
      if (p < due && !list.contains(p)) {
        list.add(p);
      }
    }
    list.sort();
    return list;
  }

  Future<void> _submitSettlement() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _enteredAmount;
    if (amount <= 0) return;

    setState(() => _isProcessing = true);

    try {
      final companies = await widget.db.select(widget.db.companies).get();
      final stores = await widget.db.select(widget.db.stores).get();

      final companyId = DevicePrefs.companyId ??
          (companies.isNotEmpty ? companies.first.id : widget.customer.companyId);
      final storeId = DevicePrefs.storeId ?? (stores.isNotEmpty ? stores.first.id : null);

      final posDao = PosDao(widget.db);
      await posDao.recordCustomerPayment(
        companyId: companyId,
        storeId: storeId,
        customerId: widget.customer.id,
        amount: amount,
        paymentMethod: _paymentMethod,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.inStockColor,
            content: Text(
              'Payment of ₱${amount.toStringAsFixed(2)} recorded for ${widget.customer.fullName}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to record payment: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isCompact = mediaQuery.size.width < 500;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settle Credit Balance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Record payment against outstanding debt',
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer Debt Summary Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15),
                                  child: Text(
                                    widget.customer.fullName.isNotEmpty
                                        ? widget.customer.fullName[0].toUpperCase()
                                        : 'C',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.customer.fullName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                      if (widget.customer.phone != null && widget.customer.phone!.isNotEmpty)
                                        Text(
                                          widget.customer.phone!,
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'TOTAL DUE',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                                      ),
                                      Text(
                                        '₱${widget.customer.dueAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Credit Limit: ₱${widget.customer.creditLimit.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'Loyalty Tier: ${widget.customer.loyaltyTier}',
                                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Payment Amount
                      const Text(
                        'Payment Amount (₱) *',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('settle_amount_input'),
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        decoration: InputDecoration(
                          prefixText: '₱ ',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _amountController.clear(),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter payment amount';
                          final numVal = double.tryParse(val.trim());
                          if (numVal == null || numVal <= 0) return 'Enter a valid amount greater than 0';
                          if (numVal > widget.customer.dueAmount) {
                            return 'Amount cannot exceed total due of ₱${widget.customer.dueAmount.toStringAsFixed(2)}';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),

                      // Quick Payment Suggestions
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _getQuickAmounts().map((amount) {
                          final isFull = (amount - widget.customer.dueAmount).abs() < 0.01;
                          final isSelected = (_enteredAmount - amount).abs() < 0.01;
                          return ActionChip(
                            key: Key('quick_settle_${amount.toInt()}'),
                            label: Text(
                              isFull ? 'Pay Full (₱${amount.toStringAsFixed(2)})' : '₱${amount.toStringAsFixed(0)}',
                            ),
                            backgroundColor: isSelected
                                ? AppTheme.accentColor.withValues(alpha: 0.15)
                                : isFull
                                    ? Colors.red.shade50
                                    : null,
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? AppTheme.accentColor
                                  : isFull
                                      ? Colors.red.shade700
                                      : Colors.black87,
                            ),
                            onPressed: () {
                              setState(() {
                                _amountController.text = amount.toStringAsFixed(2);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Payment Method Selector
                      const Text(
                        'Payment Method',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: _paymentMethods.map((m) {
                          final isSelected = _paymentMethod == m.id;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                key: Key('settle_method_${m.id}'),
                                onTap: () => setState(() => _paymentMethod = m.id),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected ? m.color.withValues(alpha: 0.12) : AppTheme.backgroundColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? m.color : AppTheme.cardBorderColor,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(m.icon, color: isSelected ? m.color : Colors.black54, size: 20),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          m.label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? m.color : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Notes / Reference Input
                      const Text(
                        'Reference / Notes (Optional)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('settle_notes_input'),
                        controller: _notesController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Official Receipt #4091 or Cheque Ref',
                          prefixIcon: Icon(Icons.notes_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Balance Impact Summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.inStockBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.inStockColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Remaining Due Balance:',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.inStockColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '₱${_remainingDue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.inStockColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
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
                      child: ElevatedButton.icon(
                        key: const Key('settle_submit_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _isProcessing ? 'Processing...' : 'Confirm Settlement',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isProcessing ? null : _submitSettlement,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
