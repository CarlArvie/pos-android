import 'package:flutter/material.dart';
import '../../../data/local/database.dart';
import '../../../data/local/seed_data.dart';
import '../../theme/app_theme.dart';
import 'setup_device_screen.dart';
import 'create_company_screen.dart';
import 'existing_business_login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final AppDatabase db;

  const WelcomeScreen({super.key, required this.db});

  void _loadDemoData(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Run the seeder
    await DatabaseSeeder.seedIfEmpty(db);

    if (context.mounted) {
      // Close the dialog
      Navigator.of(context).pop();

      // Navigate to SetupDeviceScreen so they can provision
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupDeviceScreen(db: db)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.point_of_sale_rounded,
                    size: 80,
                    color: AppTheme.accentColor,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome to POS System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set up your store or connect to an existing account to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Standalone / New Company Option
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.storefront_rounded),
                    label: const Text(
                      'Create a new Company',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => CreateCompanyScreen(db: db)),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Cloud Sync Option
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_sync_rounded),
                    label: const Text(
                      'I already have an account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => ExistingBusinessLoginScreen(db: db)),
                      );
                    },
                  ),
                  const SizedBox(height: 48),

                  // Hidden / Developer option
                  TextButton(
                    onPressed: () => _loadDemoData(context),
                    child: const Text(
                      'Load Demo Data (Testing only)',
                      style: TextStyle(color: Colors.grey),
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
