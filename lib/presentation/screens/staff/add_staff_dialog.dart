import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_auth_service.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';

class AddStaffDialog extends StatefulWidget {
  final AppDatabase db;

  const AddStaffDialog({super.key, required this.db});

  @override
  State<AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  
  String _firstName = '';
  String _lastName = '';
  String _position = 'Cashier';
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (!PermissionService.instance.hasPermission(PosPermissions.staffManage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to add staff.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final companyId = DevicePrefs.companyId;
    final storeId = DevicePrefs.storeId;
    if (companyId == null || storeId == null) return;

    setState(() => _isLoading = true);

    try {
      // 1. Create Auth User via REST API (avoids logging out current Admin)
      final profileId = await SupabaseAuthService.signUpUserBackend(_email, _password);

      final employeeId = const Uuid().v4();

      // 2. Insert into SQLite Employees Table
      final newEmployee = EmployeesCompanion.insert(
        id: employeeId,
        companyId: companyId,
        storeId: drift.Value(storeId),
        profileId: drift.Value(profileId),
        email: drift.Value(_email),
        firstName: _firstName,
        lastName: _lastName,
        position: drift.Value(_position),
      );

      await widget.db.posDao.addEmployee(newEmployee);

      // 3. Immediately upsert directly to Supabase cloud
      try {
        await Supabase.instance.client.from('employees').upsert({
          'id': employeeId,
          'company_id': companyId,
          'store_id': storeId,
          'profile_id': profileId,
          'email': _email,
          'first_name': _firstName,
          'last_name': _lastName,
          'position': _position,
          'is_active': true,
        });
      } catch (_) {
        // Fallback: the queueSync in addEmployee will retry syncing
      }
      
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
    if (!PermissionService.instance.hasPermission(PosPermissions.staffManage)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to create staff accounts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Add Staff Member'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => _firstName = v!.trim(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => _lastName = v!.trim(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: PermissionService.instance.getAllRoles().contains(_position)
                    ? _position
                    : PermissionService.instance.getAllRoles().first,
                decoration: const InputDecoration(labelText: 'Position / Role', border: OutlineInputBorder()),
                items: PermissionService.instance.getAllRoles().map((r) {
                  return DropdownMenuItem(value: r, child: Text(r));
                }).toList(),
                onChanged: (v) => setState(() => _position = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Valid email required' : null,
                onSaved: (v) => _email = v!.trim(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Account Password',
                  border: OutlineInputBorder(),
                  helperText: 'Used for initial login.',
                ),
                obscureText: true,
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                onSaved: (v) => _password = v!,
              ),
            ],
          ),
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
            : const Text('Save'),
        ),
      ],
    );
  }
}
