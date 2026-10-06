import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../features/monetization/presentation/paywall_screen.dart';
import '../../models/economy_config.dart';
import '../../providers/economy_provider.dart';
import '../../providers/user_provider.dart';
import '../utils/rewarded_flow.dart';
import '../theme/app_colors.dart';
import '../utils/app_snackbar.dart';

/// Shown whenever a user tries to spend coins they don't have (removing a
/// watermark, unlocking something premium, etc). Offers the two ways out:
/// watch a rewarded ad for free coins, or skip the grind and go premium.
class InsufficientCoinsSheet {
  InsufficientCoinsSheet._();

  /// Returns true if the user's balance is now >= [cost] (they watched an ad
  /// and earned enough) so the caller can immediately retry its action.
  static Future<bool> show(
    BuildContext context, {
    required String actionLabel,
    required int cost,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _InsufficientCoinsModal(actionLabel: actionLabel, cost: cost),
    );
    return result ?? false;
  }
}

class _InsufficientCoinsModal extends ConsumerStatefulWidget {
  final String actionLabel;
  final int cost;
  const _InsufficientCoinsModal({required this.actionLabel, required this.cost});

  @override
  ConsumerState<_InsufficientCoinsModal> createState() => _InsufficientCoinsModalState();
}

class _InsufficientCoinsModalState extends ConsumerState<_InsufficientCoinsModal> {
  bool _watchingAd = false;

  Future<void> _watchAd() async {
    if (_watchingAd) return;
    setState(() => _watchingAd = true);

    final config = ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
    final result = await runRewardedAd(ref);
    if (!mounted) return;
    setState(() => _watchingAd = false);

    switch (result) {
      case AdFlowResult.credited:
        final balance = ref.read(userProvider).value?.coins ?? 0;
        if (balance >= widget.cost) {
          Navigator.pop(context, true);
        } else {
          AppSnackBar.showSuccess(context, "+${config.adRewardAmount} coins added!");
        }
      case AdFlowResult.pending:
        AppSnackBar.showInfo(context, "Verifying your reward... coins will appear shortly.");
      case AdFlowResult.dismissed:
        AppSnackBar.showInfo(context, "Watch the full ad to earn coins.");
      case AdFlowResult.unavailable:
        AppSnackBar.showError(context, "Ad not available right now, try again in a bit.");
      case AdFlowResult.limitReached:
        AppSnackBar.showInfo(context, "Daily ad limit reached. Try again tomorrow or go Premium.");
      case AdFlowResult.notSignedIn:
        AppSnackBar.showInfo(context, "Please sign in first.");
    }
  }

  void _goPremium() {
    Navigator.pop(context, false);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider).value;
    final config = ref.watch(economyConfigProvider).valueOrNull ?? const EconomyConfig();
    final balance = user?.coins ?? 0;
    final adLimit = (user?.isPremium ?? false) ? config.premiumAdLimitPerDay : config.freeAdLimitPerDay;
    final canWatchAd = user != null && user.dailyAdsWatched < adLimit;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.electricLime.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const FaIcon(FontAwesomeIcons.coins, size: 28, color: AppColors.electricLime),
          ),
          const SizedBox(height: 20),
          Text(
            "Not enough coins",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            "${widget.actionLabel} costs ${widget.cost} coins — you have $balance. ${canWatchAd ? 'Watch a quick ad for free coins, or go' : 'Come back tomorrow for free coins, or go'} Premium for a bigger daily allowance.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 28),
          if (canWatchAd) SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _watchingAd ? null : _watchAd,
              icon: _watchingAd
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const FaIcon(FontAwesomeIcons.play, size: 16),
              label: const Text("Watch Ad for Free Coins", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricLime,
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _watchingAd ? null : _goPremium,
              icon: const FaIcon(FontAwesomeIcons.crown, size: 16, color: Colors.amber),
              label: const Text("Go Premium", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _watchingAd ? null : () => Navigator.pop(context, false),
            child: const Text("Not Now", style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
