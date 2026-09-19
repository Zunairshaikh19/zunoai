import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/user_provider.dart';

/// Guards against re-showing the sheet on every rebuild while it's already
/// open (or was just answered this session).
final genderPickerShownProvider = StateProvider<bool>((ref) => false);

/// One-time picker so the prompt gallery can show only prompts tagged for
/// this user's gender (plus unisex/couple). Shown once, from the dashboard,
/// while `user.gender` is null; skipping defaults to 'unisex' so the person
/// isn't asked again.
class GenderPickerSheet extends ConsumerWidget {
  const GenderPickerSheet({super.key});

  static void showIfNeeded(BuildContext context, WidgetRef ref) {
    final user = ref.read(userProvider).value;
    if (user == null || user.gender != null) return;
    if (ref.read(genderPickerShownProvider)) return;
    ref.read(genderPickerShownProvider.notifier).state = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const GenderPickerSheet(),
    );
  }

  Widget _option(BuildContext context, WidgetRef ref, {required String label, required FaIconData icon, required String value}) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(userProvider.notifier).setGender(value);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              FaIcon(icon, size: 32, color: AppColors.electricLime),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Who are we creating for?",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            "This just tailors which styles show up in your gallery.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _option(context, ref, label: "Male", icon: FontAwesomeIcons.mars, value: "male"),
              const SizedBox(width: 16),
              _option(context, ref, label: "Female", icon: FontAwesomeIcons.venus, value: "female"),
            ],
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref.read(userProvider.notifier).setGender("unisex");
              Navigator.pop(context);
            },
            child: const Text("Skip — show me everything", style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
