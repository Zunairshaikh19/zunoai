import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/dynamic_icon.dart';

class SocialButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final dynamic icon; // Use dynamic to support both IconData and FaIconData

  const SocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: DynamicIcon(icon, size: 20, color: Colors.white),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppColors.borderSubtle),
          shape: const StadiumBorder(),
          backgroundColor: AppColors.surface.withOpacity(0.5),
        ),
      ),
    );
  }

}
