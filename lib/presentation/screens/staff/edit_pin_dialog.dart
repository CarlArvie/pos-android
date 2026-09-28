import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';

class EditPinDialog extends StatefulWidget {
  final AppDatabase db;
  final Employee employee;

  const EditPinDialog({super.key, required this.db, required this.employee});

  @override
  State<EditPinDialog> createState() => _EditPinDialogState();
}

class _EditPinDialogState extends State<EditPinDialog> {
  final _formKey = GlobalKey<FormState>();
  String _newPin = '';
  bool _isLoading = false;

  Future<void> _save() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffResetPin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to reset PINs.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      await widget.db.posDao.updateEmployeePin(widget.employee.id, _newPin);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffResetPin)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to reset employee PINs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Reset PIN for ${widget.employee.firstName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a new 4-6 digit PIN code for this employee to use when logging into the terminal.'),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'New PIN',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 4 || v.length > 6) return 'Must be 4-6 digits';
                if (int.tryParse(v) == null) return 'Numbers only';
                return null;
              },
              onSaved: (v) => _newPin = v!.trim(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Update PIN'),
        ),
      ],
    );
  }
}
