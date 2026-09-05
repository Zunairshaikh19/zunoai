import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/image_prompt.dart';
import '../../../providers/user_provider.dart';
import '../../generation/presentation/upload_screen.dart';
import '../../monetization/presentation/coin_dialog.dart';

class DetailScreen extends ConsumerWidget {
  final ImagePrompt prompt;
  const DetailScreen({super.key, required this.prompt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: prompt.imageUrl,
              fit: BoxFit.cover,
            ),
          ),
          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.9),
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.chevronLeft, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 100), // Push content down
                          Row(
                            children: [
                              const FaIcon(FontAwesomeIcons.wandMagicSparkles, color: AppColors.electricLime, size: 14),
                              const SizedBox(width: 8),
                              Text(
                                prompt.category.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.electricLime,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.0,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Style Blueprint",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Blurred Prompt Box
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 250), // Fixed maximum height
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Text(
                                    prompt.hiddenPrompt.replaceAll(RegExp(r'\w'), '*'),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 16,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: ElevatedButton(
                              onPressed: () {
                                if (user != null && user.coins >= 40) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => UploadScreen(prompt: prompt),
                                    ),
                                  );
                                } else {
                                  showDialog(
                                    context: context,
                                    builder: (context) => const CoinDialog(),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.electricLime,
                                foregroundColor: Colors.black,
                                shape: const StadiumBorder(),
                              ),
                              child: const Text(
                                "Generate for Me",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              "Costs 40 Zuno Coins",
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
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
