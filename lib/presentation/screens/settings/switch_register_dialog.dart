import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../theme/app_theme.dart';

class SwitchRegisterDialog extends StatefulWidget {
  final AppDatabase db;
  final String storeId;
  final String? currentRegisterId;

  const SwitchRegisterDialog({
    super.key,
    required this.db,
    required this.storeId,
    this.currentRegisterId,
  });

  @override
  State<SwitchRegisterDialog> createState() => _SwitchRegisterDialogState();
}

class _SwitchRegisterDialogState extends State<SwitchRegisterDialog> {
  List<CashRegister> _registers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRegisters();
  }

  Future<void> _loadRegisters() async {
    _registers = await widget.db.posDao.getRegistersForStore(widget.storeId);
    if (mounted) setState(() => _isLoading = false);
  }

  void _selectRegister(CashRegister register) async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.storesSwitch,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to switch POS terminals.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await DevicePrefs.setRegisterId(register.id);
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
          'You do not have permission to switch POS terminals.',
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
      title: const Text('Switch POS Terminal'),
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
                  itemCount: _registers.length,
                  itemBuilder: (context, index) {
                    final register = _registers[index];
                    final isCurrent = register.id == widget.currentRegisterId;
                    return ListTile(
                      leading: const Icon(Icons.point_of_sale_rounded),
                      title: Text(register.registerName),
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
                              onPressed: () => _selectRegister(register),
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
