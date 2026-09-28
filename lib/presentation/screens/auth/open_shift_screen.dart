import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../main_shell_screen.dart';

class OpenShiftScreen extends StatefulWidget {
  final AppDatabase db;
  final Employee employee;

  const OpenShiftScreen({super.key, required this.db, required this.employee});

  @override
  State<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends State<OpenShiftScreen> {
  final _amountController = TextEditingController(text: '0.00');
  final _notesController = TextEditingController();
  bool _isLoading = false;

  Future<void> _startShift() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    
    final companyId = DevicePrefs.companyId;
    final storeId = DevicePrefs.storeId;
    final registerId = DevicePrefs.registerId;
    final employeeId = DevicePrefs.currentEmployeeId;

    if (companyId == null || storeId == null || registerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device not properly provisioned.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    await widget.db.posDao.openCashShift(
      companyId: companyId,
      storeId: storeId,
      registerId: registerId,
      employeeId: employeeId,
      openingBalance: amount,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShellScreen(database: widget.db)),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Shift'),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.point_of_sale_rounded, size: 64, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                'Open Cash Drawer',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the starting cash amount (float) in the drawer for this shift.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Opening Balance',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: _isLoading ? null : _startShift,
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Start Shift'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
