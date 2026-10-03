import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  const storeId = 'default-store-001';
  const companyId = 'default-company-001';

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': companyId,
      'provisioned_store_id': storeId,
      'current_employee_id': 'admin-tester-001',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);

    db = AppDatabase(NativeDatabase.memory());
    await DatabaseSeeder.seedIfEmpty(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Staff & Cashier Characterization Tests', () {
    test('Employee retrieval and filtering for store', () async {
      final initialEmployees = await db.posDao.getEmployeesForStore(storeId);
      expect(initialEmployees.isNotEmpty, isTrue);

      final initialCount = initialEmployees.length;

      // Add a new cashier employee
      final newCashierId = const Uuid().v4();
      await db.posDao.addEmployee(EmployeesCompanion.insert(
        id: newCashierId,
        companyId: companyId,
        storeId: const Value(storeId),
        firstName: 'Maria',
        lastName: 'Santos',
        position: const Value('Cashier'),
        pinCode: const Value('4321'),
      ));

      final updatedEmployees = await db.posDao.getEmployeesForStore(storeId);
      expect(updatedEmployees.length, equals(initialCount + 1));
      expect(updatedEmployees.any((e) => e.id == newCashierId), isTrue);

      final added = updatedEmployees.firstWhere((e) => e.id == newCashierId);
      expect(added.firstName, equals('Maria'));
      expect(added.lastName, equals('Santos'));
      expect(added.position, equals('Cashier'));
      expect(added.pinCode, equals('4321'));
      expect(added.isActive, isTrue);
    });

    test('Updating employee PIN and authentication verification', () async {
      final employees = await db.posDao.getEmployeesForStore(storeId);
      final targetEmp = employees.first;

      // Update PIN
      const newPin = '7890';
      await db.posDao.updateEmployeePin(targetEmp.id, newPin);

      // Verify old PIN fails and new PIN succeeds
      final oldAuth = await db.posDao.getEmployeeByPin(storeId, targetEmp.pinCode ?? '0000');
      if (targetEmp.pinCode != newPin) {
        expect(oldAuth?.id, isNot(targetEmp.id));
      }

      final newAuth = await db.posDao.getEmployeeByPin(storeId, newPin);
      expect(newAuth, isNotNull);
      expect(newAuth!.id, equals(targetEmp.id));
      expect(newAuth.pinCode, equals(newPin));
    });

    test('Updating employee role / position', () async {
      final employees = await db.posDao.getEmployeesForStore(storeId);
      final cashier = employees.firstWhere((e) => e.position.toLowerCase() == 'cashier');

      // Promote cashier to Manager
      await db.posDao.updateEmployeeRole(cashier.id, 'Manager');

      final refreshed = await (db.select(db.employees)..where((e) => e.id.equals(cashier.id))).getSingle();
      expect(refreshed.position, equals('Manager'));
    });

    test('Toggling employee active status and query behavior', () async {
      final employees = await db.posDao.getEmployeesForStore(storeId);
      final target = employees.first;

      // Deactivate employee
      await db.posDao.updateEmployeeActive(target.id, false);

      final directCheck = await (db.select(db.employees)..where((e) => e.id.equals(target.id))).getSingle();
      expect(directCheck.isActive, isFalse);

      // Verify that deactivated employee cannot login via PIN
      final pinLogin = await db.posDao.getEmployeeByPin(storeId, target.pinCode ?? '1234');
      expect(pinLogin, isNull);

      // Re-activate employee
      await db.posDao.updateEmployeeActive(target.id, true);
      final reactivated = await (db.select(db.employees)..where((e) => e.id.equals(target.id))).getSingle();
      expect(reactivated.isActive, isTrue);
    });

    test('Custom role creation, assignment, and permission overrides', () async {
      const customRole = 'Shift Supervisor';

      // 1. Create custom role template
      final supervisorPerms = {
        PosPermissions.posView,
        PosPermissions.posDiscountPreset,
        PosPermissions.transactionsViewAll,
        PosPermissions.reportsView,
      };

      await PermissionService.instance.createCustomRole(customRole, supervisorPerms);
      expect(PermissionService.instance.getAllRoles().contains(customRole), isTrue);
      expect(PermissionService.instance.getCustomRoles().contains(customRole), isTrue);
      expect(PermissionService.instance.getRolePermissions(customRole), equals(supervisorPerms));

      // 2. Add an employee with custom role
      final empId = const Uuid().v4();
      await db.posDao.addEmployee(EmployeesCompanion.insert(
        id: empId,
        companyId: companyId,
        firstName: 'Elena',
        lastName: 'Reyes',
        position: const Value(customRole),
        pinCode: const Value('5555'),
      ));

      // 3. Test employee custom override takes precedence
      expect(PermissionService.instance.getEmployeeCustomPermissions(empId), isNull);

      // Add override removing discount permission
      final overridePerms = Set<String>.from(supervisorPerms)..remove(PosPermissions.posDiscountPreset);
      await PermissionService.instance.setEmployeeCustomPermissions(empId, overridePerms);

      expect(PermissionService.instance.getEmployeeCustomPermissions(empId), equals(overridePerms));

      // 4. Clean up / reset override
      await PermissionService.instance.setEmployeeCustomPermissions(empId, null);
      expect(PermissionService.instance.getEmployeeCustomPermissions(empId), isNull);
    });

    test('Volume test: 100 staff members load and filter without errors [Verified]', () async {
      final companions = List.generate(
        100,
        (i) => EmployeesCompanion.insert(
          id: 'bulk-emp-$i',
          companyId: companyId,
          storeId: const Value(storeId),
          firstName: 'Employee$i',
          lastName: 'Test',
          position: Value(i % 3 == 0 ? 'Manager' : 'Cashier'),
          pinCode: Value((1000 + i).toString()),
          isActive: Value(i % 10 != 0), // 10% inactive
        ),
      );

      await db.batch((batch) {
        batch.insertAll(db.employees, companions);
      });

      final allStoreEmployees = await (db.select(db.employees)
            ..where((e) => e.storeId.equals(storeId))
            ..orderBy([(e) => OrderingTerm.asc(e.firstName)]))
          .get();

      expect(allStoreEmployees.length, greaterThanOrEqualTo(100));

      final activeOnly = allStoreEmployees.where((e) => e.isActive).toList();
      final inactiveOnly = allStoreEmployees.where((e) => !e.isActive).toList();

      expect(activeOnly.isNotEmpty, isTrue);
      expect(inactiveOnly.isNotEmpty, isTrue);
    });
  });
}
