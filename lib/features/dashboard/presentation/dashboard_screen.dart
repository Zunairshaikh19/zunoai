import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../providers/user_provider.dart';
import '../../../models/image_prompt.dart';
import '../../../core/theme/app_colors.dart';
import '../../detail/presentation/detail_screen.dart';
import '../../monetization/presentation/coin_store_screen.dart';
import '../../generation/presentation/history_screen.dart';
import '../../../providers/saved_prompts_provider.dart';
import '../../../services/local_cache_service.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../models/user_model.dart';
import 'daily_streak_banner.dart';
import 'native_ad_card.dart';
import 'gender_picker_sheet.dart';

final localCacheServiceProvider = Provider((ref) => LocalCacheService());
final selectedCategoryProvider = StateProvider<String>((ref) => "All");

class PromptsNotifier extends AsyncNotifier<List<ImagePrompt>> {
  @override
  FutureOr<List<ImagePrompt>> build() async {
    final cached = await ref.read(localCacheServiceProvider).getCachedPrompts();
    if (cached.isNotEmpty) {
      _fetchFromNetwork();
      return cached;
    }
    return _fetchFromNetwork();
  }

  Future<List<ImagePrompt>> _fetchFromNetwork() async {
    try {
      final prompts = await ref.read(firebaseServiceProvider).getImagePrompts();
      await ref.read(localCacheServiceProvider).savePrompts(prompts);
      state = AsyncValue.data(prompts);
      return prompts;
    } catch (e, stack) {
      if (state.hasValue) return state.value!;
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _fetchFromNetwork();
  }
}

final promptsProvider = AsyncNotifierProvider<PromptsNotifier, List<ImagePrompt>>(PromptsNotifier.new);

final filteredPromptsProvider = Provider<AsyncValue<List<ImagePrompt>>>((ref) {
  final promptsAsync = ref.watch(promptsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final userGender = ref.watch(userProvider).value?.gender;

  return promptsAsync.whenData((prompts) {
    var result = prompts.where((p) {
      // No gender chosen yet (or 'unisex') sees everything; otherwise hide
      // prompts tagged for the other gender. 'couple' always shows.
      if (userGender == null || userGender == 'unisex') return true;
      return p.gender == userGender || p.gender == 'unisex' || p.gender == 'couple';
    }).toList();

    if (category != "All") {
      result = result.where((p) => p.category == category).toList();
    }
    return result;
  });
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredPromptsAsync = ref.watch(filteredPromptsProvider);
    final allPrompts = ref.watch(promptsProvider).value ?? [];
    final isPremium = ref.watch(userProvider).value?.tier == UserTier.paid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) GenderPickerSheet.showIfNeeded(context, ref);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const _DashboardHeader(),
            const DailyStreakBanner(),
            Expanded(
              child: filteredPromptsAsync.when(
                data: (filtered) => RefreshIndicator(
                  onRefresh: () => ref.read(promptsProvider.notifier).refresh(),
                  color: AppColors.electricLime,
                  backgroundColor: Colors.black,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _CategoryFilterList(allPrompts: allPrompts),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        sliver: SliverMasonryGrid.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          itemBuilder: (context, index) {
                            if (!isPremium && isNativeAdSlot(index)) {
                              return const RepaintBoundary(child: NativeAdCard());
                            }
                            final promptIndex = isPremium ? index : promptIndexForRenderedIndex(index);
                            return RepaintBoundary(
                              child: _ImageCard(
                                prompt: filtered[promptIndex],
                                index: promptIndex,
                              ),
                            );
                          },
                          childCount: isPremium ? filtered.length : totalSlotsWithAds(filtered.length),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
                loading: () => const _ShimmerGrid(),
                error: (err, _) => _ErrorMessage(error: err),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.electricLime,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const FaIcon(FontAwesomeIcons.bolt, color: Colors.black, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            "Zuno AI",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          userAsync.when(
            data: (user) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CoinStoreScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.coins, color: Colors.amber, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      "${user?.coins ?? 0}",
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox(),
            error: (err, stack) => const SizedBox(),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: const FaIcon(FontAwesomeIcons.clockRotateLeft, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterList extends ConsumerWidget {
  final List<ImagePrompt> allPrompts;
  const _CategoryFilterList({required this.allPrompts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ["All", ...allPrompts.map((p) => p.category).toSet()];
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) => ref.read(selectedCategoryProvider.notifier).state = cat,
              backgroundColor: Colors.transparent,
              selectedColor: Colors.white10,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.electricLime : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isSelected ? AppColors.electricLime : Colors.white10),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImageCard extends ConsumerWidget {
  final ImagePrompt prompt;
  final int index;
  const _ImageCard({required this.prompt, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = (index % 3 + 2.5) * 60.0;
    final savedPrompts = ref.watch(savedPromptsProvider);
    final isSaved = savedPrompts.any((p) => p.id == prompt.id);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DetailScreen(prompt: prompt)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: prompt.imageUrl,
                  height: height,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.white.withValues(alpha: 0.05)),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () {
                      ref.read(savedPromptsProvider.notifier).toggleSave(prompt);
                      if (isSaved) {
                        AppSnackBar.showInfo(context, "Removed from Saved List");
                      } else {
                        AppSnackBar.showSuccess(context, "Added to Saved List");
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSaved ? AppColors.electricLime : Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: FaIcon(
                        isSaved ? FontAwesomeIcons.solidBookmark : FontAwesomeIcons.bookmark,
                        color: isSaved ? Colors.black : Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.electricLime,
                  child: FaIcon(FontAwesomeIcons.solidUser, size: 10, color: Colors.black),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Zuno Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[900]!,
        highlightColor: Colors.grey[800]!,
        child: Container(
          height: (index % 3 + 2) * 80.0,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      itemCount: 6,
    );
  }
}

class _ErrorMessage extends ConsumerWidget {
  final Object error;
  const _ErrorMessage({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text("Could not fetch creations", style: TextStyle(color: Colors.white54)),
          TextButton(
            onPressed: () => ref.refresh(promptsProvider),
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}
