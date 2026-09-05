import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Privacy Policy")),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Last Updated: August 2026",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              "Zuno AI respects your privacy and is committed to protecting your personal data.",
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 24),
            Text("1. Data Collection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              "We collect your email for authentication and user profile purposes. When you upload a face reference image, it is processed only for AI generation and is not stored permanently or shared with third parties without your consent.",
            ),
            SizedBox(height: 24),
            Text("2. Image Generation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              "The AI generation is powered by Gemini/Nano Banana. Images created are for your personal use. You are responsible for ensuring the content complies with safety guidelines.",
            ),
            SizedBox(height: 24),
            Text("3. Ads & Monetization", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              "We use Google Mobile Ads and Unity Ads to provide free generations. These services may collect certain device identifiers as per their own privacy policies.",
            ),
            SizedBox(height: 24),
            Text("4. Your Rights", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              "You can request deletion of your account and data at any time through the app settings or by contacting our support.",
            ),
            SizedBox(height: 48),
            Center(
              child: Text(
                "contact@zunoai.example.com",
                style: TextStyle(color: Colors.purpleAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
