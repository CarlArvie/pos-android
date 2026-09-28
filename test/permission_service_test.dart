import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/core/permissions/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('PermissionService Core Tests', () {
    test('Admin role has complete unrestricted access to all permissions and tabs', () async {
      await DevicePrefs.setCurrentEmployeeRole('Admin');
      await DevicePrefs.setCurrentEmployeeId('admin-emp-001');

      // Admin has every single granular permission
      for (final perm in PosPermissions.allPermissions) {
        expect(
          PermissionService.instance.hasPermission(perm.key),
          isTrue,
          reason: 'Admin must have permission: ${perm.key}',
        );
      }

      // Admin has access to all 8 shell tabs
      for (int i = 0; i < 8; i++) {
        expect(
          PermissionService.instance.canAccessTab(i),
          isTrue,
          reason: 'Admin must have access to tab $i',
        );
      }
    });

    test('Cashier role has counter permissions but restricted from Admin views', () async {
      await DevicePrefs.setCurrentEmployeeRole('Cashier');
      await DevicePrefs.setCurrentEmployeeId('cashier-emp-002');

      // Allowed Cashier permissions
      expect(PermissionService.instance.hasPermission(PosPermissions.posView), isTrue);
      expect(PermissionService.instance.hasPermission(PosPermissions.posSell), isTrue);
      expect(PermissionService.instance.hasPermission(PosPermissions.posDiscountPreset), isTrue);
      expect(PermissionService.instance.hasPermission(PosPermissions.customersView), isTrue);
      expect(PermissionService.instance.hasPermission(PosPermissions.transactionsViewOwn), isTrue);

      // Restricted Cashier permissions
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.posDiscountCustom), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryAdd), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.reportsView), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.settingsView), isFalse);
      expect(PermissionService.instance.hasPermission(PosPermissions.staffView), isFalse);

      // Tab Access check
      expect(PermissionService.instance.canAccessTab(0), isFalse); // Inventory blocked
      expect(PermissionService.instance.canAccessTab(1), isTrue);  // Customers allowed
      expect(PermissionService.instance.canAccessTab(2), isTrue);  // POS Counter allowed
      expect(PermissionService.instance.canAccessTab(3), isTrue);  // Transactions allowed
      expect(PermissionService.instance.canAccessTab(4), isFalse); // Reports blocked
      expect(PermissionService.instance.canAccessTab(5), isFalse); // Stores blocked
      expect(PermissionService.instance.canAccessTab(6), isFalse); // Staff blocked
      expect(PermissionService.instance.canAccessTab(7), isFalse); // Settings blocked
    });

    test('Role customization saves and resets to default properly', () async {
      await DevicePrefs.setCurrentEmployeeRole('Cashier');
      await DevicePrefs.setCurrentEmployeeId('cashier-emp-003');

      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isFalse);

      // Customize Cashier to grant inventory view
      final cashierPerms = PermissionService.instance.getRolePermissions('Cashier');
      cashierPerms.add(PosPermissions.inventoryView);
      await PermissionService.instance.saveRolePermissions('Cashier', cashierPerms);

      // Now Cashier should have inventory view
      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isTrue);
      expect(PermissionService.instance.canAccessTab(0), isTrue);

      // Reset Cashier to default
      await PermissionService.instance.resetRoleToDefault('Cashier');

      // Should be revoked back to standard template
      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isFalse);
      expect(PermissionService.instance.canAccessTab(0), isFalse);
    });

    test('Custom role creation and deletion work seamlessly', () async {
      const customRole = 'Floor Supervisor';
      expect(PermissionService.instance.getAllRoles().contains(customRole), isFalse);

      // Create role
      await PermissionService.instance.createCustomRole(
        customRole,
        {PosPermissions.posView, PosPermissions.posSell, PosPermissions.posVoidCart},
      );

      expect(PermissionService.instance.getAllRoles().contains(customRole), isTrue);
      expect(PermissionService.instance.getCustomRoles().contains(customRole), isTrue);

      // Verify custom role evaluation
      await DevicePrefs.setCurrentEmployeeRole(customRole);
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isTrue);
      expect(PermissionService.instance.hasPermission(PosPermissions.inventoryView), isFalse);

      // Delete custom role
      await PermissionService.instance.deleteCustomRole(customRole);
      expect(PermissionService.instance.getAllRoles().contains(customRole), isFalse);
    });

    test('Employee-level permission overrides take precedence over role template', () async {
      await DevicePrefs.setCurrentEmployeeRole('Cashier');
      const empId = 'special-cashier-007';
      await DevicePrefs.setCurrentEmployeeId(empId);

      // Base cashier cannot void carts
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isFalse);

      // Grant special override to this specific employee
      final baseCashierPerms = PermissionService.instance.getRolePermissions('Cashier');
      final customOverrides = Set<String>.from(baseCashierPerms)..add(PosPermissions.posVoidCart);

      await PermissionService.instance.setEmployeeCustomPermissions(empId, customOverrides);

      // Now this specific cashier CAN void carts
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isTrue);

      // Another cashier still CANNOT void carts
      await DevicePrefs.setCurrentEmployeeId('normal-cashier-008');
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isFalse);

      // Remove employee override
      await PermissionService.instance.setEmployeeCustomPermissions(empId, null);
      await DevicePrefs.setCurrentEmployeeId(empId);
      expect(PermissionService.instance.hasPermission(PosPermissions.posVoidCart), isFalse);
    });

    test('PermissionService case-insensitivity and cloud sync methods', () async {
      await PermissionService.instance.init(force: true);

      // 1. Role case-insensitivity
      await PermissionService.instance.saveRolePermissions('cashier', {PosPermissions.posView, PosPermissions.inventoryView});
      expect(PermissionService.instance.getRolePermissions('Cashier').contains(PosPermissions.inventoryView), isTrue);
      expect(PermissionService.instance.getRolePermissions('CASHIER').contains(PosPermissions.inventoryView), isTrue);
      expect(PermissionService.instance.getRolePermissions('cashier').contains(PosPermissions.inventoryView), isTrue);

      // 2. Apply cloud role permissions
      await PermissionService.instance.applyCloudRolePermissions(
        '{"cashier": ["pos.view", "pos.sell", "inventory.view"]}',
      );
      expect(PermissionService.instance.getRolePermissions('Cashier').contains(PosPermissions.inventoryView), isTrue);

      // 3. Apply cloud employee permissions override
      await PermissionService.instance.applyCloudEmployeePermissions(
        'emp-cas-hier',
        '["pos.view", "inventory.view", "customers.view"]',
      );
      final empPerms = PermissionService.instance.getEmployeeCustomPermissions('emp-cas-hier');
      expect(empPerms, isNotNull);
      expect(empPerms!.contains(PosPermissions.inventoryView), isTrue);

      // Clear cloud employee override
      await PermissionService.instance.applyCloudEmployeePermissions('emp-cas-hier', null);
      expect(PermissionService.instance.getEmployeeCustomPermissions('emp-cas-hier'), isNull);

      // Cleanup
      await PermissionService.instance.resetRoleToDefault('Cashier');
    });
  });
}
