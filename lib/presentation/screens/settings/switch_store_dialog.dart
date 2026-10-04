import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../theme/app_theme.dart';

class SwitchStoreDialog extends StatefulWidget {
  final AppDatabase db;
  final String companyId;
  final String? currentStoreId;

  const SwitchStoreDialog({
    super.key,
    required this.db,
    required this.companyId,
    this.currentStoreId,
  });

  @override
  State<SwitchStoreDialog> createState() => _SwitchStoreDialogState();
}

class _SwitchStoreDialogState extends State<SwitchStoreDialog> {
  List<Store> _stores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    _stores = await widget.db.posDao.getStores(widget.companyId);
    if (mounted) setState(() => _isLoading = false);
  }

  void _selectStore(Store store) async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.storesSwitch,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to switch store branches.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final registers = await widget.db.posDao.getRegistersForStore(store.id);
    if (registers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot switch: This store has no POS terminals.'),
        ),
      );
      return;
    }

    // Bind device to new store and its first register
    await DevicePrefs.setStoreId(store.id);
    await DevicePrefs.setRegisterId(registers.first.id);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.storesSwitch,
    )) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'You do not have permission to switch store branches.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Switch Store Branch'),
      content: _isLoading
          ? const SizedBox(
              width: 300,
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 400,
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: SizedBox(
                width: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _stores.length,
                  itemBuilder: (context, index) {
                    final store = _stores[index];
                    final isCurrent = store.id == widget.currentStoreId;
                    return ListTile(
                      leading: const Icon(Icons.storefront_rounded),
                      title: Text(store.storeName),
                      trailing: isCurrent
                          ? const Text(
                              'Active',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(64, 44),
                              ),
                              onPressed: () => _selectStore(store),
                              child: const Text('Select'),
                            ),
                    );
                  },
                ),
              ),
            ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
