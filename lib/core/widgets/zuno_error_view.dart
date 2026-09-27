import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shared "something went wrong" state for an AsyncValue's error branch —
/// icon, a friendly title, the underlying error as a muted subtitle, and a
/// pill-shaped Retry button — so every screen's error state looks the same
/// instead of a raw "Error: $err" Text with no visual treatment.
class ZunoErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final String title;

  const ZunoErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title = "Something went wrong",
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              "$error",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricLime,
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text("Retry", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
