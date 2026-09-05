import 'dart:io';
import 'dart:ui';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  // Real IDs should be used here, these are test IDs
  final String _googleInterstitialId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/1033173712' 
      : 'ca-app-pub-3940256099942544/4411468910';
      
  final String _googleRewardedId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/5224354917' 
      : 'ca-app-pub-3940256099942544/1712485313';

  final String _unityGameId = Platform.isAndroid ? 'UNUSED_FOR_NOW' : 'UNUSED_FOR_NOW';
  final String _unityRewardedPlacement = 'rewardedVideo';

  Future<void> init() async {
    await MobileAds.instance.initialize();
    await UnityAds.init(
      gameId: _unityGameId,
      testMode: true,
      onComplete: () => print('Unity Ads Initialized'),
      onFailed: (error, message) => print('Unity Ads Init Failed: $error $message'),
    );
    loadInterstitial();
    loadRewarded();
  }

  void loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _googleInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  void showInterstitial(VoidCallback onDismissed) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadInterstitial();
          onDismissed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
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
    RewardedAd.load(
      adUnitId: _googleRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) => _rewardedAd = null,
      ),
    );
  }

  void showRewarded({
    required Function(RewardItem) onReward,
    required VoidCallback onFailed,
  }) {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadRewarded();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          loadRewarded();
          _showUnityRewarded(onReward, onFailed);
        },
      );
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) => onReward(reward));
    } else {
      _showUnityRewarded(onReward, onFailed);
    }
  }

  void _showUnityRewarded(Function(RewardItem) onReward, VoidCallback onFailed) {
    UnityAds.showVideoAd(
      placementId: _unityRewardedPlacement,
      onComplete: (placementId) => onReward(RewardItem(40, 'coins')),
      onFailed: (placementId, error, message) => onFailed(),
      onStart: (placementId) => print('Unity Ad Started'),
      onClick: (placementId) => print('Unity Ad Clicked'),
    );
  }
}
