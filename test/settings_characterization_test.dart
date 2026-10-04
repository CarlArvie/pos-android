import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:pos/presentation/models/discount_preset.dart';
import 'package:pos/presentation/screens/settings/edit_company_dialog.dart';
import 'package:pos/presentation/screens/settings/edit_discount_rules_dialog.dart';
import 'package:pos/presentation/screens/settings/settings_view.dart';
import 'package:pos/presentation/screens/settings/switch_register_dialog.dart';
import 'package:pos/presentation/screens/settings/switch_store_dialog.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'admin-001',
      'current_employee_role': 'Admin',
      'require_pin_for_unlock': true,
      'senior_pwd_discount_percent': 20.0,
      'max_custom_discount_percent': 50.0,
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('Settings Characterization Tests', () {
    testWidgets('SettingsView loads company, store, and register accurately from local DB', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Verify business profile loaded
      expect(find.text('Business Profile'), findsOneWidget);
      expect(find.text('Apex Supermarket & POS'), findsOneWidget);
      expect(find.text('Main Retail Branch'), findsWidgets); // Store name subtitle & Hardware binding subtitle
      expect(find.text('Main Checkout #1'), findsOneWidget);

      // Verify security settings
      expect(find.text('Require PIN for Quick Unlock'), findsOneWidget);
      final pinSwitch = tester.widget<SwitchListTile>(find.byKey(const Key('settings_require_pin_switch')));
      expect(pinSwitch.value, isTrue);

      // Verify discount policies
      expect(find.byKey(const Key('admin_discount_policies_card')), findsOneWidget);
      expect(find.text('20% statutory discount on qualifying items'), findsOneWidget);
      expect(find.text('Cashier cannot apply custom discounts exceeding 50%'), findsOneWidget);

      await db.close();
    });

    testWidgets('Toggling Require PIN switch immediately updates DevicePrefs', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(DevicePrefs.requirePinForUnlock, isTrue);

      // Tap the switch
      await tester.tap(find.byKey(const Key('settings_require_pin_switch')));
      await tester.pumpAndSettle();

      expect(DevicePrefs.requirePinForUnlock, isFalse);

      await db.close();
    });

    testWidgets('EditCompanyDialog updates company name in SQLite', (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      final company = await db.posDao.getCompany('default-company-001');
      expect(company, isNotNull);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditCompanyDialog(db: db, company: company!),
        ),
      ));
      await tester.pumpAndSettle();

      // Enter new name
      await tester.enterText(find.byType(TextField), 'Acme Enterprise POS');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify company in DB was updated
      final updatedCompany = await db.posDao.getCompany('default-company-001');
      expect(updatedCompany?.name, equals('Acme Enterprise POS'));

      await db.close();
    });

    testWidgets('EditDiscountRulesDialog modifies statutory rate, max cap, and presets', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: EditDiscountRulesDialog(),
        ),
      ));
      await tester.pumpAndSettle();

      // Change senior/pwd rate to 25%
      await tester.enterText(find.byKey(const Key('senior_pwd_percent_input')), '25');
      // Change max custom rate to 40%
      await tester.enterText(find.byKey(const Key('max_custom_percent_input')), '40');
      await tester.pumpAndSettle();

      // Add a custom preset
      await tester.tap(find.byKey(const Key('add_discount_preset_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('new_preset_label_input')), 'Staff Promo');
      await tester.enterText(find.byKey(const Key('new_preset_percent_input')), '15');
      await tester.tap(find.byKey(const Key('confirm_add_preset_button')));
      await tester.pumpAndSettle();

      expect(find.text('Staff Promo'), findsOneWidget);

      // Save policies
      await tester.ensureVisible(find.byKey(const Key('save_discount_rules_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_discount_rules_button')));
      await tester.pumpAndSettle();

      expect(DevicePrefs.seniorPwdDiscountPercent, equals(25.0));
      expect(DevicePrefs.maxCustomDiscountPercent, equals(40.0));
      expect(DevicePrefs.discountPresets.any((p) => p.label == 'Staff Promo'), isTrue);
    });

    testWidgets('Mobile phone (360x640) layout renders SettingsView and Dialogs without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Verify no overflow on 360x640
      expect(tester.takeException(), isNull);
      expect(find.text('Business Profile'), findsOneWidget);

      // Test EditDiscountRulesDialog on 360x640
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: EditDiscountRulesDialog()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Test SwitchStoreDialog on 360x640
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SwitchStoreDialog(db: db, companyId: 'default-company-001')),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Test SwitchRegisterDialog on 360x640
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SwitchRegisterDialog(db: db, storeId: 'default-store-001')),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await db.close();
    });
  });
}
