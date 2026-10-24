import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// TODO(owner): replace with the real support email before release, and use the
// same address in the Play Console listing and the hosted privacy policy.
const String kSupportEmail = 'contact@zunoai.example.com';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
      appBar: AppBar(title: const Text("Privacy Policy")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Last Updated: October 2026", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              "Zuno AI respects your privacy. This page explains what we collect, where it goes and what you can do about it.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            _section("1. What we collect", [
              "Account: your email address, and the display name and profile photo you choose to add.",
              "Photos you upload: the reference photos you pick to create an image (they can show faces).",
              "Your creations: the images you generate and their history, plus your coin balance, subscription status and ad activity needed to run the app.",
              "Device data: a push notification token, and identifiers used by Google AdMob for ads.",
            ]),
            _section("2. How your photos are used", [
              "When you generate an image, your reference photo is sent over the internet to our AI provider (OpenRouter) and the AI model provider behind it, only to create your image.",
              "The finished image is hosted on ImgBB and shown to you through a web link. Anyone who has that link can open the image, so do not share it if you want it private.",
              "Only upload photos of yourself or photos of people who have given you permission.",
            ]),
            _section("3. Services we use", [
              "Firebase (Google): sign-in and our database.",
              "Supabase: the servers that run image generation, coins and purchase checks.",
              "OpenRouter and its AI model providers: image generation.",
              "ImgBB: image hosting.",
              "Google AdMob: rewarded and other ads for free users.",
              "Google Play Billing: subscriptions. We never see your card details.",
              "These services have their own privacy policies and may process data under them.",
            ]),
            _section("4. How long we keep it", [
              "Your account data and generation history stay until you delete them or delete your account.",
              "Images already hosted on ImgBB may remain reachable through their link after deletion. To have a specific image removed, contact us.",
            ]),
            _section("5. Your rights", [
              "You can delete your account and data at any time from the Profile screen in the app, or by contacting us.",
              "Deleting your account does not cancel a Google Play subscription. Cancel it in Google Play first (Menu → Payments & subscriptions → Subscriptions).",
            ]),
            _section("6. Children", [
              "Zuno AI is not meant for children under 13, and we do not knowingly collect their data.",
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
