import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../theme/app_colors.dart';

/// Shown instead of a blank screen when a signed-out visitor opens a page that
/// needs an account (Profile, Coin Vault). Gives them a clear way forward.
class GuestSignInPrompt extends StatelessWidget {
  final String title;
  final String message;

  const GuestSignInPrompt({
    super.key,
    this.title = 'Sign in to continue',
    this.message = 'Create an account or sign in to see this page.',
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
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.electricLime.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const FaIcon(FontAwesomeIcons.lock, size: 28, color: AppColors.electricLime),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white60),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricLime,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                ),
                child: const Text('Sign In / Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
