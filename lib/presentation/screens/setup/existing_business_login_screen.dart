import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/sync_engine.dart';
import '../../theme/app_theme.dart';
import 'setup_device_screen.dart';
import 'welcome_screen.dart';

class ExistingBusinessLoginScreen extends StatefulWidget {
  final AppDatabase db;

  const ExistingBusinessLoginScreen({super.key, required this.db});

  @override
  State<ExistingBusinessLoginScreen> createState() => _ExistingBusinessLoginScreenState();
}

class _ExistingBusinessLoginScreenState extends State<ExistingBusinessLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // Sign in with Email and Password
      final authResponse = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = authResponse.user;
      if (user == null) throw Exception('Login failed.');

      // Find the employee record linked to this Supabase Auth User
      final employeeRecord = await supabase
          .from('employees')
          .select('company_id, id, position')
          .eq('profile_id', user.id)
          .maybeSingle();

      if (employeeRecord == null) {
        throw Exception('Account not linked to any business.');
      }

      final companyId = employeeRecord['company_id'] as String;
      final employeeId = employeeRecord['id'] as String;
      final employeeRole = (employeeRecord['position'] as String?) ?? 'Cashier';

      // 1. Fetch Company from Supabase
      final companyResponse = await supabase.from('companies').select().eq('id', companyId).maybeSingle();
      if (companyResponse == null) {
        throw Exception('Business data not found.');
      }

      // 2. Fetch everything else
      final storesResp = await supabase.from('stores').select().eq('company_id', companyId);
      final registersResp = await supabase.from('cash_registers').select().eq('company_id', companyId);
      final employeesResp = await supabase.from('employees').select().eq('company_id', companyId);
      
      final productTypesResp = await supabase.from('product_types').select().eq('company_id', companyId);
      final productsResp = await supabase.from('products').select().eq('company_id', companyId);
      final inventoryResp = await supabase.from('inventories').select().eq('company_id', companyId);

      List<Map<String, dynamic>> customersResp = const [];
      List<Map<String, dynamic>> shiftsResp = const [];
      try {
        customersResp = await supabase.from('customers').select().eq('company_id', companyId);
      } catch (_) {}
      try {
        shiftsResp = await supabase.from('cash_managements').select().eq('company_id', companyId);
      } catch (_) {}

      // 3. Hydrate Local SQLite Database
      final currentCompanyId = DevicePrefs.companyId;
      final isSwitchingCompany = currentCompanyId == null ||
          currentCompanyId == 'default-company-001' ||
          currentCompanyId != companyId;

      await widget.db.posDao.hydrateFromCloud(
        company: companyResponse,
        stores: storesResp,
        registers: registersResp,
        employees: employeesResp,
        productTypes: productTypesResp,
        products: productsResp,
        inventories: inventoryResp,
        customers: customersResp,
        cashManagements: shiftsResp,
        clearExisting: isSwitchingCompany,
      );

      // 4. Provision the device with Company and Log the user in
      await DevicePrefs.setCompanyId(companyId);
      await DevicePrefs.setCurrentEmployeeId(employeeId);
      await DevicePrefs.setCurrentEmployeeRole(employeeRole);
      final requirePin = (companyResponse['require_pin'] as bool?) ?? false;
      await DevicePrefs.setRequirePinForUnlock(requirePin);

      // Start realtime websocket immediately
      SyncEngine.instance?.restartRealtime();

      if (!mounted) return;

      // Navigate to SetupDeviceScreen to pick Store & Register
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupDeviceScreen(db: widget.db)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => WelcomeScreen(db: widget.db)),
            );
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_person_rounded, size: 64, color: AppTheme.primaryColor),
                  const SizedBox(height: 24),
                  const Text(
                    'Sign In',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your email and password to log in and sync your store.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  
                  if (_errorMsg != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade700)),
                    ),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                    validator: (value) => (value == null || value.isEmpty || !value.contains('@')) ? 'Please enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_rounded),
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? 'Please enter your password' : null,
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isLoading ? null : _submitForm,
                      child: _isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
