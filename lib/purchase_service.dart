import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'apple_delegate.dart';
import 'purchase_data.dart';

enum PurchaseType { suc, verify, serevers, fail }

mixin PurchaseService {
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;

  Function(PurchaseType)? _purchaseCall;

  PurchaseConfig config = PurchaseConfig(
    hotCode: '',
    selectedCode: '',
    list: [],
  );

  bool _isEffective = false;

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
      onError: (Object error) {},
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
      _isEffective = true;
      await Future.delayed(const Duration(seconds: 2));
      return config;
    } else {
      try {
        Set<String> productIds = config.list.map((item) => item.id).toSet();

        final ProductDetailsResponse productResponse = await InAppPurchase
            .instance
            .queryProductDetails(productIds);

        if (productResponse.error != null ||
            productResponse.productDetails.isEmpty) {
          _isEffective = false;
          return config;
        }

        for (final item in config.list) {
          for (final details in productResponse.productDetails) {
            if (details.id == item.id) {
              item.details = details;
              break;
            }
          }
        }
        _isEffective = true;
      } catch (_) {
        _isEffective = false;
      }
    }
    return config;
  }

  /// 更新订单配置
  void updatePurchasesConfig(String json) {
    if (_isEffective == true) return;
    config = PurchaseConfig.fromJson(jsonDecode(json));
  }

  /// 购买订单
  Future<void> purchaseBuy({
    required ProductDetails details,
    Function(PurchaseType)? purchaseCall,
  }) async {
    _purchaseCall = purchaseCall;

    final bool isAvailable = await InAppPurchase.instance.isAvailable();
    if (!isAvailable) {
      _notifyPurchasCallNotice(PurchaseType.fail);
      return;
    }
    try {
      await _clearPendingPurchases();
      final bool purchaseState = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (purchaseState == false) {
        _notifyPurchasCallNotice(PurchaseType.fail);
      }
    } catch (_) {
      _notifyPurchasCallNotice(PurchaseType.fail);
    }
  }

  /// 恢复购买订单
  Future<void> purchaseRestore({Function(PurchaseType)? purchaseCall}) async {
    _purchaseCall = purchaseCall;

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
    if (purchaseDetailsList.isEmpty) {
      _notifyPurchasCallNotice(PurchaseType.fail);
      return;
    }
    final List<PurchaseDetails> orderList = List.from(purchaseDetailsList);
    orderList.sort(
      (a, b) => (int.tryParse(b.transactionDate ?? '') ?? 0).compareTo(
        int.tryParse(a.transactionDate ?? '') ?? 0,
      ),
    );

    final firstPurchase = orderList.first;
    bool isVerify = false;
    for (PurchaseDetails purchase in orderList) {
      if (purchase.pendingCompletePurchase == false) continue;
      InAppPurchase.instance.completePurchase(purchase);
      isVerify = true;
    }
    if (isVerify == true) _notifyPurchasCallNotice(PurchaseType.verify);
    if (firstPurchase.status == PurchaseStatus.pending) {
      _onPurchasePending();
    } else if (firstPurchase.status == PurchaseStatus.canceled) {
      _onPurchaseError(firstPurchase);
    } else if (firstPurchase.status == PurchaseStatus.error) {
      _onPurchaseError(firstPurchase);
    } else if (firstPurchase.status == PurchaseStatus.purchased ||
        firstPurchase.status == PurchaseStatus.restored) {
      _notifyPurchasCallNotice(PurchaseType.suc);
      if (Platform.isAndroid) {
        var googleDetail = firstPurchase as GooglePlayPurchaseDetails;
        _purchasedAndroid(googleDetail);
      } else if (Platform.isIOS) {
        _purchasedAppleBuy();
      }
    }
  }

  void _purchasedAndroid(GooglePlayPurchaseDetails? details) async {
    try {
      final res = await purchaseAndroidVerify(details);
      final PurchaseType type = res ? PurchaseType.serevers : PurchaseType.fail;
      _notifyPurchasCallNotice(type);
    } catch (_) {
      _notifyPurchasCallNotice(PurchaseType.fail);
    }
  }

  Future _purchasedAppleBuy() async {
    try {
      await SKRequestMaker().startRefreshReceiptRequest();
      final receiptData = await SKReceiptManager.retrieveReceiptData();
      final res = await purchaseAppleVerify(receiptData: receiptData);
      final PurchaseType type = res ? PurchaseType.serevers : PurchaseType.fail;
      _notifyPurchasCallNotice(type);
    } catch (_) {
      _notifyPurchasCallNotice(PurchaseType.fail);
    }
  }

  /// 购买失败处理
  void _onPurchaseError(PurchaseDetails purchase) {
    _notifyPurchasCallNotice(PurchaseType.fail);
  }

  /// 等待支付处理
  void _onPurchasePending() {}

  /// 发送订阅回调事件
  void _notifyPurchasCallNotice(PurchaseType type) {
    _purchaseCall?.call(type);
    if (type == PurchaseType.fail || type == PurchaseType.serevers) {
      _purchaseCall = null;
    }
  }
}
