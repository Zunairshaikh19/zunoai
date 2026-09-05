import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../legal/presentation/privacy_policy_screen.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../monetization/presentation/paywall_screen.dart';

import '../../notifications/presentation/support_chat_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text("Not Logged In"));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _pickAndUploadProfilePic(context, ref, user.uid),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: AppColors.electricLime.withOpacity(0.1),
                        backgroundImage: user.photoUrl != null 
                            ? CachedNetworkImageProvider(user.photoUrl!) 
                            : null,
                        child: user.photoUrl == null 
                            ? const FaIcon(FontAwesomeIcons.solidUser, size: 40, color: AppColors.electricLime) 
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.electricLime,
                            shape: BoxShape.circle,
                          ),
                          child: const FaIcon(FontAwesomeIcons.camera, size: 12, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      (user.displayName != null && user.displayName!.isNotEmpty) 
                          ? user.displayName! 
                          : user.email.split('@')[0], // Email ki bajaye name show hoga
                      style: const TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 16, color: AppColors.electricLime),
                      onPressed: () => _showEditNameDialog(context, ref, user.uid, user.displayName),
                    ),
                  ],
                ),
                Text(
                  user.email,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  user.tier == UserTier.paid ? "Premium Member" : "Free Member",
                  style: const TextStyle(color: AppColors.electricLime, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                _buildReferralCard(context, user, ref),
                const SizedBox(height: 32),
                _buildSettingsList(context, ref),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text("Error loading profile: $err", textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(userProvider),
                child: const Text("Retry"),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(firebaseServiceProvider).signOut(),
                child: const Text("Logout"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfilePic(BuildContext context, WidgetRef ref, String uid) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    
    if (pickedFile != null) {
      try {
        await ref.read(firebaseServiceProvider).uploadProfilePicture(uid, File(pickedFile.path));
        ref.invalidate(userProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e")),
        );
      }
    }
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref, String uid, String? currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter your name",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ref.read(firebaseServiceProvider).updateDisplayName(uid, controller.text.trim());
                ref.invalidate(userProvider);
                Navigator.pop(context);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard(BuildContext context, UserModel user, WidgetRef ref) {
    final canRedeem = user.referredBy == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              "Refer & Earn",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Share your code with friends. Both get 40 coins (1 free generation) when they join!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    user.referralCode,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.copy, size: 18, color: Colors.white70),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: user.referralCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Code copied to clipboard!")),
                      );
                    },
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 18, color: AppColors.electricLime),
                    onPressed: () {
                      Share.share(
                        "Join Zuno AI and get 40 free coins for AI image generation! Use my referral code: ${user.referralCode}",
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Friends joined: ${user.referralCount}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.electricLime),
            ),
            if (canRedeem) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.redeem),
                label: const Text("Have a referral code?"),
                onPressed: () => _showRedeemDialog(context, ref, user.uid),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRedeemDialog(BuildContext context, WidgetRef ref, String uid) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Redeem Code"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter friend's code",
            labelText: "Referral Code",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(firebaseServiceProvider).redeemReferralCode(uid, controller.text.trim().toUpperCase());
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Bonus claimed successfully!")),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
              }
            },
            child: const Text("Claim Bonus"),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildSettingsTile(
          icon: FontAwesomeIcons.crown,
          title: "Zuno Premium",
          iconColor: Colors.amber,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PaywallScreen()),
          ),
        ),
        _buildSettingsTile(
          icon: FontAwesomeIcons.solidBell,
          title: "Notifications",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NotificationsScreen()),
          ),
        ),
        _buildSettingsTile(
          icon: FontAwesomeIcons.headset,
          title: "Support Center",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SupportChatScreen()),
          ),
        ),
        _buildSettingsTile(
          icon: FontAwesomeIcons.shieldHalved,
          title: "Privacy & Security",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
          ),
        ),
        _buildSettingsTile(
          icon: FontAwesomeIcons.rightFromBracket,
          title: "Logout",
          iconColor: Colors.redAccent,
          textColor: Colors.redAccent,
          onTap: () async {
            await ref.read(firebaseServiceProvider).signOut();
          },
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required dynamic icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
    Color textColor = Colors.white,
  }) {
    return ListTile(
      leading: _buildIcon(icon, iconColor),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
      trailing: const FaIcon(FontAwesomeIcons.chevronRight, color: Colors.white12, size: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
    );
  }

  Widget _buildIcon(dynamic icon, Color color) {
    const size = 18.0;
    if (icon is FaIconData) {
      return FaIcon(icon as FaIconData, color: color, size: size);
    }
    return Icon(icon as IconData, color: color, size: size);
  }
}
