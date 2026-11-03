import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'privacy_policy_screen.dart' show kSupportEmail;

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _h = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);

  Widget _section(String title, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _h),
          const SizedBox(height: 8),
          for (final p in paragraphs) ...[
            Text(p, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Terms of Use")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Last Updated: November 2026", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              "By using Zuno AI you agree to these terms. If you do not agree, please do not use the app.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            _section("1. Using Zuno AI", [
              "Zuno AI creates AI-generated images from a prompt and the photo(s) you upload.",
              "You must be at least 13 years old (or the minimum age in your country) to use the app.",
              "You are responsible for your account and for everything done with it.",
            ]),
            _section("2. Your photos and permission", [
              "Only upload photos of yourself, or of people who have clearly given you permission to use their likeness.",
              "You keep the rights to the photos you upload. You allow us and our AI providers to process them only to create your images.",
            ]),
            _section("3. What you must not do", [
              "Do not create sexual, nude or explicit images of anyone, and never any content involving minors.",
              "Do not create images meant to harass, threaten, defraud or impersonate a real person, or to spread false information about them.",
              "Do not create hateful, violent or illegal content, or try to break, overload or reverse-engineer the service.",
              "We may block prompts, remove images and suspend or close accounts that break these rules.",
            ]),
            _section("4. Your creations", [
              "You may use the images you generate for personal and commercial purposes, as long as you follow these terms and the law.",
              "AI results can be imperfect or unexpected, and similar images may be created for other users. We do not promise any particular result.",
              "If you see a result that is harmful or breaks the rules, tell us at the address below.",
            ]),
            _section("5. Coins, ads and subscriptions", [
              "Generating images uses coins. Free users can earn coins by watching ads and from daily rewards; premium users get more.",
              "Coins have no cash value and cannot be transferred or exchanged for money.",
              "Subscriptions and coin packs are billed by Google Play and are managed and cancelled there. Refunds follow Google Play's refund rules.",
              "If a generation fails because of a fault on our side, the coins for it are returned to your balance.",
            ]),
            _section("6. Account deletion", [
              "You can delete your account from the Profile screen at any time. This does not cancel a Google Play subscription, so cancel it in Google Play first.",
            ]),
            _section("7. Our responsibility", [
              "The app is provided \"as is\". To the extent the law allows, we are not liable for indirect or unexpected losses from using it, and our total liability is limited to what you paid us in the last 12 months.",
              "We may change the app or these terms. If you keep using Zuno AI after a change, you accept the new terms.",
            ]),
            _section("8. Contact", [
              "Questions, complaints or content reports:",
            ]),
            const Center(
              child: Text(
                kSupportEmail,
                style: TextStyle(color: AppColors.electricLime),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
