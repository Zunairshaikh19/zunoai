import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../models/user_model.dart';
import '../../../models/economy_config.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/economy_provider.dart';
import '../../../providers/purchase_provider.dart';
import '../../../services/iap_service.dart';

const String _kMonthlyProductId = 'zuno_premium_monthly';
// Create both as subscriptions in Play Console (see PRODUCTION_CHECKLIST.md).
// Prices: $9.99 / month and $79.99 / year (set in Play Console, not here).
const String _kYearlyProductId = 'zuno_premium_yearly';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _isProcessing = false;
  bool _productsLoaded = false;
  ProductDetails? _monthlyProduct;
  ProductDetails? _yearlyProduct;
  String _selectedPlan = 'yearly'; // preferred once/if a yearly product exists

  @override
  void initState() {
    super.initState();
    // Already-premium users get the status view below (built straight from
    // userProvider) instead of the buy flow, so there's no need to spin up
    // the store connection and fetch product details for them.
    final isAlreadyPremium = ref.read(userProvider).value?.isPremium ?? false;
    if (!isAlreadyPremium) {
      _initIap();
    }
  }

  StreamSubscription<PurchaseEvent>? _purchaseSub;

  Future<void> _initIap() async {
    // The PurchaseCoordinator (started at app launch) verifies purchases with
    // the backend; this screen only reacts to its result.
    _purchaseSub = ref.read(purchaseCoordinatorProvider).events.listen((event) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (event.success) {
        AppSnackBar.showSuccess(context, event.message);
        Navigator.pop(context);
      } else {
        AppSnackBar.showError(context, event.message);
      }
    });

    final products = await IapService().fetchProducts({_kMonthlyProductId, _kYearlyProductId});
    if (mounted) {
      setState(() {
        _productsLoaded = true;
        for (final p in products) {
          if (p.id == _kMonthlyProductId) _monthlyProduct = p;
          if (p.id == _kYearlyProductId) _yearlyProduct = p;
        }
        if (_yearlyProduct == null) _selectedPlan = 'monthly';
      });
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  ProductDetails? get _activeProduct => _selectedPlan == 'yearly' ? _yearlyProduct : _monthlyProduct;

  Future<void> _buyProduct() async {
    final product = _activeProduct;
    if (product == null) {
      AppSnackBar.showInfo(context, "Store product details loading or unavailable.");
      return;
    }
    if (ref.read(userProvider).value == null) {
      AppSnackBar.showInfo(context, "Please sign in first.");
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final started = await IapService().buyProduct(product);
      // The result (success/failure) arrives through the coordinator stream.
      if (!started && mounted) setState(() => _isProcessing = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, "Transaction error: $e");
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isProcessing = true);
    try {
      await IapService().restorePurchases();
      // Restored purchases are re-verified by the backend; a success/failure
      // message is shown from the coordinator stream. Nothing to restore =>
      // no event, so tell the user we checked.
      if (mounted) AppSnackBar.showInfo(context, "Checking your purchases...");
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
    final config = ref.watch(economyConfigProvider).valueOrNull ?? const EconomyConfig();
    final isPremium = user?.isPremium ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Zuno AI Premium", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: isPremium && user != null
            ? _buildPremiumStatusView(user)
            : _buildBuyFlow(context, user, config),
      ),
    );
  }

  Widget _buildBuyFlow(BuildContext context, UserModel? user, EconomyConfig config) {
    final isLowOnCoins = user != null && user.coins < config.generationCost;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isLowOnCoins) ...[
            _buildLowCoinsBanner(user!, config),
            const SizedBox(height: 18),
          ],
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
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
              child: const FaIcon(FontAwesomeIcons.crown, size: 40, color: AppColors.electricLime),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "More images,\nno ads, no waiting",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            "Premium gives you a bigger daily coin allowance every day.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildValueRow(FontAwesomeIcons.coins, "${config.dailyBonusPremium} coins every day (monthly)", "~${(config.dailyBonusPremium * 30 / config.generationCost).floor()} images/mo"),
          const SizedBox(height: 9),
          _buildValueRow(FontAwesomeIcons.coins, "${config.dailyBonusPremiumYearly} coins every day (yearly)", "~${(config.dailyBonusPremiumYearly * 30 / config.generationCost).floor()} images/mo"),
          const SizedBox(height: 9),
          _buildValueRow(FontAwesomeIcons.wandMagicSparkles, "Exclusive Pro styles", "Premium only"),
          const SizedBox(height: 9),
          _buildValueRow(FontAwesomeIcons.ban, "No ads, free watermark removal", "Included"),
          const SizedBox(height: 22),
          _buildPlanSelector(),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
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
                  : Text(_ctaLabel(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: AppColors.electricLime),
              SizedBox(width: 4),
              Text("Cancel anytime in Google Play", style: TextStyle(fontSize: 11, color: Colors.white38)),
              SizedBox(width: 14),
              Icon(Icons.lock_rounded, size: 13, color: AppColors.electricLime),
              SizedBox(width: 4),
              Text("Secure checkout", style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isProcessing ? null : _restorePurchases,
            child: const Text("Restore Purchases", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _ctaLabel() {
    final product = _activeProduct;
    if (product == null) return _productsLoaded ? "Store unavailable" : "Loading...";
    return "Start Premium — ${product.price}";
  }

  Widget _buildLowCoinsBanner(UserModel user, EconomyConfig config) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Only ${user.coins} coins left — you need ${config.generationCost} for your next generation",
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueRow(FaIconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.electricLime.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: FaIcon(icon, size: 13, color: AppColors.electricLime),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.electricLime)),
        ],
      ),
    );
  }

  Widget _buildPlanSelector() {
    final hasYearly = _yearlyProduct != null;

    return Column(
      children: [
        if (hasYearly) ...[
          _buildPlanCard(
            selected: _selectedPlan == 'yearly',
            badge: "BEST VALUE",
            title: "Yearly",
            subtitle: "${_yearlyProduct!.price} / year",
            onTap: () => setState(() => _selectedPlan = 'yearly'),
          ),
          const SizedBox(height: 10),
        ],
        _buildPlanCard(
          selected: _selectedPlan == 'monthly' || !hasYearly,
          title: "Monthly",
          subtitle: _monthlyProduct != null ? "${_monthlyProduct!.price} / month" : (_productsLoaded ? "Unavailable right now" : "Loading..."),
          onTap: () => setState(() => _selectedPlan = 'monthly'),
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? AppColors.electricLime.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.electricLime : Colors.white.withValues(alpha: 0.08), width: 2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (badge != null)
              Positioned(
                top: -22,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.electricLime, borderRadius: BorderRadius.circular(100)),
                  child: Text(badge, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? AppColors.electricLime : Colors.white24, width: 2),
                    color: selected ? AppColors.electricLime : Colors.transparent,
                  ),
                  child: selected ? const Icon(Icons.circle, size: 9, color: Colors.black) : null,
                ),
              ],
            ),
          ],
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
            expiresText != null ? "Active until $expiresText (renews unless cancelled)" : "Active subscription",
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
                  "Each image costs coins from this balance. Your daily allowance refills every UTC day.",
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
          _buildFeatureRow(Icons.check_circle_rounded, "Bigger daily coin allowance"),
          _buildFeatureRow(Icons.check_circle_rounded, "Ad-Free Creative Workspace"),
          _buildFeatureRow(Icons.check_circle_rounded, "Free watermark removal"),
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
}
