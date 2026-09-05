import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../../models/history_item.dart';
import '../../../providers/root_index_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    final historyAsync = user == null 
        ? const AsyncValue.data(<HistoryItem>[]) 
        : ref.watch(historyProvider(user.uid));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("My Masterpieces", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (user != null) {
            ref.invalidate(historyProvider(user.uid));
          }
        },
        child: historyAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FaIcon(FontAwesomeIcons.images, size: 64, color: Colors.white10),
                        SizedBox(height: 24),
                        Text(
                          "No masterpieces yet",
                          style: TextStyle(fontSize: 18, color: Colors.white38, fontWeight: FontWeight.bold),
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
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricLime,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text("Start Creating", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              );
            }
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _HistoryCard(item: item, index: index);
                    },
                    childCount: items.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricLime)),
          error: (err, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                const SizedBox(height: 8),
                Text("Error: $err"),
                TextButton(
                  onPressed: () => ref.invalidate(historyProvider(user!.uid)), 
                  child: const Text("Retry", style: TextStyle(color: AppColors.electricLime)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final historyProvider = FutureProvider.family<List<HistoryItem>, String>((ref, uid) {
  return ref.watch(firebaseServiceProvider).getUserHistory(uid);
});

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final int index;
  const _HistoryCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final isFailed = item.status == HistoryStatus.failed;
    final height = (index % 3 + 2.5) * 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: Colors.white10),
            ),
            child: isFailed 
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FaIcon(FontAwesomeIcons.circleExclamation, color: AppColors.error.withOpacity(0.5), size: 32),
                    const SizedBox(height: 12),
                    const Text("Failed", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                  ],
                )
              : CachedNetworkImage(
                  imageUrl: item.outputUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.white.withOpacity(0.05)),
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.promptCategory,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat.yMMMd().format(item.timestamp),
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
