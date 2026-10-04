import 'package:flutter/material.dart';
import '../../../core/device_prefs.dart';
import '../../../core/permissions/pos_permissions.dart';
import '../../../core/permissions/permission_service.dart';
import '../../models/discount_preset.dart';
import '../../theme/app_theme.dart';

/// Modal dialog to configure store discount rules,
/// statutory Senior/PWD rates, maximum cashier discount limits, and quick presets.
class EditDiscountRulesDialog extends StatefulWidget {
  const EditDiscountRulesDialog({super.key});

  @override
  State<EditDiscountRulesDialog> createState() =>
      _EditDiscountRulesDialogState();
}

class _EditDiscountRulesDialogState extends State<EditDiscountRulesDialog> {
  late TextEditingController _seniorPwdController;
  late TextEditingController _maxCustomController;
  late List<DiscountPreset> _presets;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _seniorPwdController = TextEditingController(
      text: DevicePrefs.seniorPwdDiscountPercent.toStringAsFixed(0),
    );
    _maxCustomController = TextEditingController(
      text: DevicePrefs.maxCustomDiscountPercent.toStringAsFixed(0),
    );
    _presets = List.from(DevicePrefs.discountPresets);
  }

  @override
  void dispose() {
    _seniorPwdController.dispose();
    _maxCustomController.dispose();
    super.dispose();
  }

  void _addPreset() {
    final labelCtrl = TextEditingController();
    final pctCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Add Discount Preset',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('new_preset_label_input'),
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Preset Name',
                  hintText: 'e.g. Employee Discount, VIP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('new_preset_percent_input'),
                controller: pctCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Discount Percentage (%)',
                  hintText: 'e.g. 10 or 15',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_add_preset_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 44),
            ),
            onPressed: () {
              final label = labelCtrl.text.trim();
              final pct = double.tryParse(pctCtrl.text.trim());
              if (label.isEmpty || pct == null || pct <= 0 || pct > 100) return;

              setState(() {
                _presets.add(
                  DiscountPreset(
                    id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
                    label: label,
                    percent: pct,
                    isSystem: false,
                  ),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add Preset'),
          ),
        ],
      ),
    );
  }

  void _removePreset(int index) {
    if (_presets[index].isSystem) return;
    setState(() {
      _presets.removeAt(index);
    });
  }

  Future<void> _saveRules() async {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.settingsDiscounts,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: You do not have permission to edit discount rules.',
          ),
        ),
      );
      return;
    }

    final seniorVal = double.tryParse(_seniorPwdController.text.trim());
    final maxVal = double.tryParse(_maxCustomController.text.trim());

    if (seniorVal == null || seniorVal <= 0 || seniorVal > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Senior/PWD percentage (1-100%).'),
        ),
      );
      return;
    }

    if (maxVal == null || maxVal <= 0 || maxVal > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Max Custom percentage (1-100%).'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await DevicePrefs.setSeniorPwdDiscountPercent(seniorVal);
      await DevicePrefs.setMaxCustomDiscountPercent(maxVal);

      // Update the system preset percentage if it exists in the list
      final updatedPresets = _presets.map((p) {
        if (p.isSystem) {
          return DiscountPreset(
            id: p.id,
            label: p.label,
            percent: seniorVal,
            isSystem: true,
          );
        }
        return p;
      }).toList();

      await DevicePrefs.setDiscountPresets(updatedPresets);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Discount rules updated successfully!'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save discount rules: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.hasPermission(
      PosPermissions.settingsDiscounts,
    )) {
      return AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'You do not have permission to edit discount rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 400;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isNarrow ? 14 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.discount_rounded,
                      color: AppTheme.accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discount & Promotion Policies',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          'Configure storewide discount limits (Admin Only)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 1: Senior / PWD Statutory Rate
              Container(
                padding: EdgeInsets.all(isNarrow ? 12 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.accessibility_new_rounded,
                          size: 18,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Senior Citizen & PWD Rate',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Statutory rate under Philippine law (RA 9994 / RA 10754).',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const Key('senior_pwd_percent_input'),
                      controller: _seniorPwdController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Senior/PWD Rate (%)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [20, 25, 30].map((rate) {
                        return ActionChip(
                          label: Text('$rate%'),
                          labelStyle: const TextStyle(fontSize: 11.5),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _seniorPwdController.text = rate.toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Section 2: Max Custom Discount Limit
              Container(
                padding: EdgeInsets.all(isNarrow ? 12 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Maximum Cashier Discount Cap',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Highest percentage a cashier or staff can apply manually.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const Key('max_custom_percent_input'),
                      controller: _maxCustomController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Max Allowed Discount (%)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [30, 50, 100].map((rate) {
                        return ActionChip(
                          label: Text('$rate%'),
                          labelStyle: const TextStyle(fontSize: 11.5),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _maxCustomController.text = rate.toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Section 3: Quick Preset Discounts
              Container(
                padding: EdgeInsets.all(isNarrow ? 12 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmark_added_rounded,
                          size: 18,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Quick Presets',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('add_discount_preset_button'),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 15,
                          ),
                          label: const Text(
                            'Add Preset',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _addPreset,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_presets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No presets configured.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _presets.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final p = _presets[idx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.label,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (p.isSystem)
                                        const Text(
                                          'Default statutory preset',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${p.percent.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                                if (!p.isSystem) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    tooltip: 'Remove Preset',
                                    onPressed: () => _removePreset(idx),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Save Actions
              if (isNarrow) ...[
                ElevatedButton(
                  key: const Key('save_discount_rules_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size(64, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveRules,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Discount Policies',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    minimumSize: const Size(64, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          minimumSize: const Size(64, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        key: const Key('save_discount_rules_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          minimumSize: const Size(64, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveRules,
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Discount Policies',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
