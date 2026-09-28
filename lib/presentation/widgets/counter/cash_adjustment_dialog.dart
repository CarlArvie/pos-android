import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Mid-shift cash drawer adjustment dialog — records a Pay In or Pay Out.
/// Returns a [CashAdjustmentResult] or null if cancelled.
class CashAdjustmentResult {
  final String type; // 'pay_in' or 'pay_out'
  final double amount;
  final String reason;

  const CashAdjustmentResult({
    required this.type,
    required this.amount,
    required this.reason,
  });
}

class CashAdjustmentDialog extends StatefulWidget {
  final String initialType; // 'pay_in' or 'pay_out'

  const CashAdjustmentDialog({
    super.key,
    this.initialType = 'pay_in',
  });

  @override
  State<CashAdjustmentDialog> createState() => _CashAdjustmentDialogState();
}

class _CashAdjustmentDialogState extends State<CashAdjustmentDialog> {
  late String _type;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  static const _payInReasons = [
    'Change Fund Added',
    'Loan from Office',
    'Petty Cash Replenishment',
    'Other',
  ];

  static const _payOutReasons = [
    'Delivery Driver Tip',
    'Office Expense',
    'Supplier Payment',
    'Petty Cash Withdrawal',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _amountController.addListener(() => setState(() {}));
    _reasonController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountController.text.trim());
  bool get _isValid => _amount != null && _amount! > 0 && _reasonController.text.trim().isNotEmpty;

  List<String> get _reasonSuggestions => _type == 'pay_in' ? _payInReasons : _payOutReasons;

  @override
  Widget build(BuildContext context) {
    final isPayIn = _type == 'pay_in';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isPayIn ? Colors.green : Colors.red).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPayIn ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                      color: isPayIn ? Colors.green.shade700 : Colors.red.shade700,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cash Drawer Adjustment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Type Toggle
              Row(
                children: [
                  Expanded(
                    child: _buildTypeButton(
                      key: const Key('pay_in_tab'),
                      label: 'Pay In',
                      icon: Icons.add_circle_rounded,
                      type: 'pay_in',
                      activeColor: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTypeButton(
                      key: const Key('pay_out_tab'),
                      label: 'Pay Out',
                      icon: Icons.remove_circle_rounded,
                      type: 'pay_out',
                      activeColor: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPayIn ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPayIn
                      ? 'Adding cash to the drawer (e.g. change fund, petty cash replenishment).'
                      : 'Removing cash from the drawer (e.g. delivery tip, office expense).',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPayIn ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Amount
              const Text(
                'Amount (₱)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('cash_adjustment_amount_input'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  hintText: '0.00',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: _amountController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _amountController.clear(),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 14),

              // Reason
              const Text(
                'Reason',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _reasonSuggestions.map((r) {
                  final isSelected = _reasonController.text == r;
                  return ActionChip(
                    key: Key('reason_chip_${r.replaceAll(' ', '_')}'),
                    label: Text(r, style: TextStyle(fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    backgroundColor: isSelected ? AppTheme.accentColor.withValues(alpha: 0.12) : null,
                    labelStyle: TextStyle(color: isSelected ? AppTheme.accentColor : Colors.black87),
                    onPressed: () => setState(() => _reasonController.text = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('cash_adjustment_reason_input'),
                controller: _reasonController,
                decoration: const InputDecoration(
                  hintText: 'Enter or type custom reason...',
                  hintStyle: TextStyle(fontSize: 12),
                  prefixIcon: Icon(Icons.notes_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 16),

              // Action
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      key: const Key('confirm_cash_adjustment_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPayIn ? Colors.green.shade700 : Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isValid
                          ? () => Navigator.pop(
                                context,
                                CashAdjustmentResult(
                                  type: _type,
                                  amount: _amount!,
                                  reason: _reasonController.text.trim(),
                                ),
                              )
                          : null,
                      child: Text(
                        isPayIn ? 'Record Pay In' : 'Record Pay Out',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildTypeButton({
    required Key key,
    required String label,
    required IconData icon,
    required String type,
    required Color activeColor,
  }) {
    final isSelected = _type == type;
    return InkWell(
      key: key,
      onTap: () => setState(() {
        _type = type;
        _reasonController.clear();
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.cardBorderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? activeColor : Colors.black54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? activeColor : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
