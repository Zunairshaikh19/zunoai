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

import '../../../services/local_cache_service.dart';

final localCacheServiceProvider = Provider((ref) => LocalCacheService());

class PromptsNotifier extends AsyncNotifier<List<ImagePrompt>> {
  @override
  FutureOr<List<ImagePrompt>> build() async {
    // 1. Load from cache first
    final cached = await ref.read(localCacheServiceProvider).getCachedPrompts();
    if (cached.isNotEmpty) {
      // Return cached data immediately, then trigger background update
      _fetchFromNetwork();
      return cached;
    }
    
    // 2. If no cache, wait for network
    return _fetchFromNetwork();
  }

  Future<List<ImagePrompt>> _fetchFromNetwork() async {
    try {
      final prompts = await ref.read(firebaseServiceProvider).getImagePrompts();
      // 3. Save to cache
      await ref.read(localCacheServiceProvider).savePrompts(prompts);
      state = AsyncValue.data(prompts);
      return prompts;
    } catch (e, stack) {
      if (state.hasValue) return state.value!;
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _fetchFromNetwork();
  }
}

final promptsProvider = AsyncNotifierProvider<PromptsNotifier, List<ImagePrompt>>(PromptsNotifier.new);


class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String selectedCategory = "All";

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProvider);
    final promptsAsync = ref.watch(promptsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(userAsync),
            Expanded(
              child: promptsAsync.when(
                data: (prompts) {
                  final filtered = selectedCategory == "All" 
                      ? prompts 
                      : prompts.where((p) => p.category == selectedCategory).toList();
                  
                  return RefreshIndicator(
                    onRefresh: () => ref.read(promptsProvider.notifier).refresh(),
                    color: AppColors.electricLime,
                    backgroundColor: Colors.black,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildCategoryFilter(prompts)),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          sliver: SliverMasonryGrid.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            itemBuilder: (context, index) => _ImageCard(
                              prompt: filtered[index],
                              index: index,
                            ),
                            childCount: filtered.length,
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)), // Space for floating bar
                      ],
                    ),
                  );
                },
                loading: () => _buildShimmerGrid(),
                error: (err, _) => _buildErrorMessage(err),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue<dynamic> userAsync) {
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
                  color: Colors.white.withOpacity(0.05),
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
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.electricLime,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricLime.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const FaIcon(FontAwesomeIcons.plus, color: Colors.black, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(List<ImagePrompt> prompts) {
    final categories = ["All", ...prompts.map((p) => p.category).toSet().toList()];
    
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
              onSelected: (val) => setState(() => selectedCategory = cat),
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

  Widget _buildShimmerGrid() {
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

  Widget _buildErrorMessage(Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text("Could not fetch creations", style: TextStyle(color: Colors.white54)),
          TextButton(onPressed: () => ref.refresh(promptsProvider), child: const Text("Retry")),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final ImagePrompt prompt;
  final int index;
  const _ImageCard({required this.prompt, required this.index});

  @override
  Widget build(BuildContext context) {
    // Variable heights for masonry effect
    final height = (index % 3 + 2.5) * 60.0;

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
                  placeholder: (context, url) => Container(color: Colors.white.withOpacity(0.05)),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const FaIcon(FontAwesomeIcons.bookmark, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.electricLime,
                  child: FaIcon(FontAwesomeIcons.solidUser, size: 10, color: Colors.black),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Zuno Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
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
