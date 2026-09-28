import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Numpad dialog for overriding a cart item's unit price.
/// Returns the new price as [double], or null if cancelled.
class PriceOverrideDialog extends StatefulWidget {
  final String productName;
  final double currentPrice;

  const PriceOverrideDialog({
    super.key,
    required this.productName,
    required this.currentPrice,
  });

  @override
  State<PriceOverrideDialog> createState() => _PriceOverrideDialogState();
}

class _PriceOverrideDialogState extends State<PriceOverrideDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.currentPrice.toStringAsFixed(2);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _parsedPrice => double.tryParse(_controller.text.trim());
  bool get _isValid => _parsedPrice != null && _parsedPrice! > 0;

  void _onNumpad(String char) {
    final current = _controller.text;
    if (char == 'C') {
      _controller.text = '';
      return;
    }
    if (char == '⌫') {
      if (current.isNotEmpty) {
        _controller.text = current.substring(0, current.length - 1);
        _controller.selection =
            TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
      }
      return;
    }
    if (char == '.') {
      if (current.contains('.')) return;
    }
    // Limit to 2 decimal places
    if (current.contains('.')) {
      final parts = current.split('.');
      if (parts.length > 1 && parts[1].length >= 2) return;
    }
    _controller.text = current + char;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
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
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_rounded, color: AppTheme.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Price Override',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          widget.productName,
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Original price
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Original Price:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    Text(
                      '₱${widget.currentPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Price input display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isValid ? AppTheme.accentColor : AppTheme.cardBorderColor,
                    width: _isValid ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '₱ ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _controller.text.isEmpty ? '0.00' : _controller.text,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _controller.text.isEmpty ? Colors.grey.shade300 : AppTheme.primaryColor,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Numpad
              _buildNumpad(),
              const SizedBox(height: 14),

              // Action Buttons
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
                      key: const Key('confirm_price_override_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isValid ? () => Navigator.pop(context, _parsedPrice) : null,
                      child: const Text(
                        'Set New Price',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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

  Widget _buildNumpad() {
    const keys = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '⌫'],
    ];
    return Column(
      children: [
        ...keys.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: row.map((key) {
                  final isBack = key == '⌫';
                  final isClear = key == 'C';
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Material(
                        color: isBack
                            ? AppTheme.outOfStockBg
                            : isClear
                                ? Colors.amber.shade50
                                : AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          key: Key('numpad_key_$key'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _onNumpad(key),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.cardBorderColor),
                            ),
                            child: Text(
                              key,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isBack
                                    ? AppTheme.outOfStockColor
                                    : AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('numpad_key_clear'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => _onNumpad('C'),
              child: Container(
                width: double.infinity,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
