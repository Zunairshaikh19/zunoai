import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logAppOpen() async {
    try {
      await _analytics.logAppOpen();
    } catch (e) {
      debugPrint("Analytics logAppOpen Error: $e");
    }
  }

  Future<void> logGuestBrowsing() async {
    try {
      await _analytics.logEvent(name: 'guest_browsing_started');
    } catch (e) {
      debugPrint("Analytics logGuestBrowsing Error: $e");
    }
  }

  Future<void> logAuthGateTriggered({required String action}) async {
    try {
      await _analytics.logEvent(
        name: 'auth_gate_triggered',
        parameters: {'action': action},
      );
    } catch (e) {
      debugPrint("Analytics logAuthGateTriggered Error: $e");
    }
  }

  Future<void> logSignUp({required String signUpMethod}) async {
    try {
      await _analytics.logSignUp(signUpMethod: signUpMethod);
    } catch (e) {
      debugPrint("Analytics logSignUp Error: $e");
    }
  }

  Future<void> logLogin({required String loginMethod}) async {
    try {
      await _analytics.logLogin(loginMethod: loginMethod);
    } catch (e) {
      debugPrint("Analytics logLogin Error: $e");
    }
  }

  Future<void> logPromptViewed({required String promptId, required String category}) async {
    try {
      await _analytics.logEvent(
        name: 'prompt_viewed',
        parameters: {
          'prompt_id': promptId,
          'category': category,
        },
      );
    } catch (e) {
      debugPrint("Analytics logPromptViewed Error: $e");
    }
  }

  Future<void> logGenerationStarted({required String category}) async {
    try {
      await _analytics.logEvent(
        name: 'generation_started',
        parameters: {
          'category': category,
        },
      );
    } catch (e) {
      debugPrint("Analytics logGenerationStarted Error: $e");
    }
  }

  Future<void> logGenerationSuccess({required String category}) async {
    try {
      await _analytics.logEvent(
        name: 'generation_success',
        parameters: {
          'category': category,
        },
      );
    } catch (e) {
      debugPrint("Analytics logGenerationSuccess Error: $e");
    }
  }

  Future<void> logGenerationFailed({required String category, required String error}) async {
    try {
      await _analytics.logEvent(
        name: 'generation_failed',
        parameters: {
          'category': category,
          'error': error,
        },
      );
    } catch (e) {
      debugPrint("Analytics logGenerationFailed Error: $e");
    }
  }

  Future<void> logRewardedAdWatched() async {
    try {
      await _analytics.logEvent(name: 'rewarded_ad_watched');
    } catch (e) {
      debugPrint("Analytics logRewardedAdWatched Error: $e");
    }
  }

  Future<void> logCoinStoreViewed() async {
    try {
      await _analytics.logEvent(name: 'coin_store_viewed');
    } catch (e) {
      debugPrint("Analytics logCoinStoreViewed Error: $e");
    }
  }

  Future<void> logPurchaseCompleted({required String productId, required double value, required String currency}) async {
    try {
      await _analytics.logPurchase(
        currency: currency,
        value: value,
        items: [
          AnalyticsEventItem(
            itemId: productId,
            itemName: 'Zuno Premium Membership',
          ),
        ],
      );
    } catch (e) {
      debugPrint("Analytics logPurchaseCompleted Error: $e");
    }
  }
}
