/// Streak / daily helpers. The server decides everything on the **UTC**
/// calendar day, so the app uses UTC too (a phone's clock/timezone can't change
/// what is claimable — these helpers are only for showing the right UI).

/// Default coins per consecutive login day (cycles). The live list comes from
/// `EconomyConfig.streakRewards`; keep this in sync with the server default.
const List<int> kStreakRewards = [2, 2, 3, 3, 4, 5, 10];

bool _isSameUtcDay(DateTime a, DateTime b) {
  final x = a.toUtc();
  final y = b.toUtc();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// True if [lastReset] is not on today's UTC day (a daily bonus is due).
bool isNewUtcDay(DateTime lastReset, {DateTime? now}) =>
    !_isSameUtcDay(lastReset, now ?? DateTime.now());

/// True if the user hasn't already claimed today's streak reward.
bool canClaimStreak(DateTime? lastClaim, {DateTime? now}) {
  if (lastClaim == null) return true;
  return !_isSameUtcDay(lastClaim, now ?? DateTime.now());
}

/// The streak count today's claim would result in — continues if the last
/// claim was yesterday (UTC), otherwise restarts at 1.
int nextStreakCount(int currentStreak, DateTime? lastClaim, {DateTime? now}) {
  if (lastClaim == null) return 1;
  final today = (now ?? DateTime.now()).toUtc();
  final yesterday = today.subtract(const Duration(days: 1));
  if (_isSameUtcDay(lastClaim, yesterday)) return currentStreak + 1;
  return 1;
}

int streakReward(int streakCount, {List<int> rewards = kStreakRewards}) {
  final list = rewards.isEmpty ? kStreakRewards : rewards;
  final index = (streakCount - 1) % list.length;
  return list[index];
}
