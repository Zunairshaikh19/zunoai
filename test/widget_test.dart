import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunoai/core/utils/streak_utils.dart';
import 'package:zunoai/models/economy_config.dart';
import 'package:zunoai/models/user_model.dart';

void main() {
  group('streak_utils (UTC)', () {
    final now = DateTime.utc(2026, 10, 6, 12);

    test('can claim when never claimed or claimed on an earlier day', () {
      expect(canClaimStreak(null, now: now), isTrue);
      expect(canClaimStreak(DateTime.utc(2026, 10, 5, 23, 59), now: now), isTrue);
      expect(canClaimStreak(DateTime.utc(2026, 10, 6, 0, 1), now: now), isFalse);
    });

    test('streak continues only from yesterday', () {
      expect(nextStreakCount(3, DateTime.utc(2026, 10, 5, 8), now: now), 4);
      expect(nextStreakCount(3, DateTime.utc(2026, 10, 3, 8), now: now), 1);
      expect(nextStreakCount(0, null, now: now), 1);
    });

    test('reward cycles through the configured list', () {
      expect(streakReward(1), 2);
      expect(streakReward(7), 10);
      expect(streakReward(8), 2);
      expect(streakReward(2, rewards: const [1, 9]), 9);
      expect(streakReward(1, rewards: const []), 2);
    });
  });

  group('EconomyConfig', () {
    test('defaults match the 80% margin sizing', () {
      const c = EconomyConfig();
      expect(c.generationCost, 40);
      expect(c.dailyBonusPremium, 52);
      expect(c.dailyBonusPremiumYearly, 33);
      expect(c.premiumAdLimitPerDay, 0);
    });

    test('monthly premium stays above 80% net margin at max usage', () {
      const c = EconomyConfig();
      const coinCost = 0.04 / 40; // $0.04 per image
      double margin(double price, int daily, int days) {
        final net = price * 0.85; // after Google Play fee
        final cost = daily * days * coinCost;
        return (net - cost) / net;
      }

      expect(margin(9.99, c.dailyBonusPremium, 30), greaterThanOrEqualTo(0.80));
      expect(margin(79.99, c.dailyBonusPremiumYearly, 365), greaterThanOrEqualTo(0.80));
    });

    test('parses ints, doubles and keeps 0 as a valid value', () {
      final c = EconomyConfig.fromMap({'generationCost': 0, 'adRewardAmount': 12.0, 'freeAdLimitPerDay': -3});
      expect(c.generationCost, 0);
      expect(c.adRewardAmount, 12);
      expect(c.freeAdLimitPerDay, 3); // negative -> default
    });

    test('premiumDailyFor picks the plan', () {
      const c = EconomyConfig();
      expect(c.premiumDailyFor('yearly'), c.dailyBonusPremiumYearly);
      expect(c.premiumDailyFor('monthly'), c.dailyBonusPremium);
      expect(c.premiumDailyFor(null), c.dailyBonusPremium);
    });
  });

  group('UserModel', () {
    test('expired premium is treated as free', () {
      final expired = UserModel.fromMap({
        'tier': 'paid',
        'premiumExpiresAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        'coins': 10.0,
      }, 'u1');
      expect(expired.isPremium, isFalse);
      expect(expired.coins, 10);

      final active = UserModel.fromMap({
        'tier': 'paid',
        'premiumExpiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 5))),
      }, 'u2');
      expect(active.isPremium, isTrue);
    });

    test('paid without an expiry is not premium', () {
      expect(UserModel.fromMap({'tier': 'paid'}, 'u3').isPremium, isFalse);
    });
  });
}
