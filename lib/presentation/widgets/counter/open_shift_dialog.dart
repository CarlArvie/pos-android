import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../../core/device_prefs.dart';
import '../../theme/app_theme.dart';

/// Modal dialog to open a cash register shift with an initial cash drawer float
class OpenShiftDialog extends StatefulWidget {
  final AppDatabase db;
  final String companyId;
  final String storeId;
  final String registerId;
  final String registerName;
  final VoidCallback onShiftOpened;

  const OpenShiftDialog({
    super.key,
    required this.db,
    this.companyId = 'default-company-001',
    this.storeId = 'default-store-001',
    this.registerId = 'default-reg-001',
    this.registerName = 'Main Checkout #1',
    required this.onShiftOpened,
  });

  @override
  State<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<OpenShiftDialog> {
  final _floatController = TextEditingController(text: '1000.00');
  final _notesController = TextEditingController();
  bool _isOpening = false;

  @override
  void dispose() {
    _floatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _openingFloat => double.tryParse(_floatController.text.trim()) ?? 0.0;

  void _setFloatPreset(double amount) {
    setState(() {
      _floatController.text = amount.toStringAsFixed(2);
    });
  }

  Future<void> _handleOpenShift() async {
    if (_openingFloat < 0) return;
    setState(() => _isOpening = true);

    try {
      final posDao = PosDao(widget.db);
      await posDao.openCashShift(
        companyId: widget.companyId,
        storeId: widget.storeId,
        registerId: widget.registerId,
        employeeId: DevicePrefs.currentEmployeeId,
        openingBalance: _openingFloat,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onShiftOpened();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shift opened with ₱${_openingFloat.toStringAsFixed(2)} starting float.'),
            backgroundColor: AppTheme.inStockColor,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOpening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open shift: $e'),
            backgroundColor: AppTheme.outOfStockColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(18),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Open Cash Shift',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          widget.registerName,
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Form Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Starting Drawer Float (Cash)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Count opening coins and bills placed in the cash drawer.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),

                  // Amount input
                  TextField(
                    key: const Key('opening_float_input'),
                    controller: _floatController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.cardBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.cardBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick Float Presets
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [500.0, 1000.0, 2000.0, 5000.0].map((amount) {
                      final isSelected = _openingFloat == amount;
                      return ChoiceChip(
                        key: Key('preset_float_${amount.toInt()}'),
                        label: Text('₱${amount.toInt()}'),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppTheme.primaryColor,
                        ),
                        selected: isSelected,
                        selectedColor: AppTheme.accentColor,
                        backgroundColor: AppTheme.backgroundColor,
                        onSelected: (selected) {
                          if (selected) _setFloatPreset(amount);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Opening Notes
                  TextField(
                    key: const Key('open_shift_notes_input'),
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Opening Notes (Optional)',
                      hintText: 'e.g. Clean drawer, morning shift...',
                      labelStyle: const TextStyle(fontSize: 12),
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.cardBorderColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  ElevatedButton(
                    key: const Key('confirm_open_shift_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _isOpening ? null : _handleOpenShift,
                    child: _isOpening
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Open Drawer & Start Shift',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
