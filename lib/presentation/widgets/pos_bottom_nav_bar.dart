import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/permissions/permission_service.dart';

/// Lightweight, aesthetic, low-device-friendly bottom navigation bar for POS
class PosBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onMorePressed;

  const PosBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          top: BorderSide(
            color: AppTheme.cardBorderColor,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              // 1. Inventory or Customers based on permissions
              if (PermissionService.instance.canAccessTab(0))
                Expanded(
                  child: _NavItem(
                    icon: Icons.inventory_2_outlined,
                    activeIcon: Icons.inventory_2_rounded,
                    label: 'Inventory',
                    isSelected: currentIndex == 0,
                    onTap: () => onTabSelected(0),
                  ),
                )
              else if (PermissionService.instance.canAccessTab(1))
                Expanded(
                  child: _NavItem(
                    icon: Icons.people_outline_rounded,
                    activeIcon: Icons.people_rounded,
                    label: 'Customers',
                    isSelected: currentIndex == 1,
                    onTap: () => onTabSelected(1),
                  ),
                )
              else
                const Expanded(child: SizedBox()),

              // 2. Transactions
              if (PermissionService.instance.canAccessTab(3))
                Expanded(
                  child: _NavItem(
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long_rounded,
                    label: 'Transactions',
                    isSelected: currentIndex == 3,
                    onTap: () => onTabSelected(3),
                  ),
                )
              else
                const Expanded(child: SizedBox()),

              // 3. Middle Counter Button (Point of Sale)
              _CenterCounterButton(
                isSelected: currentIndex == 2,
                onTap: () => onTabSelected(2),
              ),

              // 4. Reports or Customers
              if (PermissionService.instance.canAccessTab(4))
                Expanded(
                  child: _NavItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    isSelected: currentIndex == 4,
                    onTap: () => onTabSelected(4),
                  ),
                )
              else if (PermissionService.instance.canAccessTab(0) &&
                  PermissionService.instance.canAccessTab(1))
                Expanded(
                  child: _NavItem(
                    icon: Icons.people_outline_rounded,
                    activeIcon: Icons.people_rounded,
                    label: 'Customers',
                    isSelected: currentIndex == 1,
                    onTap: () => onTabSelected(1),
                  ),
                )
              else
                const Expanded(child: SizedBox()),

              // 5. More Button (Rightmost)
              Expanded(
                child: _NavItem(
                  icon: Icons.menu_open_rounded,
                  activeIcon: Icons.menu_open_rounded,
                  label: 'More',
                  isSelected: false,
                  onTap: onMorePressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppTheme.accentColor;
    const inactiveColor = Color(0xFF64748B); // Slate 500

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 21,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Center Counter Button (Hero action for the Point of Sale Terminal)
class _CenterCounterButton extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _CenterCounterButton({
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.accentColor : AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: (isSelected ? AppTheme.accentColor : AppTheme.primaryColor)
                            .withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Counter',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppTheme.accentColor : AppTheme.primaryColor,
                    letterSpacing: -0.2,
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
