import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../theme/app_theme.dart';
import 'add_staff_dialog.dart';
import 'edit_pin_dialog.dart';
import 'employee_permissions_dialog.dart';
import 'create_custom_role_dialog.dart';

class StaffManagementView extends StatefulWidget {
  final AppDatabase db;

  const StaffManagementView({super.key, required this.db});

  @override
  State<StaffManagementView> createState() => _StaffManagementViewState();
}

class _StaffManagementViewState extends State<StaffManagementView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Employee> _employees = [];
  bool _isLoading = true;

  // Roles & Permissions state
  String _selectedRole = PosPermissions.roleCashier;
  Set<String> _workingRolePermissions = {};
  bool _hasUnsavedChanges = false;
  bool _isSavingRole = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployees();
    _loadRolePermissions(_selectedRole);

    // Listen to permission changes globally
    PermissionService.instance.changeNotifier.addListener(_onPermissionsChanged);
  }

  @override
  void dispose() {
    PermissionService.instance.changeNotifier.removeListener(_onPermissionsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onPermissionsChanged() {
    if (mounted) {
      if (_tabController.index != 0) {
        _tabController.index = 0;
      }
      setState(() {});
    }
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    final storeId = DevicePrefs.storeId;
    if (storeId != null) {
      _employees = await widget.db.posDao.getEmployeesForStore(storeId);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _loadRolePermissions(String role) {
    setState(() {
      _selectedRole = role;
      _workingRolePermissions =
          PermissionService.instance.getRolePermissions(role);
      _hasUnsavedChanges = false;
    });
  }

  void _showAddStaffDialog() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffManage)) return;
    final bool? added = await showDialog(
      context: context,
      builder: (_) => AddStaffDialog(db: widget.db),
    );
    if (added == true) {
      _loadEmployees();
    }
  }

  void _showEditPinDialog(Employee employee) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffResetPin)) return;
    final bool? updated = await showDialog(
      context: context,
      builder: (_) => EditPinDialog(db: widget.db, employee: employee),
    );
    if (!mounted) return;
    if (updated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PIN updated for ${employee.firstName}')),
      );
    }
  }

  void _showEmployeePermissionsDialog(Employee employee) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) return;
    final bool? changed = await showDialog(
      context: context,
      builder: (_) => EmployeePermissionsDialog(employee: employee),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  void _showCreateCustomRoleDialog() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffPermissions)) return;
    final String? newRole = await showDialog(
      context: context,
      builder: (_) => const CreateCustomRoleDialog(),
    );
    if (newRole != null && mounted) {
      _loadRolePermissions(newRole);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created custom role "$newRole".'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _changeEmployeeRole(Employee employee, String newRole) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffManage)) return;
    await widget.db.posDao.updateEmployeeRole(employee.id, newRole);
    await _loadEmployees();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated ${employee.firstName}\'s role to $newRole.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _toggleEmployeeActive(Employee employee, bool isActive) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.staffManage)) return;
    await widget.db.posDao.updateEmployeeActive(employee.id, isActive);
    await _loadEmployees();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${employee.firstName} is now ${isActive ? "Active" : "Deactivated"}.'),
          backgroundColor: isActive ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  void _toggleWorkingPermission(String key, bool enable) {
    if (_selectedRole.toLowerCase() == 'admin') return;
    setState(() {
      if (enable) {
        _workingRolePermissions.add(key);
      } else {
        _workingRolePermissions.remove(key);
      }
      _hasUnsavedChanges = true;
    });
  }

  void _toggleWorkingModuleAll(String moduleId, bool selectAll) {
    if (_selectedRole.toLowerCase() == 'admin') return;
    final modulePerms =
        PosPermissions.allPermissions.where((p) => p.moduleId == moduleId).map((p) => p.key);

    setState(() {
      if (selectAll) {
        _workingRolePermissions.addAll(modulePerms);
      } else {
        _workingRolePermissions.removeAll(modulePerms);
      }
      _hasUnsavedChanges = true;
    });
  }

  void _selectAllWorking(bool selectAll) {
    if (_selectedRole.toLowerCase() == 'admin') return;
    setState(() {
      if (selectAll) {
        _workingRolePermissions =
            PosPermissions.allPermissions.map((p) => p.key).toSet();
      } else {
        _workingRolePermissions.clear();
      }
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _saveRoleChanges() async {
    if (_selectedRole.toLowerCase() == 'admin') return;
    setState(() => _isSavingRole = true);
    try {
      await PermissionService.instance
          .saveRolePermissions(_selectedRole, _workingRolePermissions);
      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _isSavingRole = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permissions saved for role "$_selectedRole".'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingRole = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving role: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resetRoleToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset "$_selectedRole" to Default?'),
        content: const Text(
          'This will restore the original system default permissions for this role. Any custom modifications will be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reset to Default'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PermissionService.instance.resetRoleToDefault(_selectedRole);
      _loadRolePermissions(_selectedRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Role "$_selectedRole" reset to default permissions.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  Future<void> _deleteCustomRole() async {
    final assignedStaff = _employees
        .where((e) => e.position.toLowerCase() == _selectedRole.toLowerCase())
        .toList();

    if (assignedStaff.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete Role'),
          content: Text(
            'This role is currently assigned to ${assignedStaff.length} staff member(s). Reassign them to another role first before deleting.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Role "$_selectedRole"?'),
        content: const Text('Are you sure you want to delete this custom role template?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final roleToDelete = _selectedRole;
      await PermissionService.instance.deleteCustomRole(roleToDelete);
      _loadRolePermissions(PosPermissions.roleCashier);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Custom role "$roleToDelete" deleted.'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canManageStaff = PermissionService.instance.hasPermission(PosPermissions.staffManage);
    final canManagePerms = PermissionService.instance.hasPermission(PosPermissions.staffPermissions);
    final canResetPin = PermissionService.instance.hasPermission(PosPermissions.staffResetPin);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Staff & Permissions',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage staff credentials, access levels, and granular role permissions.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (canManageStaff)
                  ElevatedButton.icon(
                    key: const Key('add_staff_button'),
                    onPressed: _showAddStaffDialog,
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add Staff'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Tab Bar (only rendered when canManagePerms is true)
          if (canManagePerms)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
                ),
                child: TabBar(
                  key: const Key('staff_tabs_bar'),
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: AppTheme.primaryColor,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  tabs: [
                    Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.people_alt_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text('Staff Directory (${_employees.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      key: const Key('roles_and_permissions_tab'),
                      child: Row(
                        children: [
                          const Icon(Icons.admin_panel_settings_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text('Roles & Permissions (${PermissionService.instance.getAllRoles().length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Tab Content
          Expanded(
            child: canManagePerms
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStaffDirectoryTab(canManageStaff, canManagePerms, canResetPin),
                      _buildRolesAndPermissionsTab(),
                    ],
                  )
                : _buildStaffDirectoryTab(canManageStaff, canManagePerms, canResetPin),
          ),
        ],
      ),
      bottomSheet: _hasUnsavedChanges ? _buildUnsavedChangesBar() : null,
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: Staff Directory
  // --------------------------------------------------------------------------
  Widget _buildStaffDirectoryTab(bool canManageStaff, bool canManagePerms, bool canResetPin) {
    if (_employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No staff members registered for this store.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Click "+ Add Staff" above to create employee logins.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20.0),
      itemCount: _employees.length,
      itemBuilder: (context, index) {
        final employee = _employees[index];
        final isCurrent = employee.id == DevicePrefs.currentEmployeeId;
        final isAdmin = employee.position.toLowerCase() == 'admin';
        final hasCustomOverrides =
            PermissionService.instance.getEmployeeCustomPermissions(employee.id) != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCurrent ? AppTheme.primaryColor.withValues(alpha: 0.4) : Colors.grey.shade200,
              width: isCurrent ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 650;

                final avatar = CircleAvatar(
                  radius: 20,
                  backgroundColor: isAdmin
                      ? Colors.amber.shade100
                      : AppTheme.primaryColor.withValues(alpha: 0.1),
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                    color: isAdmin ? Colors.amber.shade800 : AppTheme.primaryColor,
                    size: 20,
                  ),
                );

                final staffInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${employee.firstName} ${employee.lastName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        // Role Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin ? Colors.amber.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isAdmin ? Colors.amber.shade300 : Colors.blue.shade200,
                            ),
                          ),
                          child: Text(
                            employee.position,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isAdmin ? Colors.amber.shade900 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                        if (hasCustomOverrides)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Text(
                              'Custom Overrides',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade800,
                              ),
                            ),
                          ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'YOU',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${employee.email ?? "No email"} • Active: ${employee.isActive ? "Yes" : "No"}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                );

                final actionButtons = <Widget>[
                  // Active Switch
                  if (canManageStaff && !isAdmin)
                    Row(
                      key: Key('active_switch_row_${employee.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          employee.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 12,
                            color: employee.isActive ? Colors.green.shade700 : Colors.grey,
                          ),
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            key: Key('active_switch_${employee.id}'),
                            value: employee.isActive,
                            activeThumbColor: Colors.green,
                            onChanged: (val) => _toggleEmployeeActive(employee, val),
                          ),
                        ),
                      ],
                    ),

                  // Permissions Button
                  if (canManagePerms)
                    OutlinedButton.icon(
                      key: Key('permissions_button_${employee.id}'),
                      icon: Icon(
                        hasCustomOverrides ? Icons.tune_rounded : Icons.shield_outlined,
                        size: 15,
                        color: hasCustomOverrides ? Colors.purple : AppTheme.primaryColor,
                      ),
                      label: Text(
                        hasCustomOverrides ? 'Overrides' : 'Permissions',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasCustomOverrides ? Colors.purple : AppTheme.primaryColor,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: hasCustomOverrides ? Colors.purple.shade300 : Colors.grey.shade300,
                        ),
                      ),
                      onPressed: () => _showEmployeePermissionsDialog(employee),
                    ),

                  // Reset PIN
                  if (canResetPin)
                    OutlinedButton.icon(
                      key: Key('reset_pin_button_${employee.id}'),
                      icon: const Icon(Icons.lock_reset_rounded, size: 15),
                      label: const Text('Reset PIN', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showEditPinDialog(employee),
                    ),

                  // Change Role Menu
                  if (canManageStaff && !isAdmin)
                    PopupMenuButton<String>(
                      key: Key('change_role_button_${employee.id}'),
                      tooltip: 'Change Role',
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      itemBuilder: (context) {
                        final allRoles = PermissionService.instance.getAllRoles();
                        return allRoles.map((role) {
                          return PopupMenuItem(
                            value: role,
                            child: Row(
                              children: [
                                if (employee.position.toLowerCase() == role.toLowerCase())
                                  const Icon(Icons.check, size: 16, color: Colors.green)
                                else
                                  const SizedBox(width: 16),
                                const SizedBox(width: 8),
                                Text(role),
                              ],
                            ),
                          );
                        }).toList();
                      },
                      onSelected: (newRole) {
                        if (newRole.toLowerCase() != employee.position.toLowerCase()) {
                          _changeEmployeeRole(employee, newRole);
                        }
                      },
                    ),
                ];

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          avatar,
                          const SizedBox(width: 12),
                          Expanded(child: staffInfo),
                        ],
                      ),
                      if (actionButtons.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Divider(height: 1, color: Colors.grey.shade200),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: actionButtons,
                          ),
                        ),
                      ],
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      avatar,
                      const SizedBox(width: 14),
                      Expanded(child: staffInfo),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.55),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actionButtons,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: Roles & Permissions Matrix
  // --------------------------------------------------------------------------
  Widget _buildRolesAndPermissionsTab() {
    final allRoles = PermissionService.instance.getAllRoles();
    final customRoles = PermissionService.instance.getCustomRoles();
    final isCustomRole = customRoles.contains(_selectedRole);
    final isAdminRole = _selectedRole.toLowerCase() == 'admin';

    final assignedCount = _employees
        .where((e) => e.position.toLowerCase() == _selectedRole.toLowerCase())
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mobile Top Role Selector Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_selectedRole),
                        initialValue: _selectedRole,
                        isDense: true,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Selected Role',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: allRoles.map((role) {
                          final isCustom = customRoles.contains(role);
                          final count = _employees
                              .where((e) => e.position.toLowerCase() == role.toLowerCase())
                              .length;
                          return DropdownMenuItem(
                            value: role,
                            child: Text(
                              '$role ($count staff)${isCustom ? " • Custom" : ""}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                        onChanged: (newRole) {
                          if (newRole != null && newRole != _selectedRole) {
                            if (_hasUnsavedChanges) {
                              _promptDiscardOrSave(() => _loadRolePermissions(newRole));
                            } else {
                              _loadRolePermissions(newRole);
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add_rounded, size: 20),
                      tooltip: 'New Custom Role',
                      onPressed: _showCreateCustomRoleDialog,
                    ),
                  ],
                ),
              ),

              // Permissions Matrix
              Expanded(
                child: _buildRoleMatrixContent(
                  isCompact: true,
                  isCustomRole: isCustomRole,
                  isAdminRole: isAdminRole,
                  assignedCount: assignedCount,
                ),
              ),
            ],
          );
        }

        // Desktop / Tablet Layout
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Role Selector Sidebar
            Container(
              width: 240,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade200, width: 1.5)),
                color: Colors.grey.shade50,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Roles',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_rounded, size: 20),
                          tooltip: 'Create Custom Role',
                          onPressed: _showCreateCustomRoleDialog,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allRoles.length,
                      itemBuilder: (context, index) {
                        final roleName = allRoles[index];
                        final isSelected = roleName == _selectedRole;
                        final roleStaffCount = _employees
                            .where((e) => e.position.toLowerCase() == roleName.toLowerCase())
                            .length;
                        final isCustom = customRoles.contains(roleName);
                        final isAdmin = roleName.toLowerCase() == 'admin';

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                          leading: Icon(
                            isAdmin
                                ? Icons.admin_panel_settings_rounded
                                : isCustom
                                    ? Icons.badge_outlined
                                    : Icons.shield_outlined,
                            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade700,
                            size: 20,
                          ),
                          title: Text(
                            roleName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppTheme.primaryColor : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '$roleStaffCount staff assigned',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          trailing: isCustom
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Custom', style: TextStyle(fontSize: 9)),
                                )
                              : null,
                          onTap: () {
                            if (_hasUnsavedChanges) {
                              _promptDiscardOrSave(() => _loadRolePermissions(roleName));
                            } else {
                              _loadRolePermissions(roleName);
                            }
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCreateCustomRoleDialog,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New Custom Role'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Role Permissions Matrix View
            Expanded(
              child: _buildRoleMatrixContent(
                isCompact: false,
                isCustomRole: isCustomRole,
                isAdminRole: isAdminRole,
                assignedCount: assignedCount,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleMatrixContent({
    required bool isCompact,
    required bool isCustomRole,
    required bool isAdminRole,
    required int assignedCount,
  }) {
    final header = Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _selectedRole,
                style: TextStyle(fontSize: isCompact ? 16 : 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isAdminRole
                      ? Colors.amber.shade50
                      : isCustomRole
                          ? Colors.purple.shade50
                          : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isAdminRole
                        ? Colors.amber.shade200
                        : isCustomRole
                            ? Colors.purple.shade200
                            : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  isAdminRole
                      ? 'System Administrator (Locked)'
                      : isCustomRole
                          ? 'Custom Role Template'
                          : 'Standard Role Template',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isAdminRole
                        ? Colors.amber.shade900
                        : isCustomRole
                            ? Colors.purple.shade800
                            : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isAdminRole
                ? 'Full unrestricted access to all POS screens, accounting, and configuration.'
                : 'Assigned to $assignedCount employee(s). Toggle features to customize this role.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (!isAdminRole) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _selectAllWorking(true),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: () => _selectAllWorking(false),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Deselect All'),
                ),
                if (isCustomRole)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.red),
                    label: const Text('Delete Role', style: TextStyle(color: Colors.red, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    onPressed: _deleteCustomRole,
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore_rounded, size: 15),
                    label: const Text('Reset to Default', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _resetRoleToDefault,
                  ),
                ElevatedButton.icon(
                  onPressed: (_hasUnsavedChanges && !_isSavingRole)
                      ? _saveRoleChanges
                      : null,
                  icon: _isSavingRole
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 15),
                  label: const Text('Save Changes', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        _hasUnsavedChanges ? Colors.green : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final adminNotice = isAdminRole
        ? Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24, vertical: 12),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The Admin role possesses complete system-wide access and cannot be restricted to prevent terminal lockouts.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    if (isCompact) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        children: [
          header,
          if (adminNotice != null) ...[
            const SizedBox(height: 8),
            adminNotice,
          ],
          const SizedBox(height: 12),
          ...PosPermissions.modules.map(
            (m) => _buildModuleCard(m, isCompact: true, isAdminRole: isAdminRole),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        ?adminNotice,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(24.0),
            itemCount: PosPermissions.modules.length,
            itemBuilder: (context, index) {
              final module = PosPermissions.modules[index];
              return _buildModuleCard(module, isCompact: false, isAdminRole: isAdminRole);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard(
    PosModuleInfo module, {
    required bool isCompact,
    required bool isAdminRole,
  }) {
    final modulePerms =
        PosPermissions.allPermissions.where((p) => p.moduleId == module.id).toList();
    final activeCount =
        modulePerms.where((p) => _workingRolePermissions.contains(p.key)).length;
    final allActive = activeCount == modulePerms.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 0,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: module.id == 'pos',
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
            child: Icon(module.icon, color: AppTheme.primaryColor, size: 18),
          ),
          title: Text(
            module.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            module.description,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: activeCount > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeCount > 0 ? Colors.green.shade300 : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  '$activeCount / ${modulePerms.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: activeCount > 0 ? Colors.green.shade800 : Colors.grey.shade600,
                  ),
                ),
              ),
              if (!isAdminRole) ...[
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    allActive
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: allActive ? AppTheme.primaryColor : Colors.grey,
                  ),
                  tooltip: allActive ? 'Deselect Module' : 'Select All in Module',
                  onPressed: () => _toggleWorkingModuleAll(module.id, !allActive),
                ),
              ],
            ],
          ),
          children: modulePerms.map((perm) {
            final isGranted = _workingRolePermissions.contains(perm.key);
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: SwitchListTile(
                dense: true,
                title: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      perm.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    if (perm.isSensitive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                value: isAdminRole ? true : isGranted,
                onChanged: isAdminRole
                    ? null
                    : (val) => _toggleWorkingPermission(perm.key, val),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }


  void _promptDiscardOrSave(VoidCallback proceed) async {
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: Text('You have unsaved changes in role "$_selectedRole". Save before switching?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // Discard
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), // Save
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (save == true) {
      await _saveRoleChanges();
      proceed();
    } else if (save == false) {
      proceed();
    }
  }

  Widget _buildUnsavedChangesBar() {
    return Material(
      elevation: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Dark slate
          border: const Border(top: BorderSide(color: Color(0xFF334155))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unsaved changes in "$_selectedRole"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Tap Save to broadcast to Cashier registers.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _isSavingRole
                    ? null
                    : () {
                        _loadRolePermissions(_selectedRole);
                      },
                child: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                key: const Key('sticky_save_permissions_button'),
                onPressed: _isSavingRole ? null : _saveRoleChanges,
                icon: _isSavingRole
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
