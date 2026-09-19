class EconomyConfig {
  final int signupBonus;
  final int referralReward;
  final int generationCost;
  final int adRewardAmount;
  final int dailyBonusFree;
  final int dailyBonusPremium;
  final int freeAdLimitPerDay;
  final int premiumAdLimitPerDay;
  final int watermarkRemovalCost;
  final int shareUnlockReward;

  const EconomyConfig({
    this.signupBonus = 40,
    this.referralReward = 40,
    this.generationCost = 40,
    this.adRewardAmount = 40,
    this.dailyBonusFree = 40,
    this.dailyBonusPremium = 80,
    this.freeAdLimitPerDay = 3,
    this.premiumAdLimitPerDay = 6,
    this.watermarkRemovalCost = 20,
    this.shareUnlockReward = 15,
  });

  factory EconomyConfig.fromMap(Map<String, dynamic>? data) {
    const defaults = EconomyConfig();
    if (data == null) return defaults;
    return EconomyConfig(
      signupBonus: data['signupBonus'] ?? defaults.signupBonus,
      referralReward: data['referralReward'] ?? defaults.referralReward,
      generationCost: data['generationCost'] ?? defaults.generationCost,
      adRewardAmount: data['adRewardAmount'] ?? defaults.adRewardAmount,
      dailyBonusFree: data['dailyBonusFree'] ?? defaults.dailyBonusFree,
      dailyBonusPremium: data['dailyBonusPremium'] ?? defaults.dailyBonusPremium,
      freeAdLimitPerDay: data['freeAdLimitPerDay'] ?? defaults.freeAdLimitPerDay,
      premiumAdLimitPerDay: data['premiumAdLimitPerDay'] ?? defaults.premiumAdLimitPerDay,
      watermarkRemovalCost: data['watermarkRemovalCost'] ?? defaults.watermarkRemovalCost,
      shareUnlockReward: data['shareUnlockReward'] ?? defaults.shareUnlockReward,
    );
  }
}
