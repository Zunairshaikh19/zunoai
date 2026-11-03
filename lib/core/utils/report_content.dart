import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/support_message.dart';
import '../../providers/user_provider.dart';
import '../theme/app_colors.dart';
import 'app_snackbar.dart';

const _reasons = <String>[
  'Sexual or explicit content',
  'Involves a minor',
  'Violent or hateful content',
  'Looks like someone else / impersonation',
  'Wrong or broken result',
  'Other',
];

/// Lets the user report a generated image. The report is sent into the user's
/// own support ticket (the admin panel's Support inbox), tagged "[REPORT]".
Future<void> showReportImageSheet(BuildContext context, WidgetRef ref, String imageUrl) async {
  final uid = ref.read(userProvider).value?.uid;
  if (uid == null) return;

  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text("Report this image", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text("What is wrong with it?", style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          for (final r in _reasons)
            ListTile(
              title: Text(r),
              onTap: () => Navigator.pop(sheetContext, r),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;

  try {
    await ref.read(firebaseServiceProvider).sendSupportMessage(
          uid,
          SupportMessage(
            id: '',
            senderId: uid,
            text: '[REPORT] $reason\nImage: $imageUrl',
            attachmentUrl: imageUrl,
            timestamp: DateTime.now(),
          ),
        );
    if (context.mounted) {
      AppSnackBar.showSuccess(context, "Thanks, we'll review this image.");
    }
  } catch (_) {
    if (context.mounted) {
      AppSnackBar.showError(context, "Couldn't send the report. Please try again.");
    }
  }
}
