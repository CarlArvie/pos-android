import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos/core/device_prefs.dart';
import 'package:pos/core/permissions/permission_service.dart';
import 'package:pos/data/local/database.dart';
import 'package:pos/presentation/theme/app_theme.dart';
import 'package:pos/presentation/widgets/counter/price_override_dialog.dart';
import 'package:pos/presentation/widgets/counter/custom_discount_dialog.dart';
import 'package:pos/presentation/widgets/counter/quantity_input_dialog.dart';
import 'package:pos/presentation/widgets/counter/cash_adjustment_dialog.dart';
import 'package:pos/presentation/widgets/counter/close_shift_dialog.dart';
import 'package:pos/presentation/screens/settings/settings_view.dart';
import 'package:pos/presentation/screens/settings/edit_discount_rules_dialog.dart';
import 'package:pos/core/permissions/pos_permissions.dart';
import 'package:pos/presentation/screens/counter_view.dart';
import 'package:pos/data/local/seed_data.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'provisioned_register_id': 'default-reg-001',
      'provisioned_company_id': 'default-company-001',
      'provisioned_store_id': 'default-store-001',
      'current_employee_id': 'default-emp-001',
      'current_employee_role': 'Admin',
    });
    await DevicePrefs.init();
    await PermissionService.instance.init(force: true);
  });

  group('PriceOverrideDialog', () {
    testWidgets('Displays product info, accepts numpad input, and returns new price', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      double? resultPrice;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultPrice = await showDialog<double>(
                  context: context,
                  builder: (_) => const PriceOverrideDialog(
                    productName: 'Special Brew Coffee',
                    currentPrice: 120.0,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Price Override'), findsOneWidget);
      expect(find.text('Special Brew Coffee'), findsOneWidget);
      expect(find.text('Original Price:'), findsOneWidget);
      expect(find.text('₱120.00'), findsOneWidget);

      // Clear existing input
      await tester.tap(find.byKey(const Key('numpad_key_clear')));
      await tester.pumpAndSettle();

      // Enter 150 using numpad
      await tester.tap(find.byKey(const Key('numpad_key_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_key_5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('numpad_key_0')));
      await tester.pumpAndSettle();

      expect(find.text('150'), findsOneWidget);

      // Confirm
      await tester.ensureVisible(find.byKey(const Key('confirm_price_override_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_price_override_button')));
      await tester.pumpAndSettle();

      expect(resultPrice, 150.0);
    });
  });

  group('CustomDiscountDialog', () {
    testWidgets('Percentage custom discount calculates correctly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CustomDiscountResult? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CustomDiscountResult>(
                  context: context,
                  builder: (_) => const CustomDiscountDialog(
                    cartSubtotal: 500.0,
                    hasSeniorPwdPreset: true,
                  ),
                );
              },
              child: const Text('Open Discount'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Discount'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Apply Discount'), findsOneWidget);
      expect(find.text('Cart Subtotal:'), findsOneWidget);
      expect(find.text('₱500.00'), findsOneWidget);

      // Enter 15% discount
      await tester.enterText(find.byKey(const Key('discount_value_input')), '15');
      await tester.pumpAndSettle();

      // 15% of 500 is 75.00
      expect(find.text('-₱75.00'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('apply_custom_discount_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply_custom_discount_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, 'percent');
      expect(result!.amount, 75.0);
      expect(result!.inputValue, 15.0);
    });

    testWidgets('Fixed peso discount works correctly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CustomDiscountResult? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CustomDiscountResult>(
                  context: context,
                  builder: (_) => const CustomDiscountDialog(
                    cartSubtotal: 400.0,
                    hasSeniorPwdPreset: true,
                  ),
                );
              },
              child: const Text('Open Discount'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Discount'));
      await tester.pumpAndSettle();

      // Switch to fixed amount mode
      await tester.tap(find.byKey(const Key('discount_mode_fixed')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('discount_value_input')), '50');
      await tester.pumpAndSettle();

      expect(find.text('-₱50.00'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('apply_custom_discount_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply_custom_discount_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, 'fixed');
      expect(result!.amount, 50.0);
      expect(result!.inputValue, 50.0);
    });

    testWidgets('Senior/PWD quick button returns 20% discount', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CustomDiscountResult? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CustomDiscountResult>(
                  context: context,
                  builder: (_) => const CustomDiscountDialog(
                    cartSubtotal: 1000.0,
                    hasSeniorPwdPreset: true,
                  ),
                );
              },
              child: const Text('Open Discount'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Discount'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('senior_pwd_preset_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.amount, 200.0);
      expect(result!.inputValue, 20.0);
    });
  });

  group('QuantityInputDialog', () {
    testWidgets('Direct quantity input for discrete items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      double? resultQty;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultQty = await showDialog<double>(
                  context: context,
                  builder: (_) => const QuantityInputDialog(
                    productName: 'Mineral Water 500ml',
                    currentQuantity: 1.0,
                    isDecimal: false,
                    unit: 'pcs',
                  ),
                );
              },
              child: const Text('Open Qty'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Qty'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Set Quantity'), findsOneWidget);
      expect(find.text('Mineral Water 500ml'), findsOneWidget);

      // Clear
      await tester.tap(find.byKey(const Key('qty_numpad_C')));
      await tester.pumpAndSettle();

      // Enter 24 pcs
      await tester.tap(find.byKey(const Key('qty_numpad_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qty_numpad_4')));
      await tester.pumpAndSettle();

      expect(find.text('24'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('confirm_quantity_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_quantity_button')));
      await tester.pumpAndSettle();

      expect(resultQty, 24.0);
    });

    testWidgets('Decimal quantity input for weighed items with decimal point', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      double? resultQty;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultQty = await showDialog<double>(
                  context: context,
                  builder: (_) => const QuantityInputDialog(
                    productName: 'Fresh Pork Belly',
                    currentQuantity: 0.5,
                    isDecimal: true,
                    unit: 'kg',
                  ),
                );
              },
              child: const Text('Open Qty'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Qty'));
      await tester.pumpAndSettle();

      // Clear using clear button
      await tester.tap(find.byKey(const Key('qty_numpad_C')));
      await tester.pumpAndSettle();

      // Enter 1.75 kg
      await tester.tap(find.byKey(const Key('qty_numpad_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qty_numpad_.')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qty_numpad_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qty_numpad_5')));
      await tester.pumpAndSettle();

      expect(find.text('1.75'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('confirm_quantity_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_quantity_button')));
      await tester.pumpAndSettle();

      expect(resultQty, 1.75);
    });
  });

  group('CashAdjustmentDialog', () {
    testWidgets('Records Pay In with reason suggestion chip', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CashAdjustmentResult? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CashAdjustmentResult>(
                  context: context,
                  builder: (_) => const CashAdjustmentDialog(initialType: 'pay_in'),
                );
              },
              child: const Text('Open Adjustment'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Adjustment'));
      await tester.pumpAndSettle();

      expect(find.text('Cash Drawer Adjustment'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('cash_adjustment_amount_input')), '1500');
      await tester.pumpAndSettle();

      // Tap suggestion chip for "Change Fund Added"
      await tester.tap(find.byKey(const Key('reason_chip_Change_Fund_Added')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('confirm_cash_adjustment_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_cash_adjustment_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, 'pay_in');
      expect(result!.amount, 1500.0);
      expect(result!.reason, 'Change Fund Added');
    });

    testWidgets('Records Pay Out with custom typed reason', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CashAdjustmentResult? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CashAdjustmentResult>(
                  context: context,
                  builder: (_) => const CashAdjustmentDialog(initialType: 'pay_out'),
                );
              },
              child: const Text('Open Adjustment'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Adjustment'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('cash_adjustment_amount_input')), '350.50');
      await tester.enterText(find.byKey(const Key('cash_adjustment_reason_input')), 'Grab delivery tip');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('confirm_cash_adjustment_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_cash_adjustment_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, 'pay_out');
      expect(result!.amount, 350.50);
      expect(result!.reason, 'Grab delivery tip');
    });
  });

  group('Blind Close Shift Enforcement', () {
    testWidgets('Cashier with posShiftBlindClose sees hidden expected balance', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Re-init as Cashier
      SharedPreferences.setMockInitialValues({
        'provisioned_register_id': 'default-reg-001',
        'provisioned_company_id': 'default-company-001',
        'provisioned_store_id': 'default-store-001',
        'current_employee_id': 'cashier-001',
        'current_employee_role': 'Cashier',
      });
      await DevicePrefs.init();
      await PermissionService.instance.init(force: true);

      final db = AppDatabase(NativeDatabase.memory());

      final dummyShift = CashManagement(
        id: 'shift-blind-001',
        companyId: 'default-company-001',
        storeId: 'default-store-001',
        cashRegisterId: 'default-reg-001',
        employeeId: 'cashier-001',
        openTime: DateTime.now(),
        openingBalance: 1000.0,
        status: 'open',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CloseShiftDialog(
            db: db,
            shift: dummyShift,
            registerName: 'Main Checkout #1',
            onShiftClosed: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Blind Close note should show
      expect(find.text('Blind Count Active: Expected totals hidden for security.'), findsOneWidget);
      expect(find.text('Counted Cash in Drawer'), findsOneWidget);

      // Expected Cash and variance MUST be hidden
      expect(find.text('Expected Cash in Drawer'), findsNothing);

      // Restore Admin
      SharedPreferences.setMockInitialValues({
        'provisioned_register_id': 'default-reg-001',
        'provisioned_company_id': 'default-company-001',
        'provisioned_store_id': 'default-store-001',
        'current_employee_id': 'default-emp-001',
        'current_employee_role': 'Admin',
      });
      await DevicePrefs.init();
      await PermissionService.instance.init(force: true);

      await db.close();
    });
  });

  group('Admin Discount Settings & Policy Enforcement', () {
    testWidgets('Custom discount exceeding Admin cap displays warning and disables apply', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Admin set cap to 30%
      await DevicePrefs.setMaxCustomDiscountPercent(30.0);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: CustomDiscountDialog(cartSubtotal: 1000.0, hasSeniorPwdPreset: true),
        ),
      ));
      await tester.pumpAndSettle();

      // Enter 40% discount (exceeds 30% cap)
      await tester.enterText(find.byKey(const Key('discount_value_input')), '40');
      await tester.pumpAndSettle();

      // Warning should show
      expect(find.byKey(const Key('discount_exceed_cap_warning')), findsOneWidget);
      expect(find.text('Exceeds maximum limit of 30% set by Admin.'), findsOneWidget);

      // Apply button should be disabled (not tap)
      final btn = tester.widget<ElevatedButton>(find.byKey(const Key('apply_custom_discount_button')));
      expect(btn.onPressed, isNull);

      // Restore default 50% cap
      await DevicePrefs.setMaxCustomDiscountPercent(50.0);
    });

    testWidgets('Admin can configure Senior/PWD discount to 25% and dialog returns 25%', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await DevicePrefs.setSeniorPwdDiscountPercent(25.0);

      CustomDiscountResult? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<CustomDiscountResult>(
                  context: context,
                  builder: (_) => const CustomDiscountDialog(
                    cartSubtotal: 1000.0,
                    hasSeniorPwdPreset: true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Senior Citizen / PWD — 25% Off'), findsOneWidget);
      expect(find.text('-₱250.00 deducted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('senior_pwd_preset_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.inputValue, 25.0);
      expect(result!.amount, 250.0);

      // Restore default
      await DevicePrefs.setSeniorPwdDiscountPercent(20.0);
    });

    testWidgets('SettingsView displays Discount Policies for Admin and hides for Cashier', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());

      // 1. As Admin
      await DevicePrefs.setCurrentEmployeeRole('Admin');
      await PermissionService.instance.init(force: true);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Discount & Promotion Policies'), findsOneWidget);
      expect(find.text('ADMIN ONLY'), findsOneWidget);
      expect(find.byKey(const Key('admin_discount_policies_card')), findsOneWidget);
      expect(find.byKey(const Key('edit_discount_rules_button')), findsOneWidget);

      // 2. As Cashier
      await DevicePrefs.setCurrentEmployeeRole('Cashier');
      await PermissionService.instance.init(force: true);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADMIN ONLY'), findsNothing);
      expect(find.byKey(const Key('admin_discount_policies_card')), findsNothing);

      // Restore
      await DevicePrefs.setCurrentEmployeeRole('Admin');
      await PermissionService.instance.init(force: true);
      await db.close();
    });

    testWidgets('EditDiscountRulesDialog saves new rates and presets correctly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: EditDiscountRulesDialog()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Discount & Promotion Policies'), findsOneWidget);

      // Update Senior/PWD rate to 30% using chip
      await tester.tap(find.widgetWithText(ActionChip, '30%').first);
      await tester.pumpAndSettle();

      // Update Max custom to 100% using chip
      await tester.tap(find.widgetWithText(ActionChip, '100%'));
      await tester.pumpAndSettle();

      // Add a custom preset
      await tester.tap(find.byKey(const Key('add_discount_preset_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('new_preset_label_input')), 'Staff Holiday');
      await tester.enterText(find.byKey(const Key('new_preset_percent_input')), '15');
      await tester.tap(find.byKey(const Key('confirm_add_preset_button')));
      await tester.pumpAndSettle();

      expect(find.text('Staff Holiday'), findsOneWidget);

      // Save rules
      await tester.ensureVisible(find.byKey(const Key('save_discount_rules_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_discount_rules_button')));
      await tester.pumpAndSettle();

      expect(DevicePrefs.seniorPwdDiscountPercent, 30.0);
      expect(DevicePrefs.maxCustomDiscountPercent, 100.0);

      final hasHolidayPreset = DevicePrefs.discountPresets.any((p) => p.label == 'Staff Holiday' && p.percent == 15.0);
      expect(hasHolidayPreset, isTrue);

      // Reset to defaults
      await DevicePrefs.setSeniorPwdDiscountPercent(20.0);
      await DevicePrefs.setMaxCustomDiscountPercent(50.0);
    });

    testWidgets('SettingsView and EditDiscountRulesDialog render on narrow mobile screen (272px width) without RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(272, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());

      await DevicePrefs.setCurrentEmployeeRole('Admin');
      await PermissionService.instance.init(force: true);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsView(db: db)),
      ));
      await tester.pumpAndSettle();

      // Scroll down to reveal discount policies card
      await tester.scrollUntilVisible(
        find.text('Discount & Promotion Policies'),
        100.0,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      // Assert Discount policies card and Admin tag render cleanly without throwing RenderFlex overflow
      expect(find.text('Discount & Promotion Policies'), findsOneWidget);
      expect(find.text('ADMIN ONLY'), findsOneWidget);
      expect(find.byKey(const Key('admin_discount_policies_card')), findsOneWidget);

      // Assert zero RenderFlex overflows in SettingsView
      expect(tester.takeException(), isNull);

      // Tap Edit Rules to open dialog on 272px width
      await tester.ensureVisible(find.byKey(const Key('edit_discount_rules_button')));
      await tester.pumpAndSettle();

      final previousOnError = FlutterError.onError;
      FlutterErrorDetails? caughtDetails;
      FlutterError.onError = (FlutterErrorDetails details) {
        caughtDetails = details;
      };

      await tester.tap(find.byKey(const Key('edit_discount_rules_button')));
      await tester.pumpAndSettle();

      FlutterError.onError = previousOnError;

      expect(find.byType(EditDiscountRulesDialog), findsOneWidget);
      expect(caughtDetails, isNull, reason: 'Expected zero RenderFlex overflows in EditDiscountRulesDialog');
      expect(tester.takeException(), isNull);

      await db.close();
    });
  });

  group('Process Checkout Permission (posSell) Enforcement', () {
    testWidgets('Cashier without posSell cannot see Charge button, sees Checkout Restricted instead', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Setup Cashier without posSell
      SharedPreferences.setMockInitialValues({
        'provisioned_register_id': 'default-reg-001',
        'provisioned_company_id': 'default-company-001',
        'provisioned_store_id': 'default-store-001',
        'current_employee_id': 'cashier-001',
        'current_employee_role': 'Cashier',
      });
      await DevicePrefs.init();
      await PermissionService.instance.init(force: true);

      // Custom override: explicitly revoke posSell from Cashier
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-001', {
        PosPermissions.posView,
        PosPermissions.posDiscountPreset,
        PosPermissions.posHoldCart,
      });

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CounterView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Add item to cart via barcode
      await tester.enterText(find.byKey(const Key('counter_barcode_search_input')), '480001005');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify Charge button is NOT visible
      expect(find.byKey(const Key('charge_checkout_button')), findsNothing);

      // Verify Checkout Restricted notice is shown instead
      expect(find.byKey(const Key('checkout_restricted_notice')), findsOneWidget);
      expect(find.text('Checkout Restricted'), findsOneWidget);

      await db.close();
    });

    testWidgets('Cashier with posSell can see Charge button normally', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'provisioned_register_id': 'default-reg-001',
        'provisioned_company_id': 'default-company-001',
        'provisioned_store_id': 'default-store-001',
        'current_employee_id': 'cashier-001',
        'current_employee_role': 'Cashier',
      });
      await DevicePrefs.init();
      await PermissionService.instance.init(force: true);

      // Grant posSell
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-001', {
        PosPermissions.posView,
        PosPermissions.posSell,
      });

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CounterView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Add item to cart via barcode
      await tester.enterText(find.byKey(const Key('counter_barcode_search_input')), '480001005');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify Charge button IS visible
      expect(find.byKey(const Key('charge_checkout_button')), findsOneWidget);
      expect(find.byKey(const Key('checkout_restricted_notice')), findsNothing);

      await db.close();
    });

    testWidgets('Mobile view hides Checkout button when posSell is revoked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'provisioned_register_id': 'default-reg-001',
        'provisioned_company_id': 'default-company-001',
        'provisioned_store_id': 'default-store-001',
        'current_employee_id': 'cashier-001',
        'current_employee_role': 'Cashier',
      });
      await DevicePrefs.init();
      await PermissionService.instance.init(force: true);

      // Revoke posSell
      await PermissionService.instance.setEmployeeCustomPermissions('cashier-001', {
        PosPermissions.posView,
      });

      final db = AppDatabase(NativeDatabase.memory());
      await DatabaseSeeder.seedIfEmpty(db);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CounterView(db: db),
        ),
      ));
      await tester.pumpAndSettle();

      // Add item to cart via barcode
      await tester.enterText(find.byKey(const Key('counter_barcode_search_input')), '480001005');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify mobile_checkout_button is NOT visible
      expect(find.byKey(const Key('mobile_checkout_button')), findsNothing);

      // View Cart button is visible instead
      expect(find.byKey(const Key('mobile_view_empty_cart_button')), findsOneWidget);
      expect(find.text('View Cart'), findsOneWidget);

      await db.close();
    });
  });
}

