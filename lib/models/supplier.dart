class Supplier {
  final String id;
  final String name;
  final String title;
  final String avatar;
  final String description;
  final List<String> supportedProductIds;
  
  bool isContracted;
  double contractCost;
  int level;
  double discountRate;      // % indirim (0.05 = %5)
  int deliveryTimeSeconds;  // Teslimat süresi (sn)
  bool isDelivering;
  int deliveryRemainingSeconds;
  int lastDeliveredAmount;

  Supplier({
    required this.id,
    required this.name,
    required this.title,
    required this.avatar,
    required this.description,
    required this.supportedProductIds,
    this.isContracted = false,
    required this.contractCost,
    this.level = 1,
    this.discountRate = 0.10,
    this.deliveryTimeSeconds = 10,
    this.isDelivering = false,
    this.deliveryRemainingSeconds = 0,
    this.lastDeliveredAmount = 0,
  });

  double get upgradeCost => contractCost * (level * 1.8);

  void upgrade() {
    level++;
    discountRate = double.parse((discountRate + 0.05).toStringAsFixed(2));
    if (deliveryTimeSeconds > 3) {
      deliveryTimeSeconds = (deliveryTimeSeconds * 0.85).round().clamp(3, 120);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'isContracted': isContracted,
    'level': level,
    'discountRate': discountRate,
    'deliveryTimeSeconds': deliveryTimeSeconds,
  };

  void loadJson(Map<String, dynamic> json) {
    isContracted = json['isContracted'] ?? isContracted;
    level = json['level'] ?? level;
    discountRate = (json['discountRate'] as num?)?.toDouble() ?? discountRate;
    deliveryTimeSeconds = json['deliveryTimeSeconds'] ?? deliveryTimeSeconds;
  }
}
