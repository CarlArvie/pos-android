import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Quick quantity input dialog. Shows a numpad to directly enter a quantity.
/// [isDecimal] — true for weighed/fractional items (kg), false for unit items.
/// Returns the new quantity as [double], or null if cancelled.
class QuantityInputDialog extends StatefulWidget {
  final String productName;
  final double currentQuantity;
  final bool isDecimal;
  final String unit;

  const QuantityInputDialog({
    super.key,
    required this.productName,
    required this.currentQuantity,
    this.isDecimal = false,
    this.unit = 'pcs',
  });

  @override
  State<QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<QuantityInputDialog> {
  String _input = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill with current quantity
    if (widget.isDecimal) {
      _input = widget.currentQuantity.toStringAsFixed(3);
    } else {
      _input = widget.currentQuantity.toInt().toString();
    }
  }

  double? get _parsedQty {
    final v = double.tryParse(_input);
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _isValid => _parsedQty != null;

  void _onKey(String key) {
    setState(() {
      if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        return;
      }
      if (key == 'C') {
        _input = '';
        return;
      }
      if (key == '.') {
        if (!widget.isDecimal) return; // no decimals for unit items
        if (_input.contains('.')) return;
      }
      // Limit decimal to 3 places
      if (_input.contains('.')) {
        final parts = _input.split('.');
        if (parts.length > 1 && parts[1].length >= 3) return;
      }
      _input = _input + key;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
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
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.pin_rounded, color: AppTheme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Set Quantity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          Text(
                            widget.productName,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isValid ? AppTheme.accentColor : AppTheme.cardBorderColor,
                      width: _isValid ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _input.isEmpty ? '0' : _input,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _input.isEmpty ? Colors.grey.shade300 : AppTheme.primaryColor,
                        ),
                      ),
                      Text(
                        widget.unit,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Numpad
                ...[
                  ['7', '8', '9'],
                  ['4', '5', '6'],
                  ['1', '2', '3'],
                  [widget.isDecimal ? '.' : '00', '0', '⌫'],
                ].map((row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: row.map((key) {
                          final isBack = key == '⌫';
                          Color bg = AppTheme.backgroundColor;
                          Color fg = AppTheme.primaryColor;
                          if (isBack) {
                            bg = AppTheme.outOfStockBg;
                            fg = AppTheme.outOfStockColor;
                          }
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Material(
                                color: bg,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  key: Key('qty_numpad_$key'),
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _onKey(key),
                                  child: Container(
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.cardBorderColor),
                                    ),
                                    child: Text(
                                      key,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: fg,
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

                // Clear button
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 3, right: 3),
                  child: Material(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      key: const Key('qty_numpad_C'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _onKey('C'),
                      child: Container(
                        width: double.infinity,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
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

                // Confirm
                ElevatedButton(
                  key: const Key('confirm_quantity_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isValid ? () => Navigator.pop(context, _parsedQty) : null,
                  child: const Text(
                    'Set Quantity',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
