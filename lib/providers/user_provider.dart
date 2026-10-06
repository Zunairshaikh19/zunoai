import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/streak_utils.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';

final firebaseServiceProvider = Provider((ref) => FirebaseService());
final notificationServiceProvider = Provider((ref) => NotificationService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseServiceProvider).authStateChanges;
});

final userProvider = StateNotifierProvider<UserNotifier, AsyncValue<UserModel?>>((ref) {
  return UserNotifier(ref.watch(firebaseServiceProvider), ref);
});

/// Holds the signed-in user's profile (live from Firestore).
///
/// The profile is read-only for money-like fields: coins, premium, ad
/// counters, streaks and referrals are changed by the backend only. This
/// notifier just asks the backend to do things (create profile, credit the
/// daily bonus, refresh premium) and shows whatever Firestore says.
class UserNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final FirebaseService _firebaseService;
  final Ref _ref;
  StreamSubscription? _userSubscription;

  String? _readyUid; // notifications/last-activity set up for this uid
  String? _premiumCheckedUid; // premium re-verified this session for this uid
  bool _creatingProfile = false;
  bool _claimingDaily = false;
  DateTime? _lastDailyAttempt;

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
        _readyUid = null;
        _premiumCheckedUid = null;
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

    _userSubscription = _firebaseService.userStream(uid).listen((userData) async {
      if (userData != null) {
        state = AsyncValue.data(userData);
        _onProfileReady(userData);
      } else {
        // Signed in, but no server-created profile yet.
        await _createProfile();
      }
    }, onError: (err, st) {
      state = AsyncValue.error(err, st);
    });
  }

  Future<void> _createProfile() async {
    if (_creatingProfile) return;
    _creatingProfile = true;
    try {
      await _firebaseService.ensureProfile();
      // The Firestore stream emits the new profile on its own.
    } catch (e, st) {
      debugPrint("Error creating user profile: $e");
      state = AsyncValue.error(e, st);
    } finally {
      _creatingProfile = false;
    }
  }

  /// Retry button for the "couldn't set up your profile" screen.
  Future<void> retryProfile() async {
    state = const AsyncValue.loading();
    final uid = _ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    _subscribeToUser(uid); // re-listens, and creates the profile if missing
  }

  void _onProfileReady(UserModel user) {
    if (_readyUid != user.uid) {
      _readyUid = user.uid;
      _ref.read(notificationServiceProvider).init(user.uid, _firebaseService);
      _firebaseService.updateLastActivity(user.uid);
    }

    _maybeClaimDaily(user);
    _maybeRefreshPremium(user);
  }

  /// The server credits the daily bonus (once per UTC day). We only nudge it.
  void _maybeClaimDaily(UserModel user) {
    if (_claimingDaily) return;
    if (!isNewUtcDay(user.lastDailyReset)) return;

    final last = _lastDailyAttempt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    _lastDailyAttempt = DateTime.now();

    _claimingDaily = true;
    _firebaseService.claimDaily().catchError((Object e) {
      debugPrint("Daily claim failed: $e");
    }).whenComplete(() => _claimingDaily = false);
  }

  /// Subscriptions renew/cancel on Google's side; re-verify near/after expiry.
  void _maybeRefreshPremium(UserModel user) {
    if (_premiumCheckedUid == user.uid) return;
    final expires = user.premiumExpiresAt;
    if (user.premiumPlan == null || expires == null) return;
    if (expires.isAfter(DateTime.now().add(const Duration(days: 3)))) return;

    _premiumCheckedUid = user.uid;
    _firebaseService.refreshPremium().catchError((Object e) {
      debugPrint("Premium refresh failed: $e");
      _premiumCheckedUid = null; // allow a retry on the next snapshot
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Future<void> setGender(String gender) async {
    final current = state.value;
    if (current != null) {
      await _firebaseService.updateUserGender(current.uid, gender);
      state = AsyncValue.data(current.copyWith(gender: gender));
    }
  }

  /// Claims today's streak on the server; the new balance arrives via the stream.
  Future<({int streak, int reward})> claimStreak() => _firebaseService.claimDailyStreak();

  /// After a rewarded ad: waits (up to [timeout]) for the server's AdMob
  /// verification to credit the coins. Returns true once the balance or the
  /// ad counter changed, false if nothing arrived (e.g. the daily limit was
  /// already reached, or Google's callback is slow).
  Future<bool> waitForAdCredit({
    required int coinsBefore,
    required int adsBefore,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final u = state.value;
      if (u != null && (u.coins > coinsBefore || u.dailyAdsWatched != adsBefore)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
    }
    return false;
  }
}
