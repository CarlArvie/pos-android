import 'package:flutter/material.dart';
import '../../../core/device_prefs.dart';
import '../../models/discount_preset.dart';
import '../../theme/app_theme.dart';

/// Result of a custom discount selection
class CustomDiscountResult {
  final double amount; // resolved ₱ amount to deduct
  final String type; // 'percent' or 'fixed'
  final double inputValue; // the raw user input (15 for 15%, 50 for ₱50)

  const CustomDiscountResult({
    required this.amount,
    required this.type,
    required this.inputValue,
  });
}

/// Dialog for applying a custom discount (percentage or fixed amount) to the cart.
/// Also exposes the Senior/PWD 20% preset as a quick shortcut.
/// Returns [CustomDiscountResult] or null if cancelled.
class CustomDiscountDialog extends StatefulWidget {
  final double cartSubtotal;
  final bool hasSeniorPwdPreset;

  const CustomDiscountDialog({
    super.key,
    required this.cartSubtotal,
    this.hasSeniorPwdPreset = true,
  });

  @override
  State<CustomDiscountDialog> createState() => _CustomDiscountDialogState();
}

class _CustomDiscountDialogState extends State<CustomDiscountDialog> {
  String _mode = 'percent'; // 'percent' or 'fixed'
  final TextEditingController _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _valueController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  double? get _inputValue => double.tryParse(_valueController.text.trim());

  double get _seniorPwdRate => DevicePrefs.seniorPwdDiscountPercent;
  double get _maxCustomPercent => DevicePrefs.maxCustomDiscountPercent;
  List<DiscountPreset> get _otherPresets =>
      DevicePrefs.discountPresets.where((p) => !p.isSystem).toList();

  bool get _isExceedingMaxCap =>
      _mode == 'percent' && (_inputValue ?? 0.0) > _maxCustomPercent;

  double get _resolvedAmount {
    final v = _inputValue;
    if (v == null || v <= 0) return 0.0;
    if (_mode == 'percent') {
      final pct = v.clamp(0.0, 100.0);
      return widget.cartSubtotal * (pct / 100.0);
    } else {
      return v.clamp(0.0, widget.cartSubtotal);
    }
  }

  bool get _isValid =>
      _inputValue != null &&
      _inputValue! > 0 &&
      _resolvedAmount > 0 &&
      !_isExceedingMaxCap;

  void _applySeniorPwd() {
    Navigator.pop(
      context,
      CustomDiscountResult(
        amount: widget.cartSubtotal * (_seniorPwdRate / 100.0),
        type: 'percent',
        inputValue: _seniorPwdRate,
      ),
    );
  }

  void _applyPreset(DiscountPreset preset) {
    Navigator.pop(
      context,
      CustomDiscountResult(
        amount: widget.cartSubtotal * (preset.percent / 100.0),
        type: 'percent',
        inputValue: preset.percent,
      ),
    );
  }

  void _applyCustom() {
    if (!_isValid) return;
    Navigator.pop(
      context,
      CustomDiscountResult(
        amount: _resolvedAmount,
        type: _mode,
        inputValue: _inputValue!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
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
                    child: const Icon(Icons.discount_rounded, color: AppTheme.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Apply Discount',
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

              // Subtotal reference
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
                    const Text('Cart Subtotal:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '₱${widget.cartSubtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Quick Preset: Senior / PWD
              if (widget.hasSeniorPwdPreset) ...[
                InkWell(
                  key: const Key('senior_pwd_preset_button'),
                  onTap: _applySeniorPwd,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.accessibility_new_rounded, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Senior Citizen / PWD — ${_seniorPwdRate.toStringAsFixed(0)}% Off',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              Text(
                                '-₱${(widget.cartSubtotal * (_seniorPwdRate / 100.0)).toStringAsFixed(2)} deducted',
                                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade700),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.amber.shade700, size: 20),
                      ],
                    ),
                  ),
                ),
                if (_otherPresets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _otherPresets.map((p) {
                      return ActionChip(
                        key: Key('preset_chip_${p.id}'),
                        avatar: const Icon(Icons.bookmark_outline_rounded, size: 14, color: AppTheme.primaryColor),
                        label: Text('${p.label} (${p.percent.toStringAsFixed(0)}%)'),
                        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _applyPreset(p),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppTheme.cardBorderColor)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'or enter custom amount',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppTheme.cardBorderColor)),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Mode Toggle: % / ₱
              Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      key: const Key('discount_mode_percent'),
                      label: '% Percentage',
                      icon: Icons.percent_rounded,
                      mode: 'percent',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModeButton(
                      key: const Key('discount_mode_fixed'),
                      label: '₱ Fixed Amount',
                      icon: Icons.money_rounded,
                      mode: 'fixed',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Value Input
              TextFormField(
                key: const Key('discount_value_input'),
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: _mode == 'fixed' ? '₱ ' : '',
                  suffixText: _mode == 'percent' ? '%' : '',
                  hintText: _mode == 'percent' ? '0.0' : '0.00',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: _valueController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _valueController.clear(),
                        )
                      : null,
                ),
              ),

              // Cap warning banner
              if (_isExceedingMaxCap) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('discount_exceed_cap_warning'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Exceeds maximum limit of ${_maxCustomPercent.toStringAsFixed(0)}% set by Admin.',
                          style: TextStyle(fontSize: 11.5, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Preview banner
              if (_isValid) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.inStockBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Discount Amount:',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.inStockColor),
                      ),
                      Text(
                        '-₱${_resolvedAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.inStockColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

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
                      key: const Key('apply_custom_discount_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isValid ? _applyCustom : null,
                      child: const Text(
                        'Apply Discount',
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

  Widget _buildModeButton({required Key key, required String label, required IconData icon, required String mode}) {
    final isSelected = _mode == mode;
    return InkWell(
      key: key,
      onTap: () {
        setState(() {
          _mode = mode;
          _valueController.clear();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentColor.withValues(alpha: 0.1) : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : AppTheme.cardBorderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accentColor : Colors.black54),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.accentColor : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
