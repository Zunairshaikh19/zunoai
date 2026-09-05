import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/image_prompt.dart';
import '../../../providers/saved_prompts_provider.dart';
import '../../../providers/root_index_provider.dart';
import '../../detail/presentation/detail_screen.dart';

class SavedListScreen extends ConsumerWidget {
  const SavedListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedPrompts = ref.watch(savedPromptsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Saved List", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: savedPrompts.isEmpty
          ? ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FaIcon(FontAwesomeIcons.bookmark, size: 64, color: Colors.white10),
                      SizedBox(height: 24),
                      Text(
                        "No saved prompts yet",
                        style: TextStyle(fontSize: 18, color: Colors.white38, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Tap the bookmark icon on any image to save it here",
                        style: TextStyle(fontSize: 13, color: Colors.white24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(rootIndexProvider.notifier).state = 0; // Go to Explore
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.electricLime,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text("Explore Creations", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemBuilder: (context, index) {
                      final prompt = savedPrompts[index];
                      return _SavedImageCard(prompt: prompt, index: index);
                    },
                    childCount: savedPrompts.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
    );
  }
}

class _SavedImageCard extends ConsumerWidget {
  final ImagePrompt prompt;
  final int index;
  const _SavedImageCard({required this.prompt, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  child: GestureDetector(
                    onTap: () {
                      ref.read(savedPromptsProvider.notifier).toggleSave(prompt);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Removed from Saved List", style: TextStyle(fontWeight: FontWeight.bold)),
                          duration: Duration(seconds: 1),
                          backgroundColor: Colors.grey,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.electricLime,
                        shape: BoxShape.circle,
                      ),
                      child: const FaIcon(
                        FontAwesomeIcons.solidBookmark,
                        color: Colors.black,
                        size: 14,
                      ),
                    ),
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
                    prompt.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold),
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
