import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../../../core/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../main_shell_screen.dart';

class CreateCompanyScreen extends StatefulWidget {
  final AppDatabase db;

  const CreateCompanyScreen({super.key, required this.db});

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _companyName = '';
  String _firstName = '';
  String _lastName = '';
  String _email = '';
  String _password = '';
  String _storeName = '';

  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // 1. Sign up the user in Supabase Auth
      final authResponse = await supabase.auth.signUp(
        email: _email,
        password: _password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Failed to create authentication user.');
      }

      // 2. Pass profileId and email to onboardNewCompany
      final ids = await widget.db.posDao.onboardNewCompany(
        companyName: _companyName,
        storeName: _storeName,
        firstName: _firstName,
        lastName: _lastName,
        email: _email,
        profileId: user.id,
      );

      await DevicePrefs.setCompanyId(ids['companyId']);
      await DevicePrefs.setStoreId(ids['storeId']);
      await DevicePrefs.setRegisterId(ids['registerId']);
      await DevicePrefs.setCurrentEmployeeId(ids['employeeId']);
      await DevicePrefs.setCurrentEmployeeRole('Admin'); // Set role to admin for the creator

      SyncEngine.instance?.restartRealtime();

      if (!mounted) return;

      // Navigate directly into POS
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainShellScreen(database: widget.db)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = 'Failed to create account: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primaryColor),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Welcome! Let\'s set up your business.',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    if (_errorMsg != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _errorMsg!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),

                    // Business Info
                    const Text('Business Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Business Name',
                        prefixIcon: Icon(Icons.business_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      onSaved: (v) => _companyName = v!.trim(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'First Branch/Store Name',
                        prefixIcon: Icon(Icons.storefront_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      onSaved: (v) => _storeName = v!.trim(),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Admin Profile
                    const Text('Owner/Admin Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'First Name',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            onSaved: (v) => _firstName = v!.trim(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Last Name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            onSaved: (v) => _lastName = v!.trim(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Valid email required' : null,
                      onSaved: (v) => _email = v!.trim(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.password_rounded),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                      onSaved: (v) => _password = v!,
                    ),
                    
                    const SizedBox(height: 48),
                    
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isLoading ? null : _submitForm,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Create Business',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
