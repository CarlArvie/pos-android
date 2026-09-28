import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import '../../../data/local/database.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';

class EditCompanyDialog extends StatefulWidget {
  final AppDatabase db;
  final Company company;

  const EditCompanyDialog({super.key, required this.db, required this.company});

  @override
  State<EditCompanyDialog> createState() => _EditCompanyDialogState();
}

class _EditCompanyDialogState extends State<EditCompanyDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.company.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(PosPermissions.settingsCompanyProfile)) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text('You do not have permission to edit company profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Edit Company Name'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Company Name', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (_nameController.text.trim().isEmpty) return;
            await widget.db.posDao.updateCompany(
              CompaniesCompanion(
                id: drift.Value(widget.company.id),
                name: drift.Value(_nameController.text.trim()),
              ),
            );
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
