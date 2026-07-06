import 'package:in_app_purchase_storekit/store_kit_wrappers.dart'
    show
        SKPaymentQueueDelegateWrapper,
        SKPaymentTransactionWrapper,
        SKStorefrontWrapper;

class AppleQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
    SKPaymentTransactionWrapper transaction,
    SKStorefrontWrapper storefront,
  ) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}
