import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/device_prefs.dart';
import '../../core/permissions/permission_service.dart';
import '../theme/app_theme.dart';

import '../../data/local/database.dart';
import '../screens/auth/pin_login_screen.dart';
import '../screens/setup/existing_business_login_screen.dart';

class AdminDrawer extends StatelessWidget {
  final AppDatabase db;
  final int currentIndex;
  final ValueChanged<int>? onSelectTab;

  const AdminDrawer({
    super.key,
    required this.db,
    this.currentIndex = 0,
    this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250, // Reduced width for "zoomed out" feel
      child: Drawer(
        backgroundColor: AppTheme.surfaceColor,
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.accentColor.withValues(alpha: 0.2),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'administrator@pos.local',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Main Retail Branch',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Drawer Menu List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                children: [
                  if (PermissionService.instance.canAccessTab(0))
                    _DrawerItem(
                      icon: Icons.inventory_2_rounded,
                      title: 'Inventory',
                      subtitle: 'Stock, categories & catalog',
                      isSelected: currentIndex == 0,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(0);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(1))
                    _DrawerItem(
                      icon: Icons.people_outline_rounded,
                      title: 'Customers',
                      subtitle: 'Loyalty points & credit limits',
                      isSelected: currentIndex == 1,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(1);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(2))
                    _DrawerItem(
                      icon: Icons.point_of_sale_rounded,
                      title: 'Point of Sale',
                      subtitle: 'Cashier checkout terminal',
                      isSelected: currentIndex == 2,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(2);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(3))
                    _DrawerItem(
                      icon: Icons.receipt_long_rounded,
                      title: 'Sales & Invoices',
                      subtitle: 'Transactions & refund history',
                      isSelected: currentIndex == 3,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(3);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(4))
                    _DrawerItem(
                      icon: Icons.bar_chart_rounded,
                      title: 'Reports & Health',
                      subtitle: 'Analytics & stock valuation',
                      isSelected: currentIndex == 4,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(4);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(5))
                    _DrawerItem(
                      icon: Icons.store_mall_directory_rounded,
                      title: 'Stores & Locations',
                      subtitle: 'Manage branches & registers',
                      isSelected: currentIndex == 5,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(5);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(6))
                    _DrawerItem(
                      icon: Icons.badge_outlined,
                      title: 'Staff & Cashiers',
                      subtitle: 'Employee accounts & PINs',
                      isSelected: currentIndex == 6,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(6);
                      },
                    ),
                  if (PermissionService.instance.canAccessTab(7))
                    _DrawerItem(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      subtitle: 'Business profile & device setup',
                      isSelected: currentIndex == 7,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectTab?.call(7);
                      },
                    ),
                  const Divider(height: 16, thickness: 1, color: AppTheme.cardBorderColor),
                  StreamBuilder<int>(
                    stream: db.posDao.watchPendingSyncCount(),
                    builder: (context, snapshot) {
                      final pendingCount = snapshot.data ?? 0;
                      final subtitle = pendingCount > 0 
                          ? '$pendingCount items pending...' 
                          : 'All local changes saved.';
                      return _DrawerItem(
                        icon: Icons.cloud_sync_rounded,
                        title: 'Supabase Cloud Sync',
                        subtitle: subtitle,
                        isSelected: false,
                        trailing: pendingCount > 0 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                        onTap: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cloud sync monitor: $subtitle')),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // Drawer Footer
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.red),
                    title: const Text('Lock Register / Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onTap: () async {
                      await DevicePrefs.setCurrentEmployeeId(null);
                      await DevicePrefs.setCurrentEmployeeRole(null);
                      if (!context.mounted) return;
                      final requirePin = DevicePrefs.requirePinForUnlock;
                      if (!requirePin) {
                        try {
                          if (Supabase.instance.isInitialized) {
                            await Supabase.instance.client.auth.signOut();
                          }
                        } catch (_) {}
                      }
                      if (!context.mounted) return;
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => requirePin
                              ? PinLoginScreen(db: db)
                              : ExistingBusinessLoginScreen(db: db),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                          color: AppTheme.inStockColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Local Database: SQLite Active',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.accentColor.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          icon,
          color: isSelected ? AppTheme.accentColor : Colors.black87,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
            color: isSelected ? AppTheme.accentColor : Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
      ),
    );
  }
}
