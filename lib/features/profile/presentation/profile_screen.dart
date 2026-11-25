import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/user_model.dart';
import '../../../models/economy_config.dart';
import '../../../providers/root_index_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/economy_provider.dart';
import '../../../providers/saved_prompts_provider.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../services/api_client.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../../legal/presentation/terms_screen.dart';
import '../../generation/presentation/history_screen.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../monetization/presentation/paywall_screen.dart';

import '../../notifications/presentation/support_chat_screen.dart';
import '../../../core/widgets/dynamic_icon.dart';
import '../../../core/widgets/guest_sign_in_prompt.dart';

class ProfileScreen extends ConsumerWidget {
  /// True when opened with Navigator.push (e.g. from the coin store); false
  /// when it is the Profile tab inside the root IndexedStack.
  final bool pushed;

  const ProfileScreen({super.key, this.pushed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    final config = ref.watch(economyConfigProvider).valueOrNull ?? const EconomyConfig();

    return Scaffold(
      appBar: AppBar(
        // Profile lives in the tab IndexedStack, not on the Navigator stack,
        // so there's nothing for Flutter to auto-pop back to — this button
        // instead switches the root tab index back to Dashboard (0).
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back to Dashboard",
          onPressed: () {
            if (pushed) {
              Navigator.of(context).pop();
            } else {
              ref.read(rootIndexProvider.notifier).state = 0;
            }
          },
        ),
        title: const Text("Profile", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const GuestSignInPrompt(
              title: 'Sign in to your profile',
              message: 'Sign in to see your coins, creations and saved styles.',
            );
          }

          final creationsCount = ref.watch(historyProvider(user.uid)).valueOrNull?.length ?? 0;
          final savedCount = ref.watch(savedPromptsProvider).length;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, ref, user),
                const SizedBox(height: 16),
                _buildStatsRow(user, creationsCount, savedCount),
                const SizedBox(height: 16),
                _buildReferralCard(context, user, ref, config),
                const SizedBox(height: 16),
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

  Widget _buildHeader(BuildContext context, WidgetRef ref, UserModel user) {
    final isPaid = user.tier == UserTier.paid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: "Change profile picture",
          child: GestureDetector(
            onTap: () => _pickAndUploadProfilePic(context, ref, user.uid),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 29,
                  backgroundColor: AppColors.electricLime.withValues(alpha: 0.1),
                  backgroundImage: user.photoUrl != null ? CachedNetworkImageProvider(user.photoUrl!) : null,
                  child: user.photoUrl == null
                      ? const FaIcon(FontAwesomeIcons.solidUser, size: 24, color: AppColors.electricLime)
                      : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.electricLime,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Colors.black, width: 2)),
                    ),
                    child: const FaIcon(FontAwesomeIcons.camera, size: 11, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      (user.displayName != null && user.displayName!.isNotEmpty)
                          ? user.displayName!
                          : user.email.split('@')[0],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 13, color: AppColors.electricLime),
                    tooltip: "Edit name",
                    padding: const EdgeInsets.only(left: 4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showEditNameDialog(context, ref, user.uid, user.displayName),
                  ),
                ],
              ),
              Text(
                isPaid ? "Premium Member" : user.email,
                style: TextStyle(color: isPaid ? AppColors.electricLime : Colors.white38, fontSize: 12, fontWeight: isPaid ? FontWeight.w700 : FontWeight.normal),
              ),
            ],
          ),
        ),
        if (!isPaid)
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen())),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.electricLime.withValues(alpha: 0.12),
              foregroundColor: AppColors.electricLime,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: const StadiumBorder(),
            ),
            child: const Text("Upgrade", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildStatsRow(UserModel user, int creationsCount, int savedCount) {
    return Row(
      children: [
        Expanded(child: _statTile(_compact(user.coins), "COINS", valueColor: AppColors.electricLime)),
        const SizedBox(width: 10),
        Expanded(child: _statTile("$creationsCount", "CREATIONS")),
        const SizedBox(width: 10),
        Expanded(child: _statTile("$savedCount", "SAVED")),
      ],
    );
  }

  String _compact(int value) {
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(1)}K";
    return "$value";
  }

  Widget _statTile(String value, String label, {Color valueColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: valueColor)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 0.3)),
        ],
      ),
    );
  }

  Widget _buildReferralCard(BuildContext context, UserModel user, WidgetRef ref, EconomyConfig config) {
    final canRedeem = user.referredBy == null;
    const goal = 5;
    final joined = user.referralCount.clamp(0, goal);
    final remaining = (goal - joined).clamp(0, goal);
    final progress = joined / goal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  remaining == 0 ? "Referral goal reached!" : "Invite $remaining more friend${remaining == 1 ? '' : 's'}",
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              Text("+${config.referralReward} coins each", style: const TextStyle(fontSize: 11, color: AppColors.electricLime, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(AppColors.electricLime),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  "$joined of $goal friends joined · code ${user.referralCode}",
                  style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.copy, size: 14, color: Colors.white54),
                tooltip: "Copy referral code",
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: user.referralCode));
                  AppSnackBar.showSuccess(context, "Code copied to clipboard!");
                },
              ),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 14, color: AppColors.electricLime),
                tooltip: "Share referral code",
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
                onPressed: () {
                  Share.share(
                    "Join Zuno AI and get ${config.referralReward} free coins for AI image generation! Use my referral code: ${user.referralCode}",
                  );
                },
              ),
            ],
          ),
          if (canRedeem) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.redeem, size: 16),
                label: const Text("Have a referral code?", style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: () => _showRedeemDialog(context, ref, user.uid),
              ),
            ),
          ],
        ],
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
        if (context.mounted) {
          AppSnackBar.showSuccess(context, "Profile picture updated!");
        }
      } catch (e) {
        if (context.mounted) {
          AppSnackBar.showError(context, "Upload failed: $e");
        }
      }
    }
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref, String uid, String? currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => _ZunoDialog(
        icon: FontAwesomeIcons.penToSquare,
        title: "Edit Name",
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Enter your name",
          ),
        ),
        cancelLabel: "Cancel",
        confirmLabel: "Save",
        onConfirm: () async {
          if (controller.text.trim().isNotEmpty) {
            await ref.read(firebaseServiceProvider).updateDisplayName(uid, controller.text.trim());
            ref.invalidate(userProvider);
            if (context.mounted) Navigator.pop(context);
          }
        },
      ),
    );
  }

  void _showRedeemDialog(BuildContext context, WidgetRef ref, String uid) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => _ZunoDialog(
        icon: Icons.redeem,
        title: "Redeem Code",
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: "Enter friend's code",
            labelText: "Referral Code",
          ),
        ),
        cancelLabel: "Cancel",
        confirmLabel: "Claim Bonus",
        onConfirm: () async {
          try {
            final code = controller.text.trim().toUpperCase();
            if (code.isEmpty) return;
            final coins = await ref.read(firebaseServiceProvider).redeemReferralCode(code);
            if (context.mounted) {
              Navigator.pop(context);
              AppSnackBar.showSuccess(context, "Bonus claimed! +$coins coins");
            }
          } on ApiException catch (e) {
            if (context.mounted) AppSnackBar.showError(context, e.message);
          } catch (_) {
            if (context.mounted) AppSnackBar.showError(context, "Couldn't redeem the code. Please try again.");
          }
        },
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ZunoDialog(
        icon: Icons.delete_forever,
        title: "Delete account?",
        content: const Text(
          "This permanently deletes your account, your creations, your coins and any Premium benefits tied to it. "
          "An active Google Play subscription is NOT cancelled automatically — cancel it in Google Play first. This cannot be undone.",
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        cancelLabel: "Cancel",
        confirmLabel: "Delete Forever",
        onConfirm: () async {
          final service = ref.read(firebaseServiceProvider);
          try {
            await service.deleteAccount();
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } on ApiException catch (e) {
            if (context.mounted) AppSnackBar.showError(context, e.message);
          } catch (_) {
            if (context.mounted) AppSnackBar.showError(context, "Couldn't delete the account. Please try again.");
          }
        },
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
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
            icon: FontAwesomeIcons.headset,
            title: "Support Center",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SupportChatScreen()),
            ),
          ),
          _buildSettingsTile(
            icon: FontAwesomeIcons.images,
            title: "My Creations",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
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
            icon: FontAwesomeIcons.shieldHalved,
            title: "Privacy Policy",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
            ),
          ),
          _buildSettingsTile(
            icon: FontAwesomeIcons.fileContract,
            title: "Terms of Use",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TermsScreen()),
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
          _buildSettingsTile(
            icon: FontAwesomeIcons.userXmark,
            title: "Delete Account",
            iconColor: Colors.redAccent,
            textColor: Colors.redAccent,
            isLast: true,
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required dynamic icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
    Color textColor = Colors.white,
    bool isLast = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: ListTile(
        leading: DynamicIcon(icon, size: 18, color: iconColor),
        title: Text(title, style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w700)),
        trailing: const FaIcon(FontAwesomeIcons.chevronRight, color: Colors.white24, size: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        onTap: onTap,
      ),
    );
  }
}

/// Shared dark-themed dialog used across Profile so prompts like "Edit Name"
/// and "Redeem Code" look like the rest of the app instead of the generic
/// Material AlertDialog.
class _ZunoDialog extends StatelessWidget {
  final dynamic icon;
  final String title;
  final Widget content;
  final String cancelLabel;
  final String confirmLabel;
  final Future<void> Function() onConfirm;

  const _ZunoDialog({
    required this.icon,
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.electricLime.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: icon is FaIconData
                      ? FaIcon(icon as FaIconData, size: 16, color: AppColors.electricLime)
                      : Icon(icon as IconData, size: 18, color: AppColors.electricLime),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            content,
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
