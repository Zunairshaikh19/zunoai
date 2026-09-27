import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../models/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/iap_service.dart';
import '../../../services/analytics_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _isProcessing = false;
  ProductDetails? _monthlyProduct;

  @override
  void initState() {
    super.initState();
    // Already-premium users get the status view below (built straight from
    // userProvider) instead of the buy flow, so there's no need to spin up
    // the store connection and fetch product details for them.
    final isAlreadyPremium = ref.read(userProvider).value?.tier == UserTier.paid;
    if (!isAlreadyPremium) {
      _initIap();
    }
  }

  Future<void> _initIap() async {
    final iap = IapService();
    await iap.init(
      onPurchaseSuccess: (purchaseDetails) async {
        try {
          final purchaseToken = purchaseDetails.verificationData.serverVerificationData;
          await ref.read(firebaseServiceProvider).activatePremium(
                productId: purchaseDetails.productID,
                purchaseToken: purchaseToken.isNotEmpty ? purchaseToken : purchaseDetails.purchaseID ?? purchaseDetails.productID,
              );
          AnalyticsService().logPurchaseCompleted(
            productId: purchaseDetails.productID,
            value: 4.99,
            currency: 'USD',
          );
          if (mounted) {
            AppSnackBar.showSuccess(context, "Welcome to Zuno AI Premium!");
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            AppSnackBar.showError(context, "Couldn't activate premium: $e");
          }
        }
      },
      onPurchaseError: (error) {
        if (mounted) {
          AppSnackBar.showError(context, "Purchase Error: $error");
        }
      },
    );

    final products = await iap.fetchProducts({'zuno_premium_monthly'});
    if (products.isNotEmpty && mounted) {
      setState(() => _monthlyProduct = products.first);
    }
  }

  Future<void> _buyProduct() async {
    if (_monthlyProduct == null) {
      AppSnackBar.showInfo(context, "Store product details loading or unavailable.");
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await IapService().buyProduct(_monthlyProduct!);
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, "Transaction error: $e");
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isProcessing = true);
    try {
      await IapService().restorePurchases();
      if (mounted) {
        AppSnackBar.showSuccess(context, "Purchases restored successfully!");
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, "Restore failed: $e");
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider).value;
    final isPremium = user?.tier == UserTier.paid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Zuno AI Premium", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: isPremium && user != null
            ? _buildPremiumStatusView(user)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.electricLime.withValues(alpha: 0.1),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.electricLime.withValues(alpha: 0.1),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const FaIcon(FontAwesomeIcons.crown, size: 48, color: AppColors.electricLime),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Elite Creative Power",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Elevate your AI generation experience",
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    _buildFeatureRow(Icons.check_circle_rounded, "Unleash Full AI Potential"),
                    _buildFeatureRow(Icons.check_circle_rounded, "Priority Processing Speed"),
                    _buildFeatureRow(Icons.check_circle_rounded, "Ad-Free Creative Workspace"),
                    _buildFeatureRow(Icons.check_circle_rounded, "Exclusive Pro Prompt Styles"),
                    const SizedBox(height: 28),
                    _buildPriceCard(context),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _isProcessing ? null : _restorePurchases,
                      child: const Text("Restore Purchases", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  /// Shown instead of the buy flow once the user is already `UserTier.paid`
  /// — status + usage + the same benefits list as confirmation, no
  /// purchase CTA (there's nothing left for them to buy on this screen).
  Widget _buildPremiumStatusView(UserModel user) {
    final expiresText = user.premiumExpiresAt != null ? DateFormat.yMMMd().format(user.premiumExpiresAt!) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.electricLime.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricLime.withValues(alpha: 0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const FaIcon(FontAwesomeIcons.crown, size: 48, color: AppColors.electricLime),
          ),
          const SizedBox(height: 20),
          const Text(
            "You're Premium",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            expiresText != null ? "Renews on $expiresText" : "Active subscription",
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.electricLime, width: 1.5),
            ),
            child: Column(
              children: [
                const Text(
                  "Your Balance",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(FontAwesomeIcons.coins, color: Colors.amber, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      "${user.coins} coins",
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.electricLime),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  "Each generation uses coins from this balance",
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Your Benefits",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 4),
          _buildFeatureRow(Icons.check_circle_rounded, "Unleash Full AI Potential"),
          _buildFeatureRow(Icons.check_circle_rounded, "Priority Processing Speed"),
          _buildFeatureRow(Icons.check_circle_rounded, "Ad-Free Creative Workspace"),
          _buildFeatureRow(Icons.check_circle_rounded, "Exclusive Pro Prompt Styles"),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.electricLime, size: 20.0),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: Colors.white70))),
        ],
      ),
    );
  }

  Widget _buildPriceCard(BuildContext context) {
    final priceText = _monthlyProduct?.price ?? "\$4.99 / month";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.electricLime, width: 1.5),
      ),
      child: Column(
        children: [
          const Text(
            "Monthly Plan",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            priceText,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.electricLime),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _buyProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricLime,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColors.electricLime.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.black54,
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                    )
                  : const Text("Start Premium", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
