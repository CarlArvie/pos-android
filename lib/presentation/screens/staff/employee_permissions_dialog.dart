import 'package:flutter/material.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/local/database.dart';
import '../../theme/app_theme.dart';

/// Modal dialog that allows an Admin to assign custom, employee-level permission
/// overrides for an individual staff member.
class EmployeePermissionsDialog extends StatefulWidget {
  final Employee employee;

  const EmployeePermissionsDialog({
    super.key,
    required this.employee,
  });

  @override
  State<EmployeePermissionsDialog> createState() => _EmployeePermissionsDialogState();
}

class _EmployeePermissionsDialogState extends State<EmployeePermissionsDialog> {
  late bool _hasCustomOverrides;
  late Set<String> _selectedPermissions;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existingOverrides =
        PermissionService.instance.getEmployeeCustomPermissions(widget.employee.id);

    if (existingOverrides != null) {
      _hasCustomOverrides = true;
      _selectedPermissions = Set<String>.from(existingOverrides);
    } else {
      _hasCustomOverrides = false;
      // Populate initially with their role defaults for convenience
      _selectedPermissions =
          PermissionService.instance.getRolePermissions(widget.employee.position);
    }
  }

  void _togglePermission(String key, bool enabled) {
    setState(() {
      if (enabled) {
        _selectedPermissions.add(key);
      } else {
        _selectedPermissions.remove(key);
      }
    });
  }

  void _toggleModuleAll(String moduleId, bool selectAll) {
    final modulePerms =
        PosPermissions.allPermissions.where((p) => p.moduleId == moduleId).map((p) => p.key);

    setState(() {
      if (selectAll) {
        _selectedPermissions.addAll(modulePerms);
      } else {
        _selectedPermissions.removeAll(modulePerms);
      }
    });
  }

  Future<void> _save() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to manage permissions.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (!_hasCustomOverrides) {
        // Clear custom overrides, revert to role
        await PermissionService.instance.setEmployeeCustomPermissions(widget.employee.id, null);
      } else {
        await PermissionService.instance
            .setEmployeeCustomPermissions(widget.employee.id, _selectedPermissions);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _hasCustomOverrides
                  ? 'Custom permissions saved for ${widget.employee.firstName}.'
                  : 'Reverted ${widget.employee.firstName} to standard ${widget.employee.position} role permissions.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving permissions: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to manage employee permissions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final emp = widget.employee;
    final isAdmin = emp.position.toLowerCase() == 'admin';

    final size = MediaQuery.of(context).size;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 650,
          maxHeight: size.height * 0.9,
        ),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${emp.firstName} ${emp.lastName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Position: ${emp.position} • ID: ${emp.id.substring(0, 8)}...',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            if (isAdmin) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This employee holds the Admin role and automatically possesses unrestricted access to all POS modules and features.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              // Custom Override Toggle Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _hasCustomOverrides ? Colors.blue.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasCustomOverrides ? Colors.blue.shade200 : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasCustomOverrides ? Icons.tune_rounded : Icons.lock_outline_rounded,
                      color: _hasCustomOverrides ? Colors.blue.shade700 : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Individual Permission Overrides',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _hasCustomOverrides ? Colors.blue.shade900 : Colors.black87,
                            ),
                          ),
                          Text(
                            _hasCustomOverrides
                                ? 'Custom permissions are enabled for this employee.'
                                : 'Inheriting standard permissions from the "${emp.position}" role.',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _hasCustomOverrides,
                      onChanged: (val) {
                        setState(() {
                          _hasCustomOverrides = val;
                          if (!val) {
                            _selectedPermissions =
                                PermissionService.instance.getRolePermissions(emp.position);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Module Accordions List
              Expanded(
                child: Opacity(
                  opacity: _hasCustomOverrides ? 1.0 : 0.6,
                  child: AbsorbPointer(
                    absorbing: !_hasCustomOverrides,
                    child: ListView.builder(
                      itemCount: PosPermissions.modules.length,
                      itemBuilder: (context, index) {
                        final module = PosPermissions.modules[index];
                        final modulePerms = PosPermissions.allPermissions
                            .where((p) => p.moduleId == module.id)
                            .toList();

                        final activeCount = modulePerms
                            .where((p) => _selectedPermissions.contains(p.key))
                            .length;
                        final allActive = activeCount == modulePerms.length;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          elevation: 0,
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              leading: Icon(module.icon, color: AppTheme.primaryColor),
                              title: Text(
                                module.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: activeCount > 0
                                          ? Colors.green.shade50
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: activeCount > 0
                                            ? Colors.green.shade300
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      '$activeCount / ${modulePerms.length}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: activeCount > 0
                                            ? Colors.green.shade800
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      allActive
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      size: 20,
                                      color: allActive ? AppTheme.primaryColor : Colors.grey,
                                    ),
                                    tooltip: allActive ? 'Deselect All' : 'Select All',
                                    onPressed: () => _toggleModuleAll(module.id, !allActive),
                                  ),
                                ],
                              ),
                              children: modulePerms.map((perm) {
                                final isGranted = _selectedPermissions.contains(perm.key);
                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border(top: BorderSide(color: Colors.grey.shade100)),
                                  ),
                                  child: SwitchListTile(
                                    dense: true,
                                    title: Wrap(
                                      spacing: 6,
                                      runSpacing: 2,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          perm.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        if (perm.isSensitive)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.orange.shade200),
                                            ),
                                            child: Text(
                                              'Sensitive',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      perm.description,
                                      style:
                                          const TextStyle(fontSize: 11, color: Colors.black54),
                                    ),
                                    value: isGranted,
                                    onChanged: (val) => _togglePermission(perm.key, val),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                if (!isAdmin) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Save Permissions'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }
}
