import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../../models/history_item.dart';
import '../../../models/user_model.dart';
import '../../../providers/root_index_provider.dart';
import '../../../core/utils/watermark.dart';
import '../../../core/utils/app_snackbar.dart';

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

// A live Firestore stream rather than a one-shot fetch: FirebaseService
// already exposes historyStream() for exactly this. A FutureProvider only
// fetches once and stays cached until something explicitly invalidates it,
// so a freshly-generated image would never show up here without an app
// restart; the stream instead pushes new items in as soon as they're saved.
final historyProvider = StreamProvider.family<List<HistoryItem>, String>((ref, uid) {
  return ref.watch(firebaseServiceProvider).historyStream(uid);
});

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final int index;
  const _HistoryCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final isFailed = item.status == HistoryStatus.failed;
    final height = (index % 3 + 2.5) * 60.0;

    return GestureDetector(
      onTap: isFailed || item.outputUrl == null || item.outputUrl!.isEmpty
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _MasterpiecePreviewScreen(imageUrl: item.outputUrl!),
                ),
              ),
      child: Column(
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
      ),
    );
  }
}

/// Plain full-screen preview for a past generation, opened by tapping a card
/// in "My Masterpieces" — just the image plus Download and Close, no
/// re-generate/share/watermark-unlock options (those belong to the
/// just-generated result screen, not to browsing old history).
class _MasterpiecePreviewScreen extends ConsumerStatefulWidget {
  final String imageUrl;
  const _MasterpiecePreviewScreen({required this.imageUrl});

  @override
  ConsumerState<_MasterpiecePreviewScreen> createState() => _MasterpiecePreviewScreenState();
}

class _MasterpiecePreviewScreenState extends ConsumerState<_MasterpiecePreviewScreen> {
  bool _isDownloading = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(widget.imageUrl)).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw "Download timed out. Please try again.",
          );
      if (response.statusCode != 200) {
        throw "Download failed (${response.statusCode})";
      }

      final isPremium = ref.read(userProvider).value?.tier == UserTier.paid;
      final bytes = isPremium ? response.bodyBytes : await applyWatermark(response.bodyBytes);
      final extension = isPremium ? 'jpg' : 'png';

      // Saves straight to the photo gallery, not a share-sheet hop — sharing
      // only hands the file to whatever app is picked next, which doesn't
      // always end up as an actual saved photo.
      await Gal.putImageBytes(bytes, name: 'ZunoAI_${DateTime.now().millisecondsSinceEpoch}.$extension');
      if (mounted) AppSnackBar.showSuccess(context, "Saved to gallery!");
    } on GalException catch (e) {
      if (mounted) AppSnackBar.showError(context, "Couldn't save to gallery: ${e.type.message}");
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, "Download error: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const CircularProgressIndicator(color: AppColors.electricLime),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.white10),
                        shape: const StadiumBorder(),
                        backgroundColor: Colors.white.withOpacity(0.05),
                      ),
                      icon: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: Colors.white),
                      label: const Text("Close", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading ? null : _download,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricLime,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const FaIcon(FontAwesomeIcons.download, size: 16),
                      label: Text(_isDownloading ? "Downloading..." : "Download"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
