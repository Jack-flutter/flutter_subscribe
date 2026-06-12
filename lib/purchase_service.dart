import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'apple_delegate.dart';
import 'purchase_data.dart';

mixin PurchaseService {
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;

  Function(bool success)? _purchaseCall;

  PurchaseConfig config = PurchaseConfig(
    hotCode: '',
    selectedCode: '',
    list: [],
  );

  bool _isEffective = false;
  bool _isExecute = false;

  /// 初始化 SDK
  Future<void> initializeSdk() async {
    // 创建监听
    _purchaseStreamSubscription = InAppPurchase.instance.purchaseStream.listen(
      cancelOnError: false,
          (List<PurchaseDetails> purchaseDetailsList) {
        _onPurchaseMonitor(purchaseDetailsList);
      },
      onDone: () {
        _purchaseStreamSubscription?.cancel();
      },
      onError: (Object error) {
        _notifyPurchasCallNotice(false);
      },
    );

    final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
    InAppPurchase.instance
        .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
    await iosPlatformAddition.setDelegate(AppleQueueDelegate());
  }

  /// 安卓订阅验证
  Future<bool> purchaseAndroidVerify(GooglePlayPurchaseDetails? details);

  /// 苹果订阅验证
  Future<bool> purchaseAppleVerify({required String receiptData});

  /// 获取订单数据
  Future<PurchaseConfig?> getPurchaseList(bool develop) async {
    if (_isEffective == true && config.list.isNotEmpty) return config;
    if (develop == true) {
      await Future.delayed(const Duration(seconds: 2));
      return config;
    } else {
      Set<String> productIds = config.list.map((item) => item.id).toSet();

      final ProductDetailsResponse productResponse = await InAppPurchase
          .instance
          .queryProductDetails(productIds);

      if (productResponse.error != null) return config;

      for (final item in config.list) {
        for (final details in productResponse.productDetails) {
          if (details.id == item.id) {
            item.details = details;
            break;
          }
        }
      }
    }

    _isEffective = true;
    return config;
  }

  /// 更新订单配置
  void updatePurchasesConfig(String json) {
    config = PurchaseConfig.fromJson(jsonDecode(json));
  }

  /// 购买订单
  Future<void> purchaseBuy({
    required ProductDetails details,
    required Function(bool success) purchaseCall,
  }) async {
    if (_isExecute) return;

    _isExecute = true;
    _purchaseCall = purchaseCall;

    final bool isAvailable = await InAppPurchase.instance.isAvailable();
    if (!isAvailable) {
      _isExecute = false;
      _notifyPurchasCallNotice(false);
      return;
    }
    try {
      await _clearPendingPurchases();
      final bool purchaseState = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      _isExecute = false;
      if (!purchaseState) {
        _notifyPurchasCallNotice(false);
      }
    } catch (_) {
      _isExecute = false;
      _notifyPurchasCallNotice(false);
    }
  }

  /// 恢复购买订单
  Future<void> purchaseRestore(Function(bool success)? restoreCall) async {
    if (_isExecute) return;

    _isExecute = true;
    _purchaseCall = restoreCall;

    if (Platform.isIOS) {
      await _purchasedAppleBuy();
    } else {
      await InAppPurchase.instance.restorePurchases();
    }
  }

  /// 清除无效订单
  Future<void> _clearPendingPurchases() async {
    if (Platform.isAndroid) return;

    try {
      final transactions = await SKPaymentQueueWrapper().transactions();
      for (final transaction in transactions) {
        try {
          await SKPaymentQueueWrapper().finishTransaction(transaction);
        } catch (e) {
          rethrow;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 购买更新监听
  void _onPurchaseMonitor(List<PurchaseDetails> purchaseDetailsList) {
    if (purchaseDetailsList.isEmpty && Platform.isAndroid) {
      purchaseAndroidVerify(null);
      _notifyPurchasCallNotice(true);
      return;
    }

    final List<PurchaseDetails> orderList = List.from(purchaseDetailsList);
    orderList.sort(
          (a, b) =>
          (int.tryParse(b.transactionDate ?? '') ?? 0).compareTo(
            int.tryParse(a.transactionDate ?? '') ?? 0,
          ),
    );

    final firstPurchase = orderList.first;
    for (PurchaseDetails purchase in orderList) {
      if (purchase.pendingCompletePurchase == false) continue;
      InAppPurchase.instance.completePurchase(purchase);
    }

    if (firstPurchase.status == PurchaseStatus.pending) {
      _onPurchasePending();
    } else if (firstPurchase.status == PurchaseStatus.canceled) {
      _onPurchaseError(firstPurchase);
    } else if (firstPurchase.status == PurchaseStatus.error) {
      _onPurchaseError(firstPurchase);
    } else if (firstPurchase.status == PurchaseStatus.purchased ||
        firstPurchase.status == PurchaseStatus.restored) {
      if (Platform.isAndroid) {
        var googleDetail = firstPurchase as GooglePlayPurchaseDetails;
        _purchasedAndroid(googleDetail);
      } else if (Platform.isIOS) {
        _purchasedAppleBuy();
      }
    }
  }

  void _purchasedAndroid(GooglePlayPurchaseDetails? details) async {
    final res = await purchaseAndroidVerify(details);
    _notifyPurchasCallNotice(res);
  }

  Future _purchasedAppleBuy() async {
    try {
      await SKRequestMaker().startRefreshReceiptRequest();
      final receiptData = await SKReceiptManager.retrieveReceiptData();
      final res = await purchaseAppleVerify(receiptData: receiptData);
      _notifyPurchasCallNotice(res);
    } catch (_) {
      _isExecute = false;
      _notifyPurchasCallNotice(false);
    }
  }

  /// 购买失败处理
  void _onPurchaseError(PurchaseDetails purchase) {
    _notifyPurchasCallNotice(false);
  }

  /// 等待支付处理
  void _onPurchasePending() {}

  /// 发送回调事件
  void _notifyPurchasCallNotice(bool success) {
    _purchaseCall?.call(success);
    _purchaseCall = null;
    _isExecute = false;
  }
}
