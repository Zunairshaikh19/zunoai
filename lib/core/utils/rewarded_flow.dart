import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/economy_config.dart';
import '../../providers/economy_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/ad_service.dart';
import '../../services/analytics_service.dart';

enum AdFlowResult {
  /// Coins were credited by the server (AdMob SSV).
  credited,

  /// The ad was watched but the server hasn't credited yet (slow callback or
  /// the daily limit was hit). The balance updates by itself if it arrives.
  pending,
  dismissed,
  unavailable,
  limitReached,
  notSignedIn,
}

/// The single entry point for "watch a rewarded ad for coins".
///
/// The client never grants coins. Google's servers call our `admob-ssv`
/// function, which verifies the signature, dedupes the transaction and credits
/// the coins; this just shows the ad and waits for the balance to change.
Future<AdFlowResult> runRewardedAd(WidgetRef ref) async {
  final user = ref.read(userProvider).value;
  if (user == null) return AdFlowResult.notSignedIn;

  final config = ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
  final limit = user.isPremium ? config.premiumAdLimitPerDay : config.freeAdLimitPerDay;
  if (user.dailyAdsWatched >= limit) return AdFlowResult.limitReached;

  // Capture before the ad: the widget may be gone when it finishes.
  final notifier = ref.read(userProvider.notifier);
  final coinsBefore = user.coins;
  final adsBefore = user.dailyAdsWatched;

  final outcome = await AdService().showRewarded(userId: user.uid);
  switch (outcome) {
    case RewardedOutcome.unavailable:
      return AdFlowResult.unavailable;
    case RewardedOutcome.dismissed:
      return AdFlowResult.dismissed;
    case RewardedOutcome.earned:
      AnalyticsService().logRewardedAdWatched();
      final credited = await notifier.waitForAdCredit(coinsBefore: coinsBefore, adsBefore: adsBefore);
      return credited ? AdFlowResult.credited : AdFlowResult.pending;
  }
}
