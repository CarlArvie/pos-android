import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../theme/app_theme.dart';

/// Modal dialog to close a cash register shift with cash drawer balancing and reconciliation
class CloseShiftDialog extends StatefulWidget {
  final AppDatabase db;
  final CashManagement shift;
  final String registerName;
  final VoidCallback onShiftClosed;

  const CloseShiftDialog({
    super.key,
    required this.db,
    required this.shift,
    this.registerName = 'Main Checkout #1',
    required this.onShiftClosed,
  });

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  final _actualCashController = TextEditingController();
  final _notesController = TextEditingController();

  ShiftSalesSummary? _summary;
  bool _isLoading = true;
  bool _isClosing = false;

  bool get _isBlindClose {
    final role = DevicePrefs.currentEmployeeRole ?? '';
    // Admins and Store Managers always see expected drawer balance and variance
    if (role.toLowerCase() == 'admin' ||
        role.toLowerCase() == 'store manager' ||
        role.toLowerCase() == 'manager') {
      return false;
    }
    return PermissionService.instance.hasPermission(PosPermissions.posShiftBlindClose);
  }

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _actualCashController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _actualCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final posDao = PosDao(widget.db);
      final summary = await posDao.getShiftSalesSummary(widget.shift.id);
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
          // Only pre-fill actual cash with expected cash if NOT blind close
          if (!_isBlindClose) {
            _actualCashController.text = summary.expectedBalance.toStringAsFixed(2);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double get _actualCash => double.tryParse(_actualCashController.text.trim()) ?? 0.0;
  double get _expectedCash => _summary?.expectedBalance ?? widget.shift.openingBalance;
  double get _variance => _actualCash - _expectedCash;

  Future<void> _handleCloseShift() async {
    setState(() => _isClosing = true);
    try {
      final posDao = PosDao(widget.db);
      await posDao.closeCashShift(
        shiftId: widget.shift.id,
        closingBalance: _actualCash,
        expectedBalance: _expectedCash,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onShiftClosed();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shift closed successfully. Closing cash: ₱${_actualCash.toStringAsFixed(2)}.'),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClosing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to close shift: $e'),
            backgroundColor: AppTheme.outOfStockColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.shift.openTime;
    final hour = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = t.minute.toString().padLeft(2, '0');
    final openedStr = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} • $hour:$minuteStr $ampm';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
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
        child: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
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
                          child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Shift Reconciliation & Close',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                '${widget.registerName} • Started $openedStr',
                                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.8)),
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

                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Financial Summary Grid
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cardBorderColor),
                            ),
                            child: Column(
                              children: [
                                _buildSummaryRow('Opening Cash Float', '₱${widget.shift.openingBalance.toStringAsFixed(2)}'),
                                const SizedBox(height: 6),
                                _buildSummaryRow('Cash Sales', '+₱${(_summary?.cashSales ?? 0.0).toStringAsFixed(2)}'),
                                const SizedBox(height: 6),
                                _buildSummaryRow('Digital Sales (GCash/Maya/Card)', '₱${(_summary?.nonCashSales ?? 0.0).toStringAsFixed(2)}'),
                                const SizedBox(height: 6),
                                _buildSummaryRow('Total Transactions', '${_summary?.transactionCount ?? 0} orders'),
                                if (!_isBlindClose) ...[
                                  const Divider(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Expected Cash in Drawer',
                                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '₱${_expectedCash.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  const Divider(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility_off_rounded, size: 16, color: Colors.blue.shade800),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Blind Count Active: Expected totals hidden for security.',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
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

                          // Actual Cash Count Input
                          Text(
                            _isBlindClose ? 'Counted Cash in Drawer' : 'Actual Counted Cash',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isBlindClose
                                ? 'Count all physical bills and coins in the drawer and enter the total below.'
                                : 'Count physical bills and coins currently in the drawer and enter below.',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 10),

                          TextField(
                            key: const Key('actual_closing_cash_input'),
                            controller: _actualCashController,
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

                          // Variance Banner (Only shown if NOT blind close)
                          if (!_isBlindClose) ...[
                            _buildVarianceBanner(),
                            const SizedBox(height: 14),
                          ],

                          // Closing Notes
                          TextField(
                            key: const Key('close_shift_notes_input'),
                            controller: _notesController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Closing Notes (Optional)',
                              hintText: 'e.g. End of morning shift, verified drawer count...',
                              labelStyle: const TextStyle(fontSize: 12),
                              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppTheme.cardBorderColor),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Close Shift Action
                          ElevatedButton(
                            key: const Key('confirm_close_shift_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            onPressed: _isClosing ? null : _handleCloseShift,
                            child: _isClosing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Confirm & Close Shift',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
      ],
    );
  }

  Widget _buildVarianceBanner() {
    final diff = _variance;
    final isBalanced = diff.abs() < 0.01;
    final isOver = diff > 0.01;

    final Color bgColor = isBalanced
        ? AppTheme.inStockBg
        : isOver
            ? Colors.amber.shade50
            : AppTheme.outOfStockBg;

    final Color textColor = isBalanced
        ? AppTheme.inStockColor
        : isOver
            ? Colors.amber.shade900
            : AppTheme.outOfStockColor;

    final IconData icon = isBalanced
        ? Icons.check_circle_rounded
        : isOver
            ? Icons.add_circle_rounded
            : Icons.warning_rounded;

    final String text = isBalanced
        ? 'Drawer is Balanced (₱0.00)'
        : isOver
            ? 'Cash Over: +₱${diff.toStringAsFixed(2)}'
            : 'Cash Short: -₱${(-diff).toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
