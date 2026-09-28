import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/local/database.dart';
import '../../../core/device_prefs.dart';
import '../auth/pin_login_screen.dart';
import '../main_shell_screen.dart';
import 'existing_business_login_screen.dart';

class SetupDeviceScreen extends StatefulWidget {
  final AppDatabase db;

  const SetupDeviceScreen({super.key, required this.db});

  @override
  State<SetupDeviceScreen> createState() => _SetupDeviceScreenState();
}

class _SetupDeviceScreenState extends State<SetupDeviceScreen> {
  bool _isLoading = true;
  
  List<Company> _companies = [];
  List<Store> _stores = [];
  List<CashRegister> _registers = [];

  Company? _selectedCompany;
  Store? _selectedStore;
  CashRegister? _selectedRegister;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Guard: Verify user is authenticated
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final isAnonymous = Supabase.instance.client.auth.currentUser?.isAnonymous ?? false;
      if (session == null || isAnonymous) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ExistingBusinessLoginScreen(db: widget.db)),
          );
        }
        return;
      }
    } catch (_) {
      // Supabase not initialized or offline
    }
    
    // Load companies
    _companies = await widget.db.select(widget.db.companies).get();
    
    if (_companies.isNotEmpty) {
      final prefCompanyId = DevicePrefs.companyId;
      if (prefCompanyId != null && _companies.any((c) => c.id == prefCompanyId)) {
        _selectedCompany = _companies.firstWhere((c) => c.id == prefCompanyId);
      } else {
        _selectedCompany = _companies.first;
      }
      await _loadStoresForCompany(_selectedCompany!.id);
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadStoresForCompany(String companyId) async {
    _stores = await widget.db.posDao.getStores(companyId);
    if (_stores.isNotEmpty) {
      final prefStoreId = DevicePrefs.storeId;
      if (prefStoreId != null && _stores.any((s) => s.id == prefStoreId)) {
        _selectedStore = _stores.firstWhere((s) => s.id == prefStoreId);
      } else {
        _selectedStore = _stores.first;
      }
      await _loadRegistersForStore(_selectedStore!.id);
    } else {
      _selectedStore = null;
      _registers = [];
      _selectedRegister = null;
    }
    setState(() {});
  }

  Future<void> _loadRegistersForStore(String storeId) async {
    _registers = await widget.db.posDao.getRegistersForStore(storeId);
    if (_registers.isNotEmpty) {
      final prefRegisterId = DevicePrefs.registerId;
      if (prefRegisterId != null && _registers.any((r) => r.id == prefRegisterId)) {
        _selectedRegister = _registers.firstWhere((r) => r.id == prefRegisterId);
      } else {
        _selectedRegister = _registers.first;
      }
    } else {
      _selectedRegister = null;
    }
    setState(() {});
  }

  Future<void> _saveAndContinue() async {
    if (_selectedCompany == null || _selectedStore == null || _selectedRegister == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Company, Store, and Register.')),
      );
      return;
    }

    await DevicePrefs.setCompanyId(_selectedCompany!.id);
    await DevicePrefs.setStoreId(_selectedStore!.id);
    await DevicePrefs.setRegisterId(_selectedRegister!.id);
    await widget.db.posDao.cleanOrphanedInventories(_selectedStore!.id);

    if (!mounted) return;

    final hasEmployee = DevicePrefs.currentEmployeeId != null;
    final requirePin = DevicePrefs.requirePinForUnlock;

    Widget nextScreen;
    if (requirePin && !hasEmployee) {
      nextScreen = PinLoginScreen(db: widget.db);
    } else {
      nextScreen = MainShellScreen(database: widget.db);
    }
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Device Setup'),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.important_devices_rounded, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                'Provision This Device',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Select the location and terminal for this device. This step is only required once.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              
              // Company Dropdown
              DropdownButtonFormField<Company>(
                decoration: const InputDecoration(
                  labelText: 'Select Company',
                  border: OutlineInputBorder(),
                ),
                value: _selectedCompany,
                items: _companies.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c.name),
                )).toList(),
                onChanged: (c) {
                  if (c != null) {
                    _selectedCompany = c;
                    _loadStoresForCompany(c.id);
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Store Dropdown
              DropdownButtonFormField<Store>(
                decoration: const InputDecoration(
                  labelText: 'Select Store Location',
                  border: OutlineInputBorder(),
                ),
                value: _selectedStore,
                items: _stores.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.storeName),
                )).toList(),
                onChanged: (s) {
                  if (s != null) {
                    _selectedStore = s;
                    _loadRegistersForStore(s.id);
                  }
                },
                disabledHint: const Text('No stores available'),
              ),
              const SizedBox(height: 16),
              
              // Register Dropdown
              DropdownButtonFormField<CashRegister>(
                decoration: const InputDecoration(
                  labelText: 'Select Cash Register',
                  border: OutlineInputBorder(),
                ),
                value: _selectedRegister,
                items: _registers.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.registerName),
                )).toList(),
                onChanged: (r) {
                  setState(() => _selectedRegister = r);
                },
                disabledHint: const Text('No registers available'),
              ),
              const SizedBox(height: 32),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: _saveAndContinue,
                child: const Text('Save & Continue'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
