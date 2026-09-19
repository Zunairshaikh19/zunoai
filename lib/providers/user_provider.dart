import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/economy_config.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import 'economy_provider.dart';

final firebaseServiceProvider = Provider((ref) => FirebaseService());
final notificationServiceProvider = Provider((ref) => NotificationService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseServiceProvider).authStateChanges;
});

final userProvider = StateNotifierProvider<UserNotifier, AsyncValue<UserModel?>>((ref) {
  return UserNotifier(ref.watch(firebaseServiceProvider), ref);
});

class UserNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final FirebaseService _firebaseService;
  final Ref _ref;
  StreamSubscription? _userSubscription;

  UserNotifier(this._firebaseService, this._ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    _ref.listen(authStateProvider, (previous, next) {
      final user = next.value;
      if (user != null) {
        _subscribeToUser(user.uid);
      } else {
        _userSubscription?.cancel();
        state = const AsyncValue.data(null);
      }
    });

    final initialUser = _ref.read(authStateProvider).value;
    if (initialUser != null) {
      _subscribeToUser(initialUser.uid);
    }
  }

  void _subscribeToUser(String uid) {
    _userSubscription?.cancel();
    
    // Initialize Push Notifications
    _ref.read(notificationServiceProvider).init(uid, _firebaseService);

    _userSubscription = _firebaseService.userStream(uid).listen((userData) async {
      if (userData != null) {
        state = AsyncValue.data(userData);
        _checkDailyReset(userData);
        if (userData.referralCode.isEmpty) {
          // Backfill for accounts created before referral codes existed, or
          // any profile write that otherwise landed without one — the
          // Refer & Earn card has nothing to show without this.
          try {
            await _firebaseService.backfillReferralCode(uid);
          } catch (e) {
            debugPrint("Error backfilling referral code: $e");
          }
        }
      } else {
        // Handle case where user is in Auth but no profile exists
        final authUser = _ref.read(authStateProvider).value;
        if (authUser != null) {
          try {
            final config = _ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
            await _firebaseService.createUserProfile(
              authUser,
              signupBonus: config.signupBonus,
              referralReward: config.referralReward,
            );
          } catch (e) {
            debugPrint("Error creating user profile: $e");
          }
        }
      }
    }, onError: (err) {
      state = AsyncValue.error(err, StackTrace.current);
    });

    // Update last activity safely
    _firebaseService.updateLastActivity(uid);
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkDailyReset(UserModel user) async {
    if (user.tier == UserTier.paid &&
        user.premiumExpiresAt != null &&
        user.premiumExpiresAt!.isBefore(DateTime.now())) {
      // Let a lapsed subscription expire client-side; security rules only
      // allow this exact paid -> free transition for the user's own account.
      await _firebaseService.expirePremium(user.uid);
    }

    final now = DateTime.now();
    final lastReset = user.lastDailyReset;

    if (now.day != lastReset.day || now.month != lastReset.month || now.year != lastReset.year) {
      final config = _ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
      final resetCoins = user.tier == UserTier.paid ? config.dailyBonusPremium : config.dailyBonusFree;
      await _firebaseService.resetDailyLimits(user.uid, resetCoins);
      final updatedData = await _firebaseService.getUserData(user.uid);
      state = AsyncValue.data(updatedData);
    }
  }

  Future<void> addCoins(int amount) async {
    final current = state.value;
    if (current != null) {
      final newBalance = current.coins + amount;
      await _firebaseService.updateUserCoins(current.uid, newBalance);
      state = AsyncValue.data(current.copyWith(coins: newBalance));
    }
  }

  Future<bool> spendCoins(int amount) async {
    final current = state.value;
    if (current != null && current.coins >= amount) {
      final newBalance = current.coins - amount;
      await _firebaseService.updateUserCoins(current.uid, newBalance);
      state = AsyncValue.data(current.copyWith(coins: newBalance));
      return true;
    }
    return false;
  }

  Future<void> setGender(String gender) async {
    final current = state.value;
    if (current != null) {
      await _firebaseService.updateUserGender(current.uid, gender);
      state = AsyncValue.data(current.copyWith(gender: gender));
    }
  }

  Future<void> incrementAdCount() async {
    final current = state.value;
    if (current != null) {
      final newCount = current.dailyAdsWatched + 1;
      await _firebaseService.updateDailyAdCount(current.uid, newCount);
      state = AsyncValue.data(current.copyWith(dailyAdsWatched: newCount));
    }
  }
}
