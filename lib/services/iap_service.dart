import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Called for every purchased/restored item. Return true ONLY when the backend
/// verified it and premium is active — only then is the purchase completed
/// (acknowledged). If it returns false the store keeps the purchase pending and
/// re-delivers it on the next launch, so a paying customer is never left
/// without their premium because of a network blip.
typedef PurchaseHandler = Future<bool> Function(PurchaseDetails details);

class IapService {
  static final IapService _instance = IapService._internal();
  factory IapService() => _instance;
  IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => _products;

  PurchaseHandler? _onPurchase;
  void Function(String)? _onPurchaseError;
  final Set<String> _inFlight = {};

  /// Starts listening to the store. Call once at app start (not from a screen)
  /// so purchases that complete later — slow payments, app restarts — are
  /// still processed.
  Future<void> init({
    required PurchaseHandler onPurchase,
    void Function(String)? onPurchaseError,
  }) async {
    _onPurchase = onPurchase;
    _onPurchaseError = onPurchaseError;

    if (_subscription != null) return; // already listening

    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint("IAP Service: Storefront unavailable");
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        _subscription?.cancel();
        _subscription = null;
      },
      onError: (error) => debugPrint("IAP Stream Error: $error"),
    );
  }

  Future<List<ProductDetails>> fetchProducts(Set<String> productIds) async {
    if (!_isAvailable) _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) return [];
    final ProductDetailsResponse response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      debugPrint("IAP Product Query Error: ${response.error!.message}");
      return [];
    }
    _products = response.productDetails;
    return _products;
  }

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<bool> buyProduct(ProductDetails product) async {
    if (!_isAvailable) return false;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions are non-consumable: the store tracks renewal/expiry itself.
    return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          debugPrint("IAP: Purchase Pending for ${purchaseDetails.productID}");
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final key = purchaseDetails.purchaseID ?? purchaseDetails.verificationData.serverVerificationData;
          if (!_inFlight.add(key)) break; // already being processed
          try {
            final handler = _onPurchase;
            final ok = handler != null ? await handler(purchaseDetails) : false;
            if (ok && purchaseDetails.pendingCompletePurchase) {
              await _iap.completePurchase(purchaseDetails);
            }
          } catch (e) {
            debugPrint("IAP: handler failed: $e");
          } finally {
            _inFlight.remove(key);
          }
          break;

        case PurchaseStatus.error:
          debugPrint("IAP: Purchase Error ${purchaseDetails.error?.message}");
          _onPurchaseError?.call(purchaseDetails.error?.message ?? "Purchase failed");
          if (purchaseDetails.pendingCompletePurchase) {
            await _iap.completePurchase(purchaseDetails);
          }
          break;

        case PurchaseStatus.canceled:
          debugPrint("IAP: Purchase Canceled by User");
          if (purchaseDetails.pendingCompletePurchase) {
            await _iap.completePurchase(purchaseDetails);
          }
          break;
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
