import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/ad_service.dart';

/// One real prompt card per this many rendered — after every 8 style cards,
/// a native ad card takes the 9th slot. iOS uses the same interval; only
/// free-tier users see this at all (checked by the caller before inserting).
const int kNativeAdInterval = 8;

bool isNativeAdSlot(int renderedIndex) => (renderedIndex + 1) % (kNativeAdInterval + 1) == 0;

/// Maps a rendered grid position back to the underlying prompt list index,
/// accounting for the ad slots interleaved before it.
int promptIndexForRenderedIndex(int renderedIndex) => renderedIndex - (renderedIndex ~/ (kNativeAdInterval + 1));

/// Total slot count (prompts + interleaved ads) for a feed of [promptCount] items.
int totalSlotsWithAds(int promptCount) {
  if (promptCount == 0) return 0;
  return promptCount + (promptCount ~/ kNativeAdInterval);
}

class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = NativeAd(
      adUnitId: AdService().nativeAdUnitId,
      factoryId: AdService.nativeAdFactoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
    _nativeAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (!_isLoaded || _nativeAd == null) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(height: 320, child: AdWidget(ad: _nativeAd!)),
    );
  }
}
