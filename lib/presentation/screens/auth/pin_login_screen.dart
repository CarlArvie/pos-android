import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../main_shell_screen.dart';
import 'open_shift_screen.dart';
import '../setup/existing_business_login_screen.dart';
import '../../theme/app_theme.dart';

class PinLoginScreen extends StatefulWidget {
  final AppDatabase db;

  const PinLoginScreen({super.key, required this.db});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String _pin = '';
  bool _isLoading = false;
  String? _errorMsg;

  void _onDigitPressed(String digit) {
    if (_pin.length < 6) {
      setState(() {
        _pin += digit;
        _errorMsg = null;
      });
      if (_pin.length == 4) { // Auto-submit on 4 digits (adjustable if 6 is preferred)
        _submitPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _errorMsg = null;
      });
    }
  }

  Future<void> _submitPin() async {
    if (_pin.isEmpty) return;

    final storeId = DevicePrefs.storeId;
    if (storeId == null) return; // Should not happen if provisioned

    setState(() => _isLoading = true);

    final employee = await widget.db.posDao.getEmployeeByPin(storeId, _pin);

    if (!mounted) return;

    if (employee != null) {
      await DevicePrefs.setCurrentEmployeeId(employee.id);
      await DevicePrefs.setCurrentEmployeeRole(employee.position);

      final registerId = DevicePrefs.registerId!;
      final shift = await widget.db.posDao.getActiveShift(registerId, employeeId: employee.id);

      if (!mounted) return;

      if (shift == null) {
        // No open shift.
        if (employee.position.toLowerCase() == 'admin') {
          // Admins bypass the float requirement completely
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainShellScreen(database: widget.db)),
          );
        } else {
          // Cashiers must open the drawer
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => OpenShiftScreen(db: widget.db, employee: employee)),
          );
        }
      } else {
        // Shift is open, go to POS
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(database: widget.db)),
        );
      }
    } else {
      setState(() {
        _errorMsg = 'Invalid PIN. Please try again.';
        _pin = '';
        _isLoading = false;
      });
    }
  }

  Widget _buildNumpadButton(String label, {VoidCallback? onPressed, IconData? icon}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed ?? () => _onDigitPressed(label),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade100,
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 28, color: Colors.black87)
                : Text(
                    label,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person_rounded, size: 64, color: AppTheme.primaryColor),
                const SizedBox(height: 24),
                const Text(
                  'Enter Cashier PIN',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                
                // PIN Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled ? AppTheme.primaryColor : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                
                if (_errorMsg != null)
                  Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                
                const SizedBox(height: 32),
                
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 24,
                      childAspectRatio: 1,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildNumpadButton('1'),
                        _buildNumpadButton('2'),
                        _buildNumpadButton('3'),
                        _buildNumpadButton('4'),
                        _buildNumpadButton('5'),
                        _buildNumpadButton('6'),
                        _buildNumpadButton('7'),
                        _buildNumpadButton('8'),
                        _buildNumpadButton('9'),
                        const SizedBox(), // Empty space
                        _buildNumpadButton('0'),
                        _buildNumpadButton('', icon: Icons.backspace_rounded, onPressed: _onBackspacePressed),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ExistingBusinessLoginScreen(db: widget.db),
                      ),
                    );
                  },
                  icon: const Icon(Icons.password_rounded, size: 18),
                  label: const Text('Sign in with Email & Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
