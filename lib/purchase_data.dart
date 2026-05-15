import 'package:in_app_purchase/in_app_purchase.dart';

class PurchaseData {
  final String id;
  final String name;
  final String code;
  final bool recommend;
  final bool selected;

  ProductDetails? details;

  PurchaseData({
    required this.id,
    required this.name,
    required this.code,
    required this.recommend,
    required this.selected,
  });

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
      recommend: json['recommend'] ?? false,
      selected: json['selected'] ?? false,
    );
  }
}
