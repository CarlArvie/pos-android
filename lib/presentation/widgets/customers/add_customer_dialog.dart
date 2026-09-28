import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../theme/app_theme.dart';

class AddCustomerDialog extends StatefulWidget {
  final AppDatabase db;
  final Customer? customer;

  const AddCustomerDialog({
    super.key,
    required this.db,
    this.customer,
  });

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _pointsController;
  late final TextEditingController _creditLimitController;

  String _loyaltyTier = 'Bronze';
  bool _isSaving = false;

  final List<String> _tiers = ['Bronze', 'Silver', 'Gold', 'Platinum'];

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameController = TextEditingController(text: c?.fullName ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _pointsController = TextEditingController(text: c != null ? c.pointsBalance.toStringAsFixed(0) : '0');
    _creditLimitController = TextEditingController(text: c != null ? c.creditLimit.toStringAsFixed(0) : '5000');
    if (c != null && _tiers.contains(c.loyaltyTier)) {
      _loyaltyTier = c.loyaltyTier;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _pointsController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
      final email = _emailController.text.trim().isEmpty ? null : _emailController.text.trim();
      final address = _addressController.text.trim().isEmpty ? null : _addressController.text.trim();
      final points = double.tryParse(_pointsController.text.trim()) ?? 0.0;
      final creditLimit = double.tryParse(_creditLimitController.text.trim()) ?? 5000.0;

      final companies = await widget.db.select(widget.db.companies).get();
      final companyId = DevicePrefs.companyId ?? (companies.isNotEmpty ? companies.first.id : 'default-company-001');

      Customer result;
      if (widget.customer != null) {
        // Update existing customer
        await widget.db.posDao.updateCustomer(
          id: widget.customer!.id,
          fullName: name,
          phone: phone,
          email: email,
          address: address,
          loyaltyTier: _loyaltyTier,
          pointsBalance: points,
          creditLimit: creditLimit,
        );
        result = await (widget.db.select(widget.db.customers)
              ..where((c) => c.id.equals(widget.customer!.id)))
            .getSingle();
      } else {
        // Insert new customer
        result = await widget.db.posDao.addCustomer(
          companyId: companyId,
          fullName: name,
          phone: phone,
          email: email,
          address: address,
          loyaltyTier: _loyaltyTier,
          pointsBalance: points,
          creditLimit: creditLimit,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save customer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'Platinum':
        return const Color(0xFF6366F1); // Indigo
      case 'Gold':
        return const Color(0xFFEAB308); // Amber Gold
      case 'Silver':
        return const Color(0xFF94A3B8); // Slate Silver
      case 'Bronze':
      default:
        return const Color(0xFFD97706); // Bronze Amber
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
                        color: AppTheme.accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit Customer' : 'Add New Customer',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          Text(
                            isEdit
                                ? 'Update profile and loyalty information'
                                : 'Register customer for sales & loyalty',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24, thickness: 1, color: AppTheme.cardBorderColor),

                // Customer Full Name
                TextFormField(
                  key: const Key('customer_name_input'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Maria Santos',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Customer name is required' : null,
                ),
                const SizedBox(height: 12),

                // Phone & Email Row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('customer_phone_input'),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '0917-000-0000',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const Key('customer_email_input'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'customer@mail.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Address
                TextFormField(
                  key: const Key('customer_address_input'),
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Delivery / Street Address',
                    hintText: 'Unit, Street, Barangay, City',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 12),

                // Loyalty Tier
                DropdownButtonFormField<String>(
                  key: const Key('customer_tier_dropdown'),
                  initialValue: _loyaltyTier,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Loyalty Tier',
                    prefixIcon: Icon(Icons.stars_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                  items: _tiers.map((tier) {
                    return DropdownMenuItem(
                      value: tier,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _getTierColor(tier),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(tier),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _loyaltyTier = val);
                  },
                ),
                const SizedBox(height: 12),

                // Loyalty Points & Credit Limit Row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('customer_points_input'),
                        controller: _pointsController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Loyalty Points',
                          prefixIcon: Icon(Icons.loyalty_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const Key('customer_credit_limit_input'),
                        controller: _creditLimitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Credit Limit (₱)',
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      key: const Key('save_customer_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        isEdit ? 'Update Customer' : 'Save Customer',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSaving ? null : _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
