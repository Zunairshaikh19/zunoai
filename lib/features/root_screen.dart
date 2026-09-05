import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard/presentation/dashboard_screen.dart';
import 'generation/presentation/history_screen.dart';
import 'profile/presentation/profile_screen.dart';
import '../core/theme/app_colors.dart';
import '../providers/root_index_provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  final List<Widget> _screens = const [
    DashboardScreen(),
    HistoryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(rootIndexProvider);

    return Scaffold(
      extendBody: true, // Important for floating nav bar
      body: IndexedStack(
        index: selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: selectedIndex,
        onTap: (index) => ref.read(rootIndexProvider.notifier).state = index,
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceTranslucent,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavBarItem(
                    icon: FontAwesomeIcons.compass,
                    label: "Explore",
                    isSelected: selectedIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _NavBarItem(
                    icon: FontAwesomeIcons.solidClock,
                    label: "History",
                    isSelected: selectedIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  _NavBarItem(
                    icon: FontAwesomeIcons.solidUser,
                    label: "Profile",
                    isSelected: selectedIndex == 2,
                    onTap: () => onTap(2),
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

class _NavBarItem extends StatelessWidget {
  final dynamic icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.electricLime : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            _buildIcon(),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final color = isSelected ? Colors.black : Colors.white70;
    const size = 20.0;
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, color: color, size: size);
    }
    return Icon(icon as IconData, color: color, size: size);
  }
}
