import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/user_provider.dart';
import '../../notifications/presentation/support_chat_screen.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/theme/app_colors.dart';

class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 100, color: Colors.redAccent),
            const SizedBox(height: 32),
            const Text(
              "Account Blocked",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              "Your account has been suspended due to a violation of our terms of service. If you believe this is a mistake, please contact our support team.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SupportChatScreen()),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text("Contact Customer Support"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricLime,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(firebaseServiceProvider).signOut();
                } catch (e) {
                  if (context.mounted) {
                    AppSnackBar.showError(context, "Couldn't log out: $e");
                  }
                }
              },
              child: const Text("Logout"),
            ),
          ],
        ),
      ),
    );
  }
}
