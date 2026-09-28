import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../theme/app_theme.dart';
import 'edit_company_dialog.dart';
import 'edit_discount_rules_dialog.dart';
import 'switch_store_dialog.dart';
import 'switch_register_dialog.dart';
import '../setup/welcome_screen.dart';
import '../auth/pin_login_screen.dart';
import '../setup/existing_business_login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync_engine.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';

class SettingsView extends StatefulWidget {
  final AppDatabase db;

  const SettingsView({super.key, required this.db});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Company? _company;
  Store? _store;
  CashRegister? _register;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final companyId = DevicePrefs.companyId;
    final storeId = DevicePrefs.storeId;
    final registerId = DevicePrefs.registerId;

    if (companyId != null) _company = await widget.db.posDao.getCompany(companyId);
    if (storeId != null) _store = await widget.db.posDao.getStore(storeId);
    if (registerId != null) _register = await widget.db.posDao.getRegister(registerId);

    if (mounted) setState(() => _isLoading = false);
  }

  void _showEditCompany() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.settingsCompanyProfile)) return;
    if (_company == null) return;
    final updated = await showDialog(
      context: context,
      builder: (_) => EditCompanyDialog(db: widget.db, company: _company!),
    );
    if (updated == true) _loadSettings();
  }

  void _showEditStore() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.settingsCompanyProfile) &&
        !PermissionService.instance.hasPermission(PosPermissions.storesManage)) {
      return;
    }
    if (_store == null) return;
    final nameController = TextEditingController(text: _store!.storeName);
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Store Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Store Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              await widget.db.posDao.updateStore(
                StoresCompanion(
                  id: drift.Value(_store!.id),
                  storeName: drift.Value(nameController.text.trim()),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == true) _loadSettings();
  }

  void _showSwitchStore() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.storesSwitch)) return;
    final companyId = DevicePrefs.companyId;
    if (companyId == null) return;

    final changed = await showDialog(
      context: context,
      builder: (_) => SwitchStoreDialog(db: widget.db, companyId: companyId, currentStoreId: _store?.id),
    );
    if (changed == true) {
      // Hard reset to login screen to apply new store constraints cleanly
      _forceLogout();
    }
  }

  void _showSwitchRegister() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.storesSwitch)) return;
    final storeId = DevicePrefs.storeId;
    if (storeId == null) return;

    final changed = await showDialog(
      context: context,
      builder: (_) => SwitchRegisterDialog(db: widget.db, storeId: storeId, currentRegisterId: _register?.id),
    );
    if (changed == true) {
      _forceLogout();
    }
  }

  bool get _isAdmin {
    final role = DevicePrefs.currentEmployeeRole?.toLowerCase() ?? '';
    return role == 'admin' ||
        PermissionService.instance.hasPermission(PosPermissions.settingsDiscounts);
  }

  void _showEditDiscountRules() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const EditDiscountRulesDialog(),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  void _forceLogout() async {
    if (!mounted) return;
    await DevicePrefs.setCurrentEmployeeId(null);
    await DevicePrefs.setCurrentEmployeeRole(null);
    final requirePin = DevicePrefs.requirePinForUnlock;
    if (!requirePin) {
      try {
        if (Supabase.instance.isInitialized) {
          await Supabase.instance.client.auth.signOut();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => requirePin
            ? PinLoginScreen(db: widget.db)
            : ExistingBusinessLoginScreen(db: widget.db),
      ),
      (route) => false,
    );
  }

  void _unbindDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unbind Device?'),
        content: const Text('This will wipe the hardware binding on this tablet and return to the Welcome screen. Local database data will remain intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Unbind', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (Supabase.instance.isInitialized) {
          await Supabase.instance.client.auth.signOut();
        }
      } catch (_) {}
      await DevicePrefs.clearProvisioning();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => WelcomeScreen(db: widget.db)),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasCompanyProfile = PermissionService.instance.hasPermission(PosPermissions.settingsCompanyProfile);
    final hasStoreManage = PermissionService.instance.hasPermission(PosPermissions.storesManage);
    final hasSecurityPolicy = PermissionService.instance.hasPermission(PosPermissions.settingsSecurityPolicy);
    final hasSyncRepair = PermissionService.instance.hasPermission(PosPermissions.settingsSyncRepair);
    final hasStoresSwitch = PermissionService.instance.hasPermission(PosPermissions.storesSwitch);
    final isSuperAdmin = (DevicePrefs.currentEmployeeRole?.toLowerCase() ?? '') == 'admin';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;
        return ListView(
          padding: EdgeInsets.all(isNarrow ? 16.0 : 24.0),
          children: [
            const Text('Business Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.cardBorderColor),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.business_rounded, color: Colors.blueGrey),
                    title: const Text('Company Name'),
                    subtitle: Text(_company?.name ?? 'Unknown'),
                    trailing: hasCompanyProfile ? const Icon(Icons.edit_rounded, size: 18) : null,
                    onTap: hasCompanyProfile ? _showEditCompany : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.storefront_rounded, color: Colors.blueGrey),
                    title: const Text('Store Name (This Location)'),
                    subtitle: Text(_store?.storeName ?? 'Unknown'),
                    trailing: (hasCompanyProfile || hasStoreManage) ? const Icon(Icons.edit_rounded, size: 18) : null,
                    onTap: (hasCompanyProfile || hasStoreManage) ? _showEditStore : null,
                  ),
                  if (hasSyncRepair) ...[
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('settings_cloud_sync_tile'),
                      leading: const Icon(Icons.cloud_sync_rounded, color: Colors.blueGrey),
                      title: const Text('Supabase Cloud Sync'),
                      subtitle: const Text('Force download latest data from the cloud.'),
                      trailing: const Icon(Icons.download_rounded, size: 18),
                      onTap: () async {
                        setState(() => _isLoading = true);
                        try {
                          final engine = SyncEngine.instance ?? SyncEngine(db: widget.db, supabase: Supabase.instance.client);
                          await engine.forcePull();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cloud sync complete!')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sync failed: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text('Security Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.cardBorderColor),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('settings_require_pin_switch'),
                    secondary: const Icon(Icons.pin_rounded, color: Colors.blueGrey),
                    title: const Text('Require PIN for Quick Unlock'),
                    subtitle: Text(hasSecurityPolicy
                        ? 'When locked, ask for a 4-digit PIN instead of the full password.'
                        : 'Security policy configuration is restricted.'),
                    value: DevicePrefs.requirePinForUnlock,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: hasSecurityPolicy
                        ? (val) async {
                            await DevicePrefs.setRequirePinForUnlock(val);
                            final companyId = DevicePrefs.companyId;
                            if (companyId != null) {
                              try {
                                await Supabase.instance.client
                                    .from('companies')
                                    .update({'require_pin': val})
                                    .eq('id', companyId);
                              } catch (_) {}
                            }
                            if (mounted) setState(() {});
                          }
                        : null,
                  ),
                ],
              ),
            ),

            if (_isAdmin) ...[
              const SizedBox(height: 32),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  const Text(
                    'Discount & Promotion Policies',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Text(
                      'ADMIN ONLY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Configure storewide statutory discount rates, cashier discount caps, and quick presets.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Card(
                key: const Key('admin_discount_policies_card'),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.cardBorderColor),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.accessibility_new_rounded, color: Colors.amber.shade800),
                      title: const Text('Senior / PWD Statutory Rate'),
                      subtitle: Text('${DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0)}% statutory discount on qualifying items'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Text(
                          '${DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0)}%',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_rounded, color: AppTheme.primaryColor),
                      title: const Text('Maximum Cashier Discount Cap'),
                      subtitle: Text('Cashier cannot apply custom discounts exceeding ${DevicePrefs.maxCustomDiscountPercent.toStringAsFixed(0)}%'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${DevicePrefs.maxCustomDiscountPercent.toStringAsFixed(0)}% max',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.bookmark_added_rounded, color: AppTheme.accentColor),
                      title: const Text('Active Discount Presets'),
                      subtitle: Text('${DevicePrefs.discountPresets.length} presets configured for POS Counter'),
                      trailing: OutlinedButton(
                        key: const Key('edit_discount_rules_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showEditDiscountRules,
                        child: const Text('Edit Rules'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            const Text('Hardware Binding (This Tablet)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 8),
            const Text('Changing these will immediately log you out to apply the new location context.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.cardBorderColor),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor),
                    title: const Text('Active Store Branch'),
                    subtitle: Text(_store?.storeName ?? 'None'),
                    trailing: hasStoresSwitch
                        ? OutlinedButton(
                            key: const Key('switch_store_button'),
                            onPressed: _showSwitchStore,
                            child: const Text('Switch'),
                          )
                        : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.point_of_sale_rounded, color: AppTheme.primaryColor),
                    title: const Text('Active POS Terminal'),
                    subtitle: Text(_register?.registerName ?? 'None'),
                    trailing: hasStoresSwitch
                        ? OutlinedButton(
                            key: const Key('switch_register_button'),
                            onPressed: _showSwitchRegister,
                            child: const Text('Switch'),
                          )
                        : null,
                  ),
                ],
              ),
            ),

            if (isSuperAdmin) ...[
              const SizedBox(height: 48),
              const Text('Danger Zone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade200),
                ),
                child: ListTile(
                  leading: Icon(Icons.phonelink_erase_rounded, color: Colors.red.shade700),
                  title: Text('Unbind Device', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                  subtitle: Text('Wipe the hardware binding and return to setup.', style: TextStyle(color: Colors.red.shade700)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: _unbindDevice,
                    child: const Text('Unbind'),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

