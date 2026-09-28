import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../theme/app_theme.dart';
import 'add_store_dialog.dart';

class StoresManagementView extends StatefulWidget {
  final AppDatabase db;

  const StoresManagementView({super.key, required this.db});

  @override
  State<StoresManagementView> createState() => _StoresManagementViewState();
}

class _StoresManagementViewState extends State<StoresManagementView> {
  List<Store> _stores = [];
  final Map<String, List<CashRegister>> _storeRegisters = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoading = true);
    final companyId = DevicePrefs.companyId;
    if (companyId != null) {
      _stores = await widget.db.posDao.getStores(companyId);
      _storeRegisters.clear();
      for (final s in _stores) {
        _storeRegisters[s.id] = await widget.db.posDao.getRegistersForStore(s.id);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showAddStoreDialog() async {
    if (!PermissionService.instance.hasPermission(PosPermissions.storesManage)) return;
    final bool? added = await showDialog(
      context: context,
      builder: (_) => AddStoreDialog(db: widget.db),
    );
    if (added == true) {
      _loadStores();
    }
  }

  Future<void> _switchToRegister(Store store, CashRegister register) async {
    if (!PermissionService.instance.hasPermission(PosPermissions.storesSwitch)) return;
    await DevicePrefs.setStoreId(store.id);
    await DevicePrefs.setRegisterId(register.id);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${store.storeName} — ${register.registerName}'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasStoresManage = PermissionService.instance.hasPermission(PosPermissions.storesManage);
    final hasStoresSwitch = PermissionService.instance.hasPermission(PosPermissions.storesSwitch);
    final currentStoreId = DevicePrefs.storeId;
    final currentRegisterId = DevicePrefs.registerId;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Locations & Terminals',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (hasStoresManage)
                ElevatedButton.icon(
                  key: const Key('add_store_button'),
                  onPressed: _showAddStoreDialog,
                  icon: const Icon(Icons.add_business_rounded),
                  label: const Text('Add Store'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _stores.isEmpty
                ? const Center(child: Text('No stores found.'))
                : ListView.builder(
                    itemCount: _stores.length,
                    itemBuilder: (context, index) {
                      final store = _stores[index];
                      final isCurrentStore = store.id == currentStoreId;
                      final registers = _storeRegisters[store.id] ?? [];

                      return Card(
                        key: Key('store_card_${store.id}'),
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isCurrentStore ? AppTheme.primaryColor.withValues(alpha: 0.5) : AppTheme.cardBorderColor,
                            width: isCurrentStore ? 1.5 : 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Store Header
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isCurrentStore
                                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                                        : Colors.grey.shade100,
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      color: isCurrentStore ? AppTheme.primaryColor : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                store.storeName,
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCurrentStore) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.inStockColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'ACTIVE STORE',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.inStockColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          store.address != null && store.address!.isNotEmpty
                                              ? store.address!
                                              : 'No address provided',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                        if (store.phone != null && store.phone!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(Icons.phone_outlined, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(
                                                store.phone!,
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20, thickness: 0.8),

                              // Registers / Terminals List
                              Row(
                                children: [
                                  const Icon(Icons.point_of_sale_rounded, size: 15, color: Colors.blueGrey),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Active Terminals (${registers.length})',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (registers.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: Text('No terminals configured for this branch.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                )
                              else
                                ...registers.map((reg) {
                                  final isCurrentRegister = reg.id == currentRegisterId;
                                  return Container(
                                    key: Key('terminal_tile_${reg.id}'),
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isCurrentRegister
                                          ? AppTheme.primaryColor.withValues(alpha: 0.05)
                                          : Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCurrentRegister
                                            ? AppTheme.primaryColor.withValues(alpha: 0.3)
                                            : AppTheme.cardBorderColor,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.desktop_windows_rounded,
                                          size: 16,
                                          color: isCurrentRegister ? AppTheme.primaryColor : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            reg.registerName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isCurrentRegister ? FontWeight.bold : FontWeight.w500,
                                              color: isCurrentRegister ? AppTheme.primaryColor : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isCurrentRegister)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.inStockColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'ACTIVE HERE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.inStockColor,
                                              ),
                                            ),
                                          )
                                        else if (hasStoresSwitch)
                                          OutlinedButton(
                                            key: Key('switch_to_terminal_${reg.id}'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                              visualDensity: VisualDensity.compact,
                                              side: const BorderSide(color: AppTheme.primaryColor),
                                            ),
                                            onPressed: () => _switchToRegister(store, reg),
                                            child: const Text('Switch', style: TextStyle(fontSize: 11)),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
