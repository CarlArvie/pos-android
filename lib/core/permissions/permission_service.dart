import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../device_prefs.dart';
import 'pos_permissions.dart';

/// Central permission management service.
/// Evaluates permissions with zero latency (in-memory cache) and persists role/employee
/// customizations to SharedPreferences and Supabase cloud for real-time multi-device sync.
class PermissionService {
  static final PermissionService instance = PermissionService._internal();
  factory PermissionService() => instance;
  PermissionService._internal();

  /// Reactive notifier triggered whenever permissions or roles change
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// In-memory cache of customized permissions per role (normalized lowercase keys)
  final Map<String, Set<String>> _rolePermissionsCache = {};

  /// In-memory cache of employee-specific overrides
  final Map<String, Set<String>> _employeeOverridesCache = {};

  /// Custom created roles list
  final List<String> _customRoles = [];

  bool _initialized = false;

  static String _normalizeRole(String role) => role.trim().toLowerCase();

  bool get _isSupabaseReady {
    try {
      return Supabase.instance.isInitialized;
    } catch (_) {
      return false;
    }
  }

  /// Initialize service, load persisted customizations into memory
  Future<void> init({bool force = false}) async {
    if (_initialized && !force) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      _rolePermissionsCache.clear();
      _employeeOverridesCache.clear();
      _customRoles.clear();

      // 1. Load custom roles list
      final customRolesList = prefs.getStringList('pos_custom_roles_list') ?? [];
      _customRoles.addAll(customRolesList);

      // 2. Load built-in roles customizations
      for (final role in [...PosPermissions.systemRoles, ..._customRoles]) {
        final key = _prefsRoleKey(role);
        final jsonStr = prefs.getString(key);
        if (jsonStr != null) {
          try {
            final List<dynamic> list = jsonDecode(jsonStr);
            _rolePermissionsCache[_normalizeRole(role)] = list.map((e) => e.toString()).toSet();
          } catch (e) {
            debugPrint('[PermissionService] Failed to parse permissions for $role: $e');
          }
        }
      }

      // 3. Load employee overrides
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('pos_emp_perms_')) {
          final empId = key.substring('pos_emp_perms_'.length);
          final jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final List<dynamic> list = jsonDecode(jsonStr);
              _employeeOverridesCache[empId] = list.map((e) => e.toString()).toSet();
            } catch (_) {}
          }
        }
      }

      _initialized = true;
    } catch (e) {
      debugPrint('[PermissionService] Init error: $e');
    }
  }

  static String _prefsRoleKey(String role) => 'pos_role_perms_${role.trim().toLowerCase().replaceAll(' ', '_')}';
  static String _prefsEmpKey(String empId) => 'pos_emp_perms_$empId';

  /// Primary check: does the current logged-in user have this permission?
  bool hasPermission(String permissionKey) {
    // 1. Super Admin bypass: Admin role always has all permissions
    final currentRole = DevicePrefs.currentEmployeeRole?.trim().toLowerCase() ?? '';
    if (currentRole == 'admin') {
      return true;
    }

    // 2. Check employee-level overrides
    final empId = DevicePrefs.currentEmployeeId;
    if (empId != null && _employeeOverridesCache.containsKey(empId)) {
      final userPerms = _employeeOverridesCache[empId]!;
      return userPerms.contains(permissionKey);
    }

    // 3. Check role-level permissions (normalized case-insensitive)
    final roleName = DevicePrefs.currentEmployeeRole ?? PosPermissions.roleCashier;
    final rolePerms = getRolePermissions(roleName);
    return rolePerms.contains(permissionKey);
  }

  /// Convenience check: can the current user view/access the given main shell tab?
  bool canAccessTab(int tabIndex) {
    // Admin always has access to all tabs
    final currentRole = DevicePrefs.currentEmployeeRole?.trim().toLowerCase() ?? '';
    if (currentRole == 'admin') return true;

    switch (tabIndex) {
      case 0: // Inventory
        return hasPermission(PosPermissions.inventoryView);
      case 1: // Customers
        return hasPermission(PosPermissions.customersView);
      case 2: // POS Counter
        return hasPermission(PosPermissions.posView);
      case 3: // Transactions
        return hasPermission(PosPermissions.transactionsViewOwn) ||
            hasPermission(PosPermissions.transactionsViewAll);
      case 4: // Reports
        return hasPermission(PosPermissions.reportsView);
      case 5: // Stores
        return hasPermission(PosPermissions.storesView);
      case 6: // Staff
        return hasPermission(PosPermissions.staffView);
      case 7: // Settings
        return hasPermission(PosPermissions.settingsView);
      default:
        return false;
    }
  }

  /// Returns active permissions for a role (customized if saved, otherwise default)
  Set<String> getRolePermissions(String roleName) {
    final norm = _normalizeRole(roleName);
    if (norm == 'admin') {
      return PosPermissions.getDefaultPermissions(PosPermissions.roleAdmin);
    }

    if (_rolePermissionsCache.containsKey(norm)) {
      return Set<String>.from(_rolePermissionsCache[norm]!);
    }

    // Return default template
    return PosPermissions.getDefaultPermissions(roleName);
  }

  /// Saves updated permissions for a role
  Future<void> saveRolePermissions(String roleName, Set<String> perms) async {
    final norm = _normalizeRole(roleName);
    if (norm == 'admin') {
      return; // Admin cannot be restricted
    }

    _rolePermissionsCache[norm] = Set<String>.from(perms);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsRoleKey(roleName), jsonEncode(perms.toList()));

    // Realtime Cloud Sync to Supabase companies table
    if (_isSupabaseReady) {
      try {
        final companyId = DevicePrefs.companyId;
        if (companyId != null && companyId.isNotEmpty) {
          final exported = exportAllRolePermissions();
          await Supabase.instance.client
              .from('companies')
              .update({'role_permissions': jsonEncode(exported)})
              .eq('id', companyId);
        }
      } catch (e) {
        debugPrint('[PermissionService] Cloud sync role permissions error: $e');
      }
    }

    changeNotifier.value++;
  }

  /// Resets a role back to system defaults
  Future<void> resetRoleToDefault(String roleName) async {
    final norm = _normalizeRole(roleName);
    if (norm == 'admin') return;

    _rolePermissionsCache.remove(norm);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsRoleKey(roleName));

    if (_isSupabaseReady) {
      try {
        final companyId = DevicePrefs.companyId;
        if (companyId != null && companyId.isNotEmpty) {
          final exported = exportAllRolePermissions();
          await Supabase.instance.client
              .from('companies')
              .update({'role_permissions': jsonEncode(exported)})
              .eq('id', companyId);
        }
      } catch (e) {
        debugPrint('[PermissionService] Cloud sync reset role error: $e');
      }
    }

    changeNotifier.value++;
  }

  /// List of all roles (built-in system roles + custom roles)
  List<String> getAllRoles() {
    return [...PosPermissions.systemRoles, ..._customRoles];
  }

  /// Returns custom user-created roles
  List<String> getCustomRoles() => List<String>.unmodifiable(_customRoles);

  /// Create a new custom role
  Future<void> createCustomRole(String roleName, Set<String> initialPerms) async {
    final trimmed = roleName.trim();
    if (trimmed.isEmpty || getAllRoles().any((r) => _normalizeRole(r) == _normalizeRole(trimmed))) {
      return;
    }

    _customRoles.add(trimmed);
    _rolePermissionsCache[_normalizeRole(trimmed)] = Set<String>.from(initialPerms);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pos_custom_roles_list', _customRoles);
    await prefs.setString(_prefsRoleKey(trimmed), jsonEncode(initialPerms.toList()));

    if (_isSupabaseReady) {
      try {
        final companyId = DevicePrefs.companyId;
        if (companyId != null && companyId.isNotEmpty) {
          final exported = exportAllRolePermissions();
          await Supabase.instance.client
              .from('companies')
              .update({'role_permissions': jsonEncode(exported)})
              .eq('id', companyId);
        }
      } catch (e) {
        debugPrint('[PermissionService] Cloud sync create custom role error: $e');
      }
    }

    changeNotifier.value++;
  }

  /// Delete a custom role
  Future<void> deleteCustomRole(String roleName) async {
    final trimmed = roleName.trim();
    _customRoles.removeWhere((r) => _normalizeRole(r) == _normalizeRole(trimmed));
    _rolePermissionsCache.remove(_normalizeRole(trimmed));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pos_custom_roles_list', _customRoles);
    await prefs.remove(_prefsRoleKey(roleName));

    if (_isSupabaseReady) {
      try {
        final companyId = DevicePrefs.companyId;
        if (companyId != null && companyId.isNotEmpty) {
          final exported = exportAllRolePermissions();
          await Supabase.instance.client
              .from('companies')
              .update({'role_permissions': jsonEncode(exported)})
              .eq('id', companyId);
        }
      } catch (e) {
        debugPrint('[PermissionService] Cloud sync delete custom role error: $e');
      }
    }

    changeNotifier.value++;
  }

  /// Returns an individual employee's custom permissions (null if inheriting role permissions)
  Set<String>? getEmployeeCustomPermissions(String employeeId) {
    if (_employeeOverridesCache.containsKey(employeeId)) {
      return Set<String>.from(_employeeOverridesCache[employeeId]!);
    }
    return null;
  }

  /// Sets or clears individual employee custom permissions override
  Future<void> setEmployeeCustomPermissions(String employeeId, Set<String>? permissions) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsEmpKey(employeeId);

    if (permissions == null) {
      _employeeOverridesCache.remove(employeeId);
      await prefs.remove(key);
    } else {
      _employeeOverridesCache[employeeId] = Set<String>.from(permissions);
      await prefs.setString(key, jsonEncode(permissions.toList()));
    }

    // Realtime Cloud Sync to Supabase employees table
    if (_isSupabaseReady) {
      try {
        await Supabase.instance.client
            .from('employees')
            .update({
              'custom_permissions': permissions != null ? jsonEncode(permissions.toList()) : null,
            })
            .eq('id', employeeId);
      } catch (e) {
        debugPrint('[PermissionService] Cloud sync employee custom permissions error: $e');
      }
    }

    changeNotifier.value++;
  }

  /// Export current role cache for cloud syncing
  Map<String, List<String>> exportAllRolePermissions() {
    final map = <String, List<String>>{};
    for (final entry in _rolePermissionsCache.entries) {
      map[entry.key] = entry.value.toList();
    }
    return map;
  }

  /// Apply role permissions received from Supabase cloud (realtime or pull cycle)
  Future<void> applyCloudRolePermissions(dynamic rolePermsData) async {
    if (rolePermsData == null) return;
    try {
      Map<String, dynamic> rawMap = {};
      if (rolePermsData is String) {
        if (rolePermsData.trim().isEmpty) return;
        rawMap = jsonDecode(rolePermsData) as Map<String, dynamic>;
      } else if (rolePermsData is Map) {
        rawMap = Map<String, dynamic>.from(rolePermsData);
      }

      final prefs = await SharedPreferences.getInstance();
      bool changed = false;

      for (final entry in rawMap.entries) {
        final roleKey = _normalizeRole(entry.key);
        if (entry.value is List) {
          final set = (entry.value as List).map((e) => e.toString()).toSet();
          _rolePermissionsCache[roleKey] = set;
          await prefs.setString(_prefsRoleKey(roleKey), jsonEncode(set.toList()));
          changed = true;
        }
      }

      if (changed) {
        changeNotifier.value++;
      }
    } catch (e) {
      debugPrint('[PermissionService] Error applying cloud role permissions: $e');
    }
  }

  /// Apply individual employee permissions received from Supabase cloud (realtime or pull cycle)
  Future<void> applyCloudEmployeePermissions(String employeeId, dynamic permsData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsEmpKey(employeeId);

      if (permsData == null) {
        if (_employeeOverridesCache.containsKey(employeeId)) {
          _employeeOverridesCache.remove(employeeId);
          await prefs.remove(key);
          changeNotifier.value++;
        }
        return;
      }

      Set<String>? newPerms;
      if (permsData is String) {
        if (permsData.trim().isNotEmpty) {
          final list = jsonDecode(permsData) as List<dynamic>;
          newPerms = list.map((e) => e.toString()).toSet();
        }
      } else if (permsData is List) {
        newPerms = permsData.map((e) => e.toString()).toSet();
      }

      if (newPerms != null) {
        _employeeOverridesCache[employeeId] = newPerms;
        await prefs.setString(key, jsonEncode(newPerms.toList()));
        changeNotifier.value++;
      }
    } catch (e) {
      debugPrint('[PermissionService] Error applying cloud employee permissions: $e');
    }
  }
}
