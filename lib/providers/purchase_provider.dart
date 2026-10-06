import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/iap_service.dart';
import 'user_provider.dart';

/// Outcome of a purchase attempt, shown by the paywall as a snackbar.
class PurchaseEvent {
  final bool success;
  final String message;
  const PurchaseEvent(this.success, this.message);
}

/// Owns the store connection for the whole app session (started once the user
/// is signed in), so a purchase that finishes after the paywall is closed — or
/// that is re-delivered on the next app start — is still verified and
/// activated by the backend.
class PurchaseCoordinator {
  final Ref _ref;
  final _events = StreamController<PurchaseEvent>.broadcast();

  PurchaseCoordinator(this._ref) {
    _start();
  }

  Stream<PurchaseEvent> get events => _events.stream;

  Future<void> _start() async {
    await IapService().init(
      onPurchase: _handlePurchase,
      onPurchaseError: (message) => _events.add(PurchaseEvent(false, "Purchase error: $message")),
    );
  }

  Future<bool> _handlePurchase(PurchaseDetails details) async {
    try {
      await _ref.read(firebaseServiceProvider).activatePremium(
            productId: details.productID,
            purchaseToken: details.verificationData.serverVerificationData,
          );

      final product = IapService().productById(details.productID);
      AnalyticsService().logPurchaseCompleted(
        productId: details.productID,
        value: product?.rawPrice ?? 0,
        currency: product?.currencyCode ?? 'USD',
      );
      _events.add(const PurchaseEvent(true, "Welcome to Zuno AI Premium!"));
      return true;
    } on ApiException catch (e) {
      _events.add(PurchaseEvent(false, "Couldn't activate premium: ${e.message}"));
      return false;
    } catch (_) {
      _events.add(const PurchaseEvent(false, "Couldn't activate premium. We'll retry automatically."));
      return false;
    }
  }

  void dispose() {
    _events.close();
  }
}

final purchaseCoordinatorProvider = Provider<PurchaseCoordinator>((ref) {
  final coordinator = PurchaseCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
