import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/device_prefs.dart';
import '../../../data/local/database.dart';
import '../../screens/setup/existing_business_login_screen.dart';
import '../../theme/app_theme.dart';
import 'manager_override_dialog.dart';

import '../../../core/permissions/permission_service.dart';

/// Reusable security guard widget that protects UIs from unauthenticated
/// and unauthorized access.
class AuthGuard extends StatefulWidget {
  final Widget child;
  final AppDatabase db;
  final List<String>? allowedRoles;
  final String? requiredPermission;
  final List<String>? anyOfPermissions;
  final String? featureName;
  final VoidCallback? onReturnToTerminal;

  const AuthGuard({
    super.key,
    required this.child,
    required this.db,
    this.allowedRoles,
    this.requiredPermission,
    this.anyOfPermissions,
    this.featureName,
    this.onReturnToTerminal,
  });

  /// Helper to verify if the current user has an active authenticated session
  static bool isAuthenticated() {
    final hasEmployee = DevicePrefs.currentEmployeeId != null;
    bool hasSession = true;
    try {
      final client = Supabase.instance.client;
      hasSession = client.auth.currentSession != null &&
          !(client.auth.currentUser?.isAnonymous ?? false);
    } catch (_) {
      // Supabase is not initialized (e.g. In unit/widget tests or offline)
      hasSession = true;
    }
    return hasEmployee && hasSession;
  }

  /// Helper to verify if the current user has one of the allowed roles or required permission
  static bool isAuthorized({
    List<String>? allowedRoles,
    String? requiredPermission,
    List<String>? anyOfPermissions,
  }) {
    final currentRole = DevicePrefs.currentEmployeeRole?.toLowerCase() ?? '';
    // Superadmin bypass
    if (currentRole == 'admin') return true;

    // Granular anyOf permissions check
    if (anyOfPermissions != null && anyOfPermissions.isNotEmpty) {
      final hasAny = anyOfPermissions.any((perm) => PermissionService.instance.hasPermission(perm));
      if (hasAny) return true;
    }

    // Granular required permission check
    if (requiredPermission != null && requiredPermission.isNotEmpty) {
      return PermissionService.instance.hasPermission(requiredPermission);
    }

    // If only anyOfPermissions was specified and none matched, return false
    if (anyOfPermissions != null && anyOfPermissions.isNotEmpty && (allowedRoles == null || allowedRoles.isEmpty)) {
      return false;
    }

    // Role check fallback
    if (allowedRoles == null || allowedRoles.isEmpty) return true;
    return allowedRoles.any((role) => role.toLowerCase() == currentRole);
  }

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool _temporaryManagerOverride = false;

  void _requestManagerOverride() async {
    final feature = widget.featureName ?? 'this section';
    final authorized = await ManagerOverrideDialog.requestOverride(
      context,
      widget.db,
      'Authorize Access to $feature',
    );
    if (authorized && mounted) {
      setState(() {
        _temporaryManagerOverride = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Manager override granted for $feature.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Check Authentication
    if (!AuthGuard.isAuthenticated()) {
      return _buildUnauthenticatedBarrier(context);
    }

    // 2. Check Authorization (unless temporary manager override is active)
    if (!_temporaryManagerOverride &&
        !AuthGuard.isAuthorized(
          allowedRoles: widget.allowedRoles,
          requiredPermission: widget.requiredPermission,
          anyOfPermissions: widget.anyOfPermissions,
        )) {
      return _buildUnauthorizedBarrier(context);
    }

    // 3. Authorized - render the protected content
    return widget.child;
  }

  Widget _buildUnauthenticatedBarrier(BuildContext context) {
    final feature = widget.featureName ?? 'this section';
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_person_rounded,
                    size: 48,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Authentication Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'You must be signed in with an authorized business account to access $feature.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.login_rounded, size: 20),
                    label: const Text(
                      'Go to Login',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => ExistingBusinessLoginScreen(db: widget.db),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnauthorizedBarrier(BuildContext context) {
    final currentRole = (DevicePrefs.currentEmployeeRole ?? 'Cashier').toUpperCase();
    final feature = widget.featureName ?? 'this section';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 48,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Access Denied',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Admin privileges are required to access $feature.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.cardBorderColor),
                  ),
                  child: Text(
                    'Current Role: $currentRole',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                    label: const Text(
                      'Return to POS Counter',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: widget.onReturnToTerminal,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.cardBorderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.verified_user_rounded, size: 18),
                    label: const Text(
                      'Request Manager Override',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    onPressed: _requestManagerOverride,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
