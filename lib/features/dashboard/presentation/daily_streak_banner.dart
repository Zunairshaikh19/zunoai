import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/streak_utils.dart';
import '../../../providers/user_provider.dart';

class DailyStreakBanner extends ConsumerWidget {
  const DailyStreakBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    if (user == null || !canClaimStreak(user.lastStreakClaim)) {
      return const SizedBox.shrink();
    }

    final nextCount = nextStreakCount(user.loginStreak, user.lastStreakClaim);
    final reward = streakReward(nextCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await ref.read(firebaseServiceProvider).claimDailyStreak(
                  user.uid,
                  newStreak: nextCount,
                  coins: reward,
                );
            if (context.mounted) {
              AppSnackBar.showSuccess(context, "Day $nextCount streak! +$reward coins");
            }
          },
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.electricLime.withValues(alpha: 0.18), Colors.transparent],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.electricLime.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: AppColors.electricLime, shape: BoxShape.circle),
                  child: const FaIcon(FontAwesomeIcons.fire, color: Colors.black, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Day $nextCount streak",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                      ),
                      Text(
                        "Tap to claim +$reward free coins",
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.electricLime),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
