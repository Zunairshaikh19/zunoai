import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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

  // Function callbacks for handling purchase completions
  Function(PurchaseDetails)? _onPurchaseSuccess;
  Function(String)? _onPurchaseError;

  Future<void> init({
    Function(PurchaseDetails)? onPurchaseSuccess,
    Function(String)? onPurchaseError,
  }) async {
    _onPurchaseSuccess = onPurchaseSuccess;
    _onPurchaseError = onPurchaseError;

    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint("IAP Service: Storefront unavailable");
      return;
    }

    _subscription?.cancel();
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint("IAP Stream Error: $error"),
    );
  }

  Future<List<ProductDetails>> fetchProducts(Set<String> productIds) async {
    if (!_isAvailable) return [];
    final ProductDetailsResponse response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      debugPrint("IAP Product Query Error: ${response.error!.message}");
      return [];
    }
    _products = response.productDetails;
    return _products;
  }

  Future<bool> buyProduct(ProductDetails product) async {
    if (!_isAvailable) return false;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions are non-consumable: the store tracks renewal/expiry itself,
    // unlike a coin pack which is consumed and re-purchasable.
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
          debugPrint("IAP: Purchase Successful for ${purchaseDetails.productID}");
          if (_onPurchaseSuccess != null) {
            await _onPurchaseSuccess!(purchaseDetails);
          }
          if (purchaseDetails.pendingCompletePurchase) {
            await _iap.completePurchase(purchaseDetails);
          }
          break;

        case PurchaseStatus.error:
          debugPrint("IAP: Purchase Error ${purchaseDetails.error?.message}");
          if (_onPurchaseError != null) {
            _onPurchaseError!(purchaseDetails.error?.message ?? "Purchase failed");
          }
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
  }
}
