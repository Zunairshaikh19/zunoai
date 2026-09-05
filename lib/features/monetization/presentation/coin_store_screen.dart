import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../../services/ad_service.dart';
import '../../../models/user_model.dart';
import 'paywall_screen.dart';

class CoinStoreScreen extends ConsumerWidget {
  const CoinStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Zuno Vault", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text("Please log in"));
          
          final adLimit = user.tier == UserTier.paid ? 6 : 3;
          final canWatchAd = user.dailyAdsWatched < adLimit;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Current Balance Card
                _buildBalanceCard(user.coins),
                const SizedBox(height: 32),
                
                // Earn Section
                _buildSectionTitle("Earn Free Coins"),
                const SizedBox(height: 16),
                _buildAdCard(context, ref, user.dailyAdsWatched, adLimit, canWatchAd),
                
                const SizedBox(height: 40),
                
                // Buy Section
                _buildSectionTitle("Premium Plan"),
                const SizedBox(height: 16),
                _buildSubscriptionCard(context),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text("Error: $err")),
      ),
    );
  }

  Widget _buildBalanceCard(int coins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.electricLime,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Text("Your Balance", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(FontAwesomeIcons.coins, color: Colors.black87, size: 32),
              const SizedBox(width: 16),
              Text(
                "$coins",
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.electricLime),
      ),
    );
  }

  Widget _buildAdCard(BuildContext context, WidgetRef ref, int watched, int limit, bool canWatch) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.electricLime.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const FaIcon(FontAwesomeIcons.circlePlay, size: 24, color: AppColors.electricLime),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Watch & Earn", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  Text("Get 40 coins ($watched/$limit today)", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: !canWatch ? null : () {
                _showAd(context, ref);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricLime,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const StadiumBorder(),
              ),
              child: const Text("Play", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen())),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.electricLime.withOpacity(0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricLime.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          children: [
            FaIcon(FontAwesomeIcons.crown, color: Colors.amber, size: 24),
            SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Zuno AI Premium", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                  SizedBox(height: 4),
                  Text("Unlimited access & Pro features", style: TextStyle(fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight, color: AppColors.electricLime, size: 16),
          ],
        ),
      ),
    );
  }

  void _showAd(BuildContext context, WidgetRef ref) {
    AdService().showRewarded(
      onReward: (reward) {
        // BUG FIX: Ensure we use the latest user context and force refresh
        ref.read(userProvider.notifier).addCoins(40).then((_) {
          ref.read(userProvider.notifier).incrementAdCount();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Coins added successfully!")),
        );
      },
      onFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ad failed to load. Please try again.")),
        );
      },
    );
  }
}
