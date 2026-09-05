import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/theme/app_colors.dart';

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
        icon: _buildIcon(),
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

  Widget _buildIcon() {
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, size: 20, color: Colors.white);
    }
    return Icon(icon as IconData, size: 20, color: Colors.white);
  }
}
