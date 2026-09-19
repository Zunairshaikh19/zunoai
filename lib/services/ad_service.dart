import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  bool _isInterstitialAdLoading = false;

  // App-open interstitial: at most once per cooldown window, and never twice
  // in the same app run even if something re-triggers the check.
  static const _lastAppOpenAdKey = 'last_app_open_interstitial_at';
  static const _appOpenCooldown = Duration(hours: 1);
  bool _hasShownAppOpenAdThisSession = false;

  final String _googleInterstitialId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/1033173712' 
      : 'ca-app-pub-3940256099942544/4411468910';
      
  final String _googleRewardedId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  // Native ad card slotted into the dashboard feed. `nativeAdFactoryId` must
  // match the id string MainActivity.kt registers (see NativeAdFactoryImpl).
  static const String nativeAdFactoryId = 'dashboardNativeAd';
  final String nativeAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3940256099942544/3986624511';

  final String _unityGameId = Platform.isAndroid ? '1234567' : '1234568';
  final String _unityRewardedPlacement = 'rewardedVideo';

  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      await UnityAds.init(
        gameId: _unityGameId,
        testMode: kDebugMode,
        onComplete: () => debugPrint('Unity Ads Initialized'),
        onFailed: (error, message) => debugPrint('Unity Ads Init Failed: $error $message'),
      );
    } catch (e) {
      debugPrint("AdService Init Error: $e");
    }
    loadInterstitial();
    loadRewarded();
  }

  void loadInterstitial() {
    if (_isInterstitialAdLoading || _interstitialAd != null) return;
    _isInterstitialAdLoading = true;

    InterstitialAd.load(
      adUnitId: _googleInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint("Interstitial Ad Failed to Load: $error");
          _interstitialAd = null;
          _isInterstitialAdLoading = false;
        },
      ),
    );
  }

  /// Shows an interstitial on app open, but only for free-tier users, at
  /// most once per hour, and never twice in one app session. Safe to call
  /// idempotently — repeat calls after the first no-op straight to [onDone].
  Future<void> maybeShowAppOpenInterstitial({
    required bool isPremium,
    required VoidCallback onDone,
  }) async {
    if (isPremium || _hasShownAppOpenAdThisSession) {
      onDone();
      return;
    }
    _hasShownAppOpenAdThisSession = true;

    final prefs = await SharedPreferences.getInstance();
    final lastShownMs = prefs.getInt(_lastAppOpenAdKey);
    if (lastShownMs != null) {
      final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastShownMs));
      if (elapsed < _appOpenCooldown) {
        onDone();
        return;
      }
    }

    await prefs.setInt(_lastAppOpenAdKey, DateTime.now().millisecondsSinceEpoch);
    showInterstitial(onDone);
  }

  void showInterstitial(VoidCallback onDismissed) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          loadInterstitial();
          onDismissed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          loadInterstitial();
          onDismissed();
        },
      );
      _interstitialAd!.show();
    } else {
      onDismissed();
    }
  }

  void loadRewarded() {
    if (_isRewardedAdLoading || _rewardedAd != null) return;
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: _googleRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint("Rewarded Ad Failed to Load: $error");
          _rewardedAd = null;
          _isRewardedAdLoading = false;
        },
      ),
    );
  }

  void showRewarded({
    required Function(RewardItem) onReward,
    required VoidCallback onFailed,
  }) {
    if (_rewardedAd != null) {
      bool rewardEarned = false;

      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _rewardedAd = null;
          loadRewarded();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _rewardedAd = null;
          loadRewarded();
          _showUnityRewarded(onReward, onFailed);
        },
      );

      _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
        if (!rewardEarned) {
          rewardEarned = true;
          onReward(reward);
        }
      });
    } else {
      _showUnityRewarded(onReward, onFailed);
    }
  }

  void _showUnityRewarded(Function(RewardItem) onReward, VoidCallback onFailed) {
    try {
      UnityAds.showVideoAd(
        placementId: _unityRewardedPlacement,
        onComplete: (placementId) => onReward(RewardItem(40, 'coins')),
        onFailed: (placementId, error, message) {
          debugPrint("Unity Ad Failed: $error $message");
          onFailed();
        },
      );
    } catch (e) {
      debugPrint("Unity Ads Error: $e");
      onFailed();
    }
  }
}
