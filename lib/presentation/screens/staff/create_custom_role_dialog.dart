import 'package:flutter/material.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../theme/app_theme.dart';

/// Dialog to create a new custom role template.
class CreateCustomRoleDialog extends StatefulWidget {
  const CreateCustomRoleDialog({super.key});

  @override
  State<CreateCustomRoleDialog> createState() => _CreateCustomRoleDialogState();
}

class _CreateCustomRoleDialogState extends State<CreateCustomRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  String _roleName = '';
  String _baseTemplate = PosPermissions.roleCashier;
  bool _isLoading = false;

  final List<String> _templateOptions = [
    PosPermissions.roleCashier,
    PosPermissions.roleManager,
    PosPermissions.roleInventory,
    'Empty (No initial permissions)',
  ];

  Future<void> _submit() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to create custom roles.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final allExisting = PermissionService.instance.getAllRoles();
    if (allExisting.any((r) => r.toLowerCase() == _roleName.trim().toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A role with this name already exists. Choose a different name.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      Set<String> initialPerms = {};
      if (_baseTemplate != 'Empty (No initial permissions)') {
        initialPerms = PermissionService.instance.getRolePermissions(_baseTemplate);
      }

      await PermissionService.instance.createCustomRole(_roleName.trim(), initialPerms);

      if (mounted) {
        Navigator.of(context).pop(_roleName.trim());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating role: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to create custom roles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppTheme.primaryColor),
          SizedBox(width: 10),
          Text('Create Custom Role'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Define a new job role template that can be assigned to staff members.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Role Title',
                hintText: 'e.g. Shift Supervisor, Floor Lead',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Role title is required';
                if (v.trim().length < 3) return 'At least 3 characters required';
                return null;
              },
              onSaved: (v) => _roleName = v!,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _baseTemplate,
              decoration: const InputDecoration(
                labelText: 'Base Template',
                helperText: 'Initial permissions to pre-fill into this role.',
                border: OutlineInputBorder(),
              ),
              items: _templateOptions.map((t) {
                return DropdownMenuItem(value: t, child: Text(t));
              }).toList(),
              onChanged: (v) => setState(() => _baseTemplate = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create Role'),
        ),
      ],
    );
  }
}
