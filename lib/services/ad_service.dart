import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What happened when a rewarded ad was shown.
enum RewardedOutcome {
  /// The user watched the ad to the end. Coins are credited by the *server*
  /// once Google's server-side verification (SSV) callback arrives.
  earned,

  /// The user closed the ad early — no reward.
  dismissed,

  /// No ad was available (not loaded / failed to show / consent missing).
  unavailable,
}

/// AdMob wrapper. Production ad unit ids are passed at build time:
///
///   flutter build appbundle --release \
///     --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-XXXX/1111111111 \
///     --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/2222222222 \
///     --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-XXXX/3333333333
///
/// (and `-PADMOB_APP_ID=ca-app-pub-XXXX~YYYY` for Gradle, see
/// PRODUCTION_CHECKLIST.md). Without them Google's *test* ids are used.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // Google's official demo ids — used only when no real id is supplied.
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  static const _rewardedAndroid =
      String.fromEnvironment('ADMOB_REWARDED_ANDROID', defaultValue: _testRewardedAndroid);
  static const _rewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS', defaultValue: _testRewardedIos);
  static const _interstitialAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID', defaultValue: _testInterstitialAndroid);
  static const _interstitialIos =
      String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: _testInterstitialIos);
  static const _nativeAndroid = String.fromEnvironment('ADMOB_NATIVE_ANDROID', defaultValue: _testNativeAndroid);
  static const _nativeIos = String.fromEnvironment('ADMOB_NATIVE_IOS', defaultValue: _testNativeIos);

  String get _rewardedId => Platform.isAndroid ? _rewardedAndroid : _rewardedIos;
  String get _interstitialId => Platform.isAndroid ? _interstitialAndroid : _interstitialIos;
  String get nativeAdUnitId => Platform.isAndroid ? _nativeAndroid : _nativeIos;

  /// True while any ad unit is still Google's demo id (=> earns nothing).
  bool get usingTestIds =>
      _rewardedId == _testRewardedAndroid ||
      _rewardedId == _testRewardedIos ||
      _interstitialId == _testInterstitialAndroid ||
      _interstitialId == _testInterstitialIos;

  // Native ad card slotted into the dashboard feed. `nativeAdFactoryId` must
  // match the id string MainActivity.kt registers (see NativeAdFactoryImpl).
  static const String nativeAdFactoryId = 'dashboardNativeAd';

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  bool _isInterstitialAdLoading = false;
  bool _initialized = false;
  bool _canRequestAds = false;

  /// True once consent allows requesting ads (GDPR/UK/EEA via Google UMP).
  bool get canRequestAds => _canRequestAds;

  // App-open interstitial: at most once per cooldown window, and never twice
  // in the same app run even if something re-triggers the check.
  static const _lastAppOpenAdKey = 'last_app_open_interstitial_at';
  static const _appOpenCooldown = Duration(hours: 1);
  bool _hasShownAppOpenAdThisSession = false;

  /// Call once after the first frame (the consent form needs a visible screen).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kReleaseMode && usingTestIds) {
      debugPrint(
        'WARNING: AdMob is using Google TEST ad unit ids in a RELEASE build — '
        'no real revenue. Pass the ADMOB_* --dart-define values (see PRODUCTION_CHECKLIST.md).',
      );
    }

    try {
      await _gatherConsent();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (!_canRequestAds) return;
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint("AdService Init Error: $e");
      return;
    }
    loadInterstitial();
    loadRewarded();
  }

  /// Google UMP consent flow (required for UK/EEA users). No-op where not required.
  Future<void> _gatherConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
            if (error != null) debugPrint('Consent form error: ${error.message}');
            if (!done.isCompleted) done.complete();
          });
        } catch (e) {
          debugPrint('Consent form failed: $e');
          if (!done.isCompleted) done.complete();
        }
      },
      (FormError error) {
        debugPrint('Consent info update failed: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  void loadInterstitial() {
    if (!_canRequestAds || _isInterstitialAdLoading || _interstitialAd != null) return;
    _isInterstitialAdLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialId,
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
    final ad = _interstitialAd;
    if (ad == null) {
      loadInterstitial();
      onDismissed();
      return;
    }
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
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
    ad.show();
  }

  void loadRewarded() {
    if (!_canRequestAds || _isRewardedAdLoading || _rewardedAd != null) return;
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: _rewardedId,
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

  /// Waits (briefly) for a rewarded ad to be ready, loading one if needed.
  Future<bool> _ensureRewardedReady() async {
    if (_rewardedAd != null) return true;
    loadRewarded();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_rewardedAd != null) return true;
      if (!_isRewardedAdLoading) loadRewarded();
    }
    return _rewardedAd != null;
  }

  /// Shows a rewarded ad tagged with the user's id for server-side
  /// verification. The reward itself is credited by the backend (admob-ssv),
  /// never by this method — the app only learns whether the ad was completed.
  Future<RewardedOutcome> showRewarded({required String userId}) async {
    if (!await _ensureRewardedReady()) return RewardedOutcome.unavailable;
    final ad = _rewardedAd!;
    _rewardedAd = null;

    final completer = Completer<RewardedOutcome>();
    var earned = false;

    await ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId));
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewarded();
        if (!completer.isCompleted) {
          completer.complete(earned ? RewardedOutcome.earned : RewardedOutcome.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint("Rewarded ad failed to show: $error");
        ad.dispose();
        loadRewarded();
        if (!completer.isCompleted) completer.complete(RewardedOutcome.unavailable);
      },
    );
    ad.show(onUserEarnedReward: (ad, reward) {
      earned = true;
    });
    return completer.future;
  }
}
