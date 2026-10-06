import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/economy_provider.dart';
import '../../../core/utils/rewarded_flow.dart';
import '../../../models/user_model.dart';
import '../../../models/economy_config.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/zuno_loader.dart';
import '../../../core/widgets/zuno_error_view.dart';
import '../../profile/presentation/profile_screen.dart';
import 'paywall_screen.dart';

class CoinStoreScreen extends ConsumerWidget {
  const CoinStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    final config = ref.watch(economyConfigProvider).valueOrNull ?? const EconomyConfig();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Zuno Vault", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text("Please log in"));

          final adLimit = user.isPremium ? config.premiumAdLimitPerDay : config.freeAdLimitPerDay;
          final canWatchAd = user.dailyAdsWatched < adLimit;
          final dailyBonus = user.isPremium ? config.premiumDailyFor(user.premiumPlan) : config.dailyBonusFree;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBalanceCard(user.coins),
                const SizedBox(height: 16),
                _buildStatsRow(user, adLimit),
                const SizedBox(height: 16),
                _buildAdProgressCard(context, ref, user.dailyAdsWatched, adLimit, canWatchAd, config.adRewardAmount),
                const SizedBox(height: 24),
                const Text("Earn more", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.electricLime)),
                const SizedBox(height: 14),
                _buildEarnGrid(context, dailyBonus, config.referralReward),
                const SizedBox(height: 24),
                _buildSubscriptionCard(context),
              ],
            ),
          );
        },
        loading: () => const ZunoLoadingScreen(),
        error: (err, _) => ZunoErrorView(
          error: err,
          title: "Couldn't load the vault",
          onRetry: () => ref.invalidate(userProvider),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(int coins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Your Balance", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.coins, color: AppColors.electricLime, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    NumberFormat.decimalPattern().format(coins),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text("Zuno Coins", style: TextStyle(color: AppColors.electricLime, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildStatsRow(UserModel user, int adLimit) {
    return Row(
      children: [
        Expanded(child: _statTile("${user.dailyAdsWatched}/$adLimit", "ADS TODAY")),
        const SizedBox(width: 10),
        Expanded(child: _statTile("${user.loginStreak}🔥", "DAY STREAK", valueColor: AppColors.electricLime)),
        const SizedBox(width: 10),
        Expanded(child: _statTile("${user.referralCount}", "FRIENDS REFERRED")),
      ],
    );
  }

  Widget _statTile(String value, String label, {Color valueColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: valueColor)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildAdProgressCard(BuildContext context, WidgetRef ref, int watched, int limit, bool canWatch, int rewardAmount) {
    final fraction = limit == 0 ? 0.0 : (watched / limit).clamp(0.0, 1.0);
    final remaining = (limit - watched).clamp(0, limit);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(AppColors.electricLime),
                  ),
                ),
                Text("$watched/$limit", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Daily ad limit", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  canWatch ? "$remaining more today · get $rewardAmount coins" : (limit == 0 ? "Premium members earn coins daily instead" : "Come back tomorrow for more"),
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: !canWatch ? null : () => _showAd(context, ref, rewardAmount),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.electricLime,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white10,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
            ),
            child: const Text("Play", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnGrid(BuildContext context, int dailyBonus, int referralReward) {
    return Row(
      children: [
        Expanded(
          child: _earnCard(
            icon: FontAwesomeIcons.solidStar,
            title: "Daily Bonus",
            subtitle: "+$dailyBonus coins · auto-credited",
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _earnCard(
            icon: FontAwesomeIcons.userPlus,
            title: "Invite Friend",
            subtitle: "+$referralReward coins each",
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
          ),
        ),
      ],
    );
  }

  Widget _earnCard({required FaIconData icon, required String title, required String subtitle, VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, size: 18, color: AppColors.electricLime),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  Widget _buildSubscriptionCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen())),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: const Row(
          children: [
            FaIcon(FontAwesomeIcons.crown, color: Colors.amber, size: 20),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Zuno AI Premium", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                  SizedBox(height: 3),
                  Text("Bigger daily coins, no ads & Pro styles", style: TextStyle(fontSize: 12, color: Colors.white38)),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight, color: AppColors.electricLime, size: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _showAd(BuildContext context, WidgetRef ref, int rewardAmount) async {
    final result = await runRewardedAd(ref);
    if (!context.mounted) return;
    switch (result) {
      case AdFlowResult.credited:
        AppSnackBar.showSuccess(context, "+$rewardAmount coins added!");
      case AdFlowResult.pending:
        AppSnackBar.showInfo(context, "Verifying your reward... coins will appear shortly.");
      case AdFlowResult.dismissed:
        AppSnackBar.showInfo(context, "Watch the full ad to earn coins.");
      case AdFlowResult.unavailable:
        AppSnackBar.showError(context, "No ad available right now. Please try again in a bit.");
      case AdFlowResult.limitReached:
        AppSnackBar.showInfo(context, "Daily ad limit reached. Come back tomorrow!");
      case AdFlowResult.notSignedIn:
        AppSnackBar.showInfo(context, "Please sign in first.");
    }
  }
}
