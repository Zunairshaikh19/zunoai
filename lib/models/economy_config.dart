/// Coin amounts and limits. The live values come from Firestore
/// `settings/economy` (so they can change without a store release); the
/// defaults below MUST match `DEFAULT_ECONOMY` in
/// `supabase/functions/_shared/lib.ts` and `economy-defaults.json`.
///
/// These numbers are only for *display* — the server enforces the real ones.
///
/// Sizing (image cost ~$0.0387 = 45 coins, ~$0.00086/coin, Google Play fee 15%):
///  * Premium monthly $9.99 -> 56 coins/day (+ streak) -> ~37 images/month max
///    -> ~82% net margin.
///  * Premium yearly $79.99 -> 38 coins/day (+ streak) -> ~25 images/month max
///    -> ~80.5% net margin.
///  * Free users earn up to ~1 image/day from ads; rewarded-ad revenue must
///    cover that (break-even eCPM ~ $8.6; verify with real AdMob data).
class EconomyConfig {
  final int signupBonus;
  final int referralReward;
  final int referralCap;
  final int generationCost;
  final int adRewardAmount;
  final int dailyBonusFree;

  /// Premium *monthly* plan, coins per day.
  final int dailyBonusPremium;

  /// Premium *yearly* plan, coins per day.
  final int dailyBonusPremiumYearly;
  final int freeAdLimitPerDay;
  final int premiumAdLimitPerDay;
  final int watermarkRemovalCost;
  final List<int> streakRewards;

  const EconomyConfig({
    this.signupBonus = 45,
    this.referralReward = 20,
    this.referralCap = 10,
    this.generationCost = 45,
    this.adRewardAmount = 10,
    this.dailyBonusFree = 0,
    this.dailyBonusPremium = 56,
    this.dailyBonusPremiumYearly = 38,
    this.freeAdLimitPerDay = 5,
    this.premiumAdLimitPerDay = 0,
    this.watermarkRemovalCost = 25,
    this.streakRewards = const [2, 2, 3, 3, 4, 5, 10],
  });

  static int _int(dynamic v, int fallback) =>
      v is num && v.isFinite && v >= 0 ? v.floor() : fallback;

  factory EconomyConfig.fromMap(Map<String, dynamic>? data) {
    const d = EconomyConfig();
    if (data == null) return d;

    final rawRewards = data['streakRewards'];
    final rewards = rawRewards is List
        ? rawRewards.map((e) => _int(e, 0)).where((e) => e > 0).toList()
        : <int>[];

    return EconomyConfig(
      signupBonus: _int(data['signupBonus'], d.signupBonus),
      referralReward: _int(data['referralReward'], d.referralReward),
      referralCap: _int(data['referralCap'], d.referralCap),
      generationCost: _int(data['generationCost'], d.generationCost),
      adRewardAmount: _int(data['adRewardAmount'], d.adRewardAmount),
      dailyBonusFree: _int(data['dailyBonusFree'], d.dailyBonusFree),
      dailyBonusPremium: _int(data['dailyBonusPremium'], d.dailyBonusPremium),
      dailyBonusPremiumYearly: _int(data['dailyBonusPremiumYearly'], d.dailyBonusPremiumYearly),
      freeAdLimitPerDay: _int(data['freeAdLimitPerDay'], d.freeAdLimitPerDay),
      premiumAdLimitPerDay: _int(data['premiumAdLimitPerDay'], d.premiumAdLimitPerDay),
      watermarkRemovalCost: _int(data['watermarkRemovalCost'], d.watermarkRemovalCost),
      streakRewards: rewards.isEmpty ? d.streakRewards : rewards,
    );
  }

  /// Coins a premium user gets per day for the given plan ('monthly'/'yearly').
  int premiumDailyFor(String? plan) => plan == 'yearly' ? dailyBonusPremiumYearly : dailyBonusPremium;
}
