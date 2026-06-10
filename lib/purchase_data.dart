import 'package:in_app_purchase/in_app_purchase.dart';

class PurchaseConfig {
  final String hotId;
  final String selectedId;
  final List<PurchaseData> list;

  PurchaseConfig({
    required this.hotId,
    required this.selectedId,
    required this.list,
  });

  factory PurchaseConfig.fromJson(Map<String, dynamic> json) {
    return PurchaseConfig(
      hotId: json['hot_id'] ?? '',
      selectedId: json['selected_id'] ?? '',
      list: List<PurchaseData>.from(
        (json['list'] ?? []).map((x) => PurchaseData.fromJson(x)),
      ),
    );
  }
}

class PurchaseData {
  final String id;
  final String name;
  final String code;

  ProductDetails? details;

  PurchaseData({required this.id, required this.name, required this.code});

  String get orderPrice {
    if (details == null) return '--';
    final symbol = details?.currencySymbol ?? '';
    final price = details?.price ?? '';
    return '$symbol${price.split(symbol).last}';
  }

  factory PurchaseData.fromJson(Map<String, dynamic> json) {
    return PurchaseData(
      id: json['id'] ?? "",
      name: json['name'] ?? "",
      code: json['code'] ?? "",
    );
  }
}
