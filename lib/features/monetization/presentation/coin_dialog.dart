import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/ad_service.dart';
import 'paywall_screen.dart';

class CoinDialog extends ConsumerWidget {
  const CoinDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    final adLimit = user?.tier == UserTier.paid ? 6 : 3;
    final canWatchAd = user != null && user.dailyAdsWatched < adLimit;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const FaIcon(FontAwesomeIcons.coins, color: Colors.amber, size: 40),
              ),
              const SizedBox(height: 24),
              
              // Title
              const Text(
                "Need More Power?",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 12),
              
              // Subtitle
              const Text(
                "You need 40 Zuno coins to visualize this masterpiece.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 32),

              // Action Buttons
              _buildActionButton(
                context: context,
                label: "Earn 40 Coins Free",
                subLabel: canWatchAd 
                    ? "Get 40 coins (${user?.dailyAdsWatched ?? 0}/$adLimit daily)"
                    : "Limit reached ($adLimit/$adLimit)",
                icon: FontAwesomeIcons.solidCirclePlay,
                color: canWatchAd ? AppColors.electricLime : Colors.white24,
                onPressed: !canWatchAd ? () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Daily limit reached. Try Premium!")),
                  );
                } : () {
                  Navigator.pop(context);
                  AdService().showRewarded(
                    onReward: (reward) {
                      ref.read(userProvider.notifier).addCoins(40).then((_) {
                        ref.read(userProvider.notifier).incrementAdCount();
                      });
                    },
                    onFailed: () {},
                  );
                },
              ),
              
              const SizedBox(height: 12),

              _buildActionButton(
                context: context,
                label: "Unlock Premium",
                subLabel: "Get unlimited generations",
                icon: FontAwesomeIcons.crown,
                color: Colors.amber,
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PaywallScreen()),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Cancel Link
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Maybe Later",
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required String subLabel,
    required dynamic icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.05),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: color.withOpacity(0.2)),
          ),
        ),
        child: Row(
          children: [
            _buildIcon(icon, 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    subLabel,
                    style: TextStyle(fontSize: 12, color: color.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(dynamic icon, double size) {
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, size: size);
    }
    return Icon(icon as IconData, size: size);
  }
}
