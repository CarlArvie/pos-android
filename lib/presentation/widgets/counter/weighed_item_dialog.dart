import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../theme/app_theme.dart';

class WeighedItemDialog extends StatefulWidget {
  final Product product;
  final double initialWeight;

  const WeighedItemDialog({
    super.key,
    required this.product,
    this.initialWeight = 1.0,
  });

  @override
  State<WeighedItemDialog> createState() => _WeighedItemDialogState();
}

class _WeighedItemDialogState extends State<WeighedItemDialog> {
  late final TextEditingController _weightController;
  bool _isInGrams = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.initialWeight > 0
          ? widget.initialWeight.toStringAsFixed(3)
          : '1.000',
    );
    _weightController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  double get _currentWeightInKg {
    final val = double.tryParse(_weightController.text.trim()) ?? 0.0;
    return _isInGrams ? (val / 1000.0) : val;
  }

  double get _computedTotal {
    return _currentWeightInKg * widget.product.price;
  }

  void _setPreset(double weightInKg) {
    setState(() {
      if (_isInGrams) {
        _weightController.text = (weightInKg * 1000).toStringAsFixed(0);
      } else {
        _weightController.text = weightInKg.toStringAsFixed(3);
      }
    });
  }

  void _toggleUnit(bool toGrams) {
    if (_isInGrams == toGrams) return;
    final curr = double.tryParse(_weightController.text.trim()) ?? 0.0;
    setState(() {
      _isInGrams = toGrams;
      if (_isInGrams) {
        // Convert kg to grams
        _weightController.text = (curr * 1000.0).toStringAsFixed(0);
      } else {
        // Convert grams to kg
        _weightController.text = (curr / 1000.0).toStringAsFixed(3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isCompact = mediaQuery.size.width < 420;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 24,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.scale_rounded, color: AppTheme.accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.productName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₱${widget.product.price.toStringAsFixed(2)} / ${widget.product.unit}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentColor,
                        ),
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
            const SizedBox(height: 16),

            // Unit Segmented Switch (kg vs g)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [
                ChoiceChip(
                  key: const Key('unit_chip_kg'),
                  label: const Text('kg'),
                  selected: !_isInGrams,
                  onSelected: (selected) {
                    if (selected) _toggleUnit(false);
                  },
                ),
                ChoiceChip(
                  key: const Key('unit_chip_g'),
                  label: const Text('grams'),
                  selected: _isInGrams,
                  onSelected: (selected) {
                    if (selected) _toggleUnit(true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Weight Input Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('scale_weight_input'),
                      controller: _weightController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '0.000',
                      ),
                    ),
                  ),
                  Text(
                    _isInGrams ? 'grams' : 'kg',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quick Weight Presets
            const Text(
              'Quick Presets:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetButton(0.250, '250g'),
                _buildPresetButton(0.500, '500g'),
                _buildPresetButton(0.750, '750g'),
                _buildPresetButton(1.000, '1.0 kg'),
                _buildPresetButton(1.500, '1.5 kg'),
                _buildPresetButton(2.000, '2.0 kg'),
              ],
            ),
            const SizedBox(height: 16),

            // Live Price Calculation Preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Subtotal (${_currentWeightInKg.toStringAsFixed(3)} kg):',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${_computedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ],
              ),
            ),
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
                    key: const Key('confirm_weighed_item_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _currentWeightInKg > 0
                        ? () => Navigator.pop(context, _currentWeightInKg)
                        : null,
                    child: const Text(
                      'Add to Cart',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(double weightKg, String label) {
    return ActionChip(
      key: Key('preset_${label.replaceAll(' ', '_')}'),
      label: Text(label),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
      onPressed: () => _setPreset(weightKg),
    );
  }
}
