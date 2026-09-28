import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../data/local/database.dart';
import '../../theme/app_theme.dart';
import '../../../core/device_prefs.dart';

class ManagerOverrideDialog extends StatefulWidget {
  final AppDatabase db;
  final String actionDescription;

  const ManagerOverrideDialog({
    super.key,
    required this.db,
    required this.actionDescription,
  });

  /// Displays the dialog and returns true if authorized, false otherwise.
  static Future<bool> requestOverride(BuildContext context, AppDatabase db, String actionDescription) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManagerOverrideDialog(db: db, actionDescription: actionDescription),
    );
    return result ?? false;
  }

  @override
  State<ManagerOverrideDialog> createState() => _ManagerOverrideDialogState();
}

class _ManagerOverrideDialogState extends State<ManagerOverrideDialog> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMsg = 'Please enter a PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final companyId = DevicePrefs.companyId;
    if (companyId == null) {
      if (mounted) Navigator.pop(context, false);
      return;
    }

    // Check if any admin exists with this PIN in the company
    final admin = await (widget.db.select(widget.db.employees)
          ..where((e) =>
              e.companyId.equals(companyId) &
              e.pinCode.equals(pin) &
              e.position.lower().equals('admin') &
              e.isActive.equals(true)))
        .getSingleOrNull();

    if (mounted) {
      setState(() => _isLoading = false);
      if (admin != null) {
        Navigator.pop(context, true); // Authorized!
      } else {
        setState(() {
          _errorMsg = 'Invalid Admin PIN';
          _pinController.clear();
        });
      }
    }
  }

  Widget _buildKeypadButton(String text) {
    return InkWell(
      onTap: () {
        if (_pinController.text.length < 6) {
          setState(() {
            _errorMsg = null;
            _pinController.text += text;
          });
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security_rounded, size: 48, color: AppTheme.accentColor),
            const SizedBox(height: 16),
            const Text(
              'Manager Override',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.actionDescription,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            
            // PIN Display
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _errorMsg != null ? Colors.red.shade300 : Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _pinController.text.isEmpty 
                  ? [Text('Enter PIN', style: TextStyle(color: Colors.grey.shade400))]
                  : List.generate(
                      _pinController.text.length,
                      (index) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.circle, size: 14, color: AppTheme.primaryColor),
                      ),
                    ),
              ),
            ),
            
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
              
            const SizedBox(height: 24),
            
            // Keypad
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                _buildKeypadButton('1'), _buildKeypadButton('2'), _buildKeypadButton('3'),
                _buildKeypadButton('4'), _buildKeypadButton('5'), _buildKeypadButton('6'),
                _buildKeypadButton('7'), _buildKeypadButton('8'), _buildKeypadButton('9'),
                
                // Clear button
                InkWell(
                  onTap: () {
                    setState(() {
                      if (_pinController.text.isNotEmpty) {
                        _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
                      }
                      _errorMsg = null;
                    });
                  },
                  child: const Center(child: Icon(Icons.backspace_outlined, color: Colors.grey)),
                ),
                
                _buildKeypadButton('0'),
                
                // Submit button
                InkWell(
                  onTap: _isLoading ? null : _verifyPin,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
