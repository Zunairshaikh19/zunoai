import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../models/image_prompt.dart';
import '../../../models/economy_config.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/economy_provider.dart';
import '../../../models/history_item.dart';
import '../../../core/theme/app_colors.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/watermark.dart';
import '../../../services/analytics_service.dart';
import '../../../services/ad_service.dart';
import '../../../models/user_model.dart';
import '../../../providers/root_index_provider.dart';
import '../../../core/widgets/zuno_watermark_badge.dart';
import '../../../core/widgets/insufficient_coins_sheet.dart';

class GenerationState {
  final File? referenceImage;
  final File? referenceImage2;
  // For a 'couple' prompt: true = one photo with both people together,
  // false = two separate solo photos (referenceImage + referenceImage2).
  final bool coupleTogether;
  final bool isGenerating;
  final bool isDownloading;
  final String? resultUrl;
  final String? errorMessage;
  final bool watermarkRemoved;
  final bool hasClaimedShareReward;
  final bool isUnlockingWatermark;

  const GenerationState({
    this.referenceImage,
    this.referenceImage2,
    this.coupleTogether = true,
    this.isGenerating = false,
    this.isDownloading = false,
    this.resultUrl,
    this.errorMessage,
    this.watermarkRemoved = false,
    this.hasClaimedShareReward = false,
    this.isUnlockingWatermark = false,
  });

  GenerationState copyWith({
    File? referenceImage,
    File? referenceImage2,
    bool? coupleTogether,
    bool? isGenerating,
    bool? isDownloading,
    String? resultUrl,
    String? errorMessage,
    bool clearResult = false,
    bool clearImage = false,
    bool clearImage2 = false,
    bool? watermarkRemoved,
    bool? hasClaimedShareReward,
    bool? isUnlockingWatermark,
  }) {
    return GenerationState(
      referenceImage: clearImage ? null : (referenceImage ?? this.referenceImage),
      referenceImage2: clearImage2 ? null : (referenceImage2 ?? this.referenceImage2),
      coupleTogether: coupleTogether ?? this.coupleTogether,
      isGenerating: isGenerating ?? this.isGenerating,
      isDownloading: isDownloading ?? this.isDownloading,
      resultUrl: clearResult ? null : (resultUrl ?? this.resultUrl),
      errorMessage: errorMessage,
      watermarkRemoved: clearResult ? false : (watermarkRemoved ?? this.watermarkRemoved),
      hasClaimedShareReward: clearResult ? false : (hasClaimedShareReward ?? this.hasClaimedShareReward),
      isUnlockingWatermark: isUnlockingWatermark ?? this.isUnlockingWatermark,
    );
  }
}

class GenerationNotifier extends StateNotifier<GenerationState> {
  final Ref _ref;
  GenerationNotifier(this._ref) : super(const GenerationState());

  void setImage(File image) {
    state = state.copyWith(referenceImage: image, errorMessage: null);
  }

  void setImage2(File image) {
    state = state.copyWith(referenceImage2: image, errorMessage: null);
  }

  void setCoupleTogether(bool together) {
    // Switching mode invalidates whichever photo(s) no longer apply.
    state = state.copyWith(
      coupleTogether: together,
      clearImage: true,
      clearImage2: true,
    );
  }

  void resetResult() {
    state = state.copyWith(clearResult: true, errorMessage: null);
  }

  Future<void> generate(ImagePrompt prompt) async {
    final image = state.referenceImage;
    if (image == null) return;
    final isCouple = prompt.gender == 'couple';
    final needsSecondImage = isCouple && !state.coupleTogether;
    if (needsSecondImage && state.referenceImage2 == null) return;

    state = state.copyWith(isGenerating: true, errorMessage: null);

    final user = _ref.read(userProvider).value;
    if (user == null) {
      state = state.copyWith(isGenerating: false, errorMessage: "User session expired");
      return;
    }

    final config = _ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
    if (user.coins < config.generationCost) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: "Insufficient coins. You need at least ${config.generationCost} coins.",
      );
      return;
    }

    try {
      final finalPrompt = prompt.hiddenPrompt.trim().isEmpty 
          ? prompt.category 
          : prompt.hiddenPrompt;

      AnalyticsService().logGenerationStarted(category: prompt.category);

      final result = await _ref.read(firebaseServiceProvider).generateImageSecurely(
        prompt: finalPrompt,
        referenceImage: image,
        referenceImage2: needsSecondImage ? state.referenceImage2 : null,
        templateImageUrl: prompt.imageUrl,
      );

      if (result != null && result.isNotEmpty) {
        final historyItem = HistoryItem(
          id: "", 
          outputUrl: result,
          promptCategory: prompt.category,
          timestamp: DateTime.now(),
          status: HistoryStatus.success,
        );
        await _ref.read(firebaseServiceProvider).saveToHistory(user.uid, historyItem);

        AnalyticsService().logGenerationSuccess(category: prompt.category);

        state = state.copyWith(
          isGenerating: false,
          resultUrl: result,
          watermarkRemoved: user.tier == UserTier.paid,
          hasClaimedShareReward: false,
        );
      } else {
        AnalyticsService().logGenerationFailed(category: prompt.category, error: "Empty or null URL");
        state = state.copyWith(
          isGenerating: false,
          errorMessage: "Generation failed. Please try again.",
        );
      }
    } catch (e) {
      AnalyticsService().logGenerationFailed(category: prompt.category, error: e.toString());
      state = state.copyWith(
        isGenerating: false,
        errorMessage: "Generation error: $e",
      );
    }
  }

  /// Saves the result to the device's photo gallery (not a share-sheet hop —
  /// `Share.shareXFiles` only hands the file to whatever app the user picks
  /// next, which several apps/actions don't turn into an actual saved photo).
  /// Returns the bonus coins earned for this (0 if already claimed for this
  /// generation), so the caller can show it in a snackbar.
  Future<int> downloadAndShareImage() async {
    final url = state.resultUrl;
    if (url == null || url.isEmpty) return 0;

    state = state.copyWith(isDownloading: true);
    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw "Download timed out. Please try again.",
          );
      if (response.statusCode == 200) {
        // A free-tier result stays watermarked in the actual saved file too —
        // only the preview would be trivial to bypass otherwise.
        final bytes = state.watermarkRemoved ? response.bodyBytes : await applyWatermark(response.bodyBytes);
        final extension = state.watermarkRemoved ? 'jpg' : 'png';

        await Gal.putImageBytes(bytes, name: 'ZunoAI_${DateTime.now().millisecondsSinceEpoch}.$extension');
        state = state.copyWith(isDownloading: false);

        if (!state.hasClaimedShareReward) {
          final config = _ref.read(economyConfigProvider).valueOrNull ?? const EconomyConfig();
          await _ref.read(userProvider.notifier).addCoins(config.shareUnlockReward);
          state = state.copyWith(hasClaimedShareReward: true);
          return config.shareUnlockReward;
        }
        return 0;
      } else {
        state = state.copyWith(
          isDownloading: false,
          errorMessage: "Download failed (${response.statusCode})",
        );
        return 0;
      }
    } on GalException catch (e) {
      state = state.copyWith(
        isDownloading: false,
        errorMessage: "Couldn't save to gallery: ${e.type.message}",
      );
      return 0;
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        errorMessage: "Download error: $e",
      );
      return 0;
    }
  }

  Future<bool> unlockWatermark(int cost) async {
    if (state.watermarkRemoved) return true;
    state = state.copyWith(isUnlockingWatermark: true);
    final spent = await _ref.read(userProvider.notifier).spendCoins(cost);
    state = state.copyWith(isUnlockingWatermark: false, watermarkRemoved: spent ? true : state.watermarkRemoved);
    return spent;
  }
}

final generationNotifierProvider =
    StateNotifierProvider.autoDispose<GenerationNotifier, GenerationState>(
  (ref) => GenerationNotifier(ref),
);

class UploadScreen extends ConsumerWidget {
  final ImagePrompt prompt;
  const UploadScreen({super.key, required this.prompt});

  Future<void> _pickImage(BuildContext context, WidgetRef ref, ImageSource source, {bool slot2 = false}) async {
    final picker = ImagePicker();
    // Downscale before upload — an uncompressed camera photo can be 4000px+
    // and several MB, which slows the round trip to the AI backend for no
    // quality benefit (the model doesn't use more detail than this anyway).
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      final notifier = ref.read(generationNotifierProvider.notifier);
      if (slot2) {
        notifier.setImage2(File(pickedFile.path));
      } else {
        notifier.setImage(File(pickedFile.path));
      }
    }
  }

  void _showPicker(BuildContext context, WidgetRef ref, {bool slot2 = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.electricLime),
              title: const Text('Gallery'),
              onTap: () {
                _pickImage(context, ref, ImageSource.gallery, slot2: slot2);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.electricLime),
              title: const Text('Camera'),
              onTap: () {
                _pickImage(context, ref, ImageSource.camera, slot2: slot2);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadBox(BuildContext context, WidgetRef ref, {File? image, required String label, required bool slot2, double height = 300}) {
    return GestureDetector(
      onTap: () => _showPicker(context, ref, slot2: slot2),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: image == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FaIcon(
                    FontAwesomeIcons.cloudArrowUp,
                    size: height > 200 ? 48 : 32,
                    color: AppColors.electricLime.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.file(image, fit: BoxFit.cover),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genState = ref.watch(generationNotifierProvider);

    ref.listen<GenerationState>(generationNotifierProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        AppSnackBar.showError(context, next.errorMessage!);
      }
    });

    final resultUrl = genState.resultUrl;
    if (resultUrl != null && resultUrl.isNotEmpty) {
      return _ResultView(prompt: prompt, resultUrl: resultUrl);
    }

    final image = genState.referenceImage;
    final isCouple = prompt.gender == 'couple';
    final canGenerate = isCouple && !genState.coupleTogether
        ? (image != null && genState.referenceImage2 != null)
        : image != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Create Masterpiece", style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PromptCard(prompt: prompt),
            const SizedBox(height: 32),
            Text(
              isCouple ? "Add Photos" : "Add Reference Image",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (isCouple) ...[
              const SizedBox(height: 4),
              const Text(
                "This style needs two people.",
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("We're together in one photo"),
                      selected: genState.coupleTogether,
                      onSelected: (_) => ref.read(generationNotifierProvider.notifier).setCoupleTogether(true),
                      selectedColor: AppColors.electricLime,
                      labelStyle: TextStyle(
                        color: genState.coupleTogether ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Separate photos"),
                      selected: !genState.coupleTogether,
                      onSelected: (_) => ref.read(generationNotifierProvider.notifier).setCoupleTogether(false),
                      selectedColor: AppColors.electricLime,
                      labelStyle: TextStyle(
                        color: !genState.coupleTogether ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 12),
            if (isCouple && !genState.coupleTogether)
              Row(
                children: [
                  Expanded(child: _uploadBox(context, ref, image: image, label: "Photo 1", slot2: false, height: 220)),
                  const SizedBox(width: 12),
                  Expanded(child: _uploadBox(context, ref, image: genState.referenceImage2, label: "Photo 2", slot2: true, height: 220)),
                ],
              )
            else
              _uploadBox(
                context,
                ref,
                image: image,
                label: isCouple ? "Tap to upload your photo together" : "Tap to upload your photo",
                slot2: false,
              ),
            const SizedBox(height: 40),
            if (genState.isGenerating)
              const _AiProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: canGenerate
                      ? () => ref.read(generationNotifierProvider.notifier).generate(prompt)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricLime,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text("Generate", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiProgressIndicator extends StatefulWidget {
  const _AiProgressIndicator();

  @override
  State<_AiProgressIndicator> createState() => _AiProgressIndicatorState();
}

class _AiProgressIndicatorState extends State<_AiProgressIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentTipIndex = 0;
  Timer? _tipTimer;

  static const List<String> _tips = [
    "Tip: You get 40 free coins every single day!",
    "Tip: Clear reference photos produce higher-quality AI portraits.",
    "Tip: Explore saved prompt blueprints to discover new styles.",
    "Tip: Upgrade to Zuno Premium for priority processing speed.",
  ];

  static const List<Map<String, dynamic>> _phases = [
    {"threshold": 0.25, "label": "Analyzing prompt & reference styles..."},
    {"threshold": 0.60, "label": "Running neural diffusion pipeline..."},
    {"threshold": 0.90, "label": "Enhancing details & lighting..."},
    {"threshold": 1.00, "label": "Finalizing generation..."},
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..forward();

    _tipTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % _tips.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _tipTimer?.cancel();
    super.dispose();
  }

  String _getCurrentPhaseLabel(double progress) {
    for (final phase in _phases) {
      if (progress <= (phase["threshold"] as double)) {
        return phase["label"] as String;
      }
    }
    return "Finalizing generation...";
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final phaseLabel = _getCurrentPhaseLabel(progress);

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.electricLime.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.electricLime.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      phaseLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    "${(progress * 100).toInt()}%",
                    style: const TextStyle(
                      color: AppColors.electricLime,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  color: AppColors.electricLime,
                ),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  _tips[_currentTipIndex],
                  key: ValueKey<int>(_currentTipIndex),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PromptCard extends StatelessWidget {
  final ImagePrompt prompt;
  const _PromptCard({required this.prompt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.electricLime, size: 20),
              const SizedBox(width: 8),
              Text(
                "Prompt: ${prompt.category}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            prompt.hiddenPrompt.isEmpty
                ? "Experience the magic of AI based on this theme."
                : prompt.hiddenPrompt,
            style: const TextStyle(color: Colors.white70, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  final ImagePrompt prompt;
  final String resultUrl;

  const _ResultView({required this.prompt, required this.resultUrl});

  // Free users see an interstitial when they're done looking at a result —
  // the highest-engagement moment in the app, and the standard placement for
  // this category of app. Premium stays completely ad-free.
  void _leaveResult(WidgetRef ref) {
    final isPremium = ref.read(userProvider).value?.tier == UserTier.paid;
    final notifier = ref.read(generationNotifierProvider.notifier);
    if (isPremium) {
      notifier.resetResult();
      return;
    }
    AdService().showInterstitial(() => notifier.resetResult());
  }

  // Header close (X) button: skips back through the prompt/upload screens
  // entirely and drops the user straight on the dashboard, unlike the back
  // arrow which only steps back to re-generate with the same prompt.
  void _closeToDashboard(BuildContext context, WidgetRef ref) {
    final isPremium = ref.read(userProvider).value?.tier == UserTier.paid;
    final notifier = ref.read(generationNotifierProvider.notifier);

    void goHome() {
      notifier.resetResult();
      ref.read(rootIndexProvider.notifier).state = 0;
      Navigator.popUntil(context, (route) => route.isFirst);
    }

    if (isPremium) {
      goHome();
    } else {
      AdService().showInterstitial(goHome);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genState = ref.watch(generationNotifierProvider);
    final config = ref.watch(economyConfigProvider).valueOrNull ?? const EconomyConfig();

    ref.listen<GenerationState>(generationNotifierProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        AppSnackBar.showError(context, next.errorMessage!);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Result Image", style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 20),
          onPressed: () => _leaveResult(ref),
        ),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.xmark, size: 20),
            tooltip: "Close",
            onPressed: () => _closeToDashboard(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: resultUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AppColors.surface),
                      ),
                      if (!genState.watermarkRemoved)
                        const Positioned(
                          right: 14,
                          bottom: 14,
                          child: IgnorePointer(
                            child: ZunoWatermarkBadge(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!genState.watermarkRemoved)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: genState.isUnlockingWatermark
                      ? null
                      : () async {
                          final notifier = ref.read(generationNotifierProvider.notifier);
                          var unlocked = await notifier.unlockWatermark(config.watermarkRemovalCost);

                          if (!unlocked && context.mounted) {
                            // Not enough coins — offer to watch an ad for more,
                            // or go premium. If they earn enough via the ad,
                            // retry the unlock right away.
                            final gotCoins = await InsufficientCoinsSheet.show(
                              context,
                              actionLabel: "Removing the watermark",
                              cost: config.watermarkRemovalCost,
                            );
                            if (gotCoins) {
                              unlocked = await notifier.unlockWatermark(config.watermarkRemovalCost);
                            }
                          }

                          if (context.mounted && unlocked) {
                            AppSnackBar.showSuccess(context, "Watermark removed!");
                          }
                        },
                  icon: genState.isUnlockingWatermark
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const FaIcon(FontAwesomeIcons.eraser, size: 14),
                  label: Text("Remove Watermark (${config.watermarkRemovalCost} coins)"),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prompt.hiddenPrompt.isNotEmpty ? prompt.hiddenPrompt : prompt.category,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _leaveResult(ref),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.white10),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: const Text("Re-generate", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: genState.isDownloading
                            ? null
                            : () async {
                                final bonus = await ref
                                    .read(generationNotifierProvider.notifier)
                                    .downloadAndShareImage();
                                final hasError =
                                    ref.read(generationNotifierProvider).errorMessage != null;
                                if (context.mounted && !hasError) {
                                  AppSnackBar.showSuccess(
                                    context,
                                    bonus > 0 ? "Saved to gallery! +$bonus coins" : "Saved to gallery!",
                                  );
                                }
                              },
                        icon: genState.isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const FaIcon(FontAwesomeIcons.download, size: 16),
                        label: Text(genState.isDownloading ? "Downloading..." : "Download"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.electricLime,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                          elevation: 8,
                          shadowColor: AppColors.electricLime.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
