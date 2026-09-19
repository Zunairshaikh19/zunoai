/// Coins granted per consecutive login day, cycling every 7 days.
const List<int> kStreakRewards = [5, 10, 15, 20, 25, 30, 50];

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// True if the user hasn't already claimed today's streak reward.
bool canClaimStreak(DateTime? lastClaim) {
  if (lastClaim == null) return true;
  return !_isSameDay(lastClaim, DateTime.now());
}

/// The streak count today's claim would result in — continues if the last
/// claim was yesterday, otherwise restarts at 1 (including a first-ever claim).
int nextStreakCount(int currentStreak, DateTime? lastClaim) {
  if (lastClaim == null) return 1;
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  if (_isSameDay(lastClaim, yesterday)) return currentStreak + 1;
  return 1;
}

int streakReward(int streakCount) {
  final index = (streakCount - 1) % kStreakRewards.length;
  return kStreakRewards[index];
}
