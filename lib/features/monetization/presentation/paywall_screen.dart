import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Zuno AI Premium"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.electricLime.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.electricLime.withOpacity(0.1),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const FaIcon(FontAwesomeIcons.crown, size: 64, color: AppColors.electricLime),
            ),
            const SizedBox(height: 32),
            const Text(
              "Elite Creative Power",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
            ),
            const SizedBox(height: 12),
            const Text(
              "Elevate your AI generation experience",
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 48),
            _buildFeatureRow(FontAwesomeIcons.solidCircleCheck, "Unleash Full AI Potential"),
            _buildFeatureRow(FontAwesomeIcons.solidCircleCheck, "Priority Processing Speed"),
            _buildFeatureRow(FontAwesomeIcons.solidCircleCheck, "Ad-Free Creative Workspace"),
            _buildFeatureRow(FontAwesomeIcons.solidCircleCheck, "Exclusive Pro Prompt Styles"),
            const SizedBox(height: 64),
            _buildPriceCard(context),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Restore Purchases", style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(dynamic icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 8),
      child: Row(
        children: [
          _buildIcon(icon),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: Colors.white70))),
        ],
      ),
    );
  }

  Widget _buildIcon(dynamic icon) {
    const color = AppColors.electricLime;
    const size = 20.0;
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, color: color, size: size);
    }
    return Icon(icon as IconData, color: color, size: size);
  }

  Widget _buildPriceCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.electricLime),
      ),
      child: Column(
        children: [
          const Text(
            "Monthly Plan",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "\$4.99 / month",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.electricLime),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () {
                // Trigger IAP
              },
              child: const Text("Start Premium", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
