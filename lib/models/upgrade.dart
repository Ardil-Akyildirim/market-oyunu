class Upgrade {
  final String id;
  final String title;
  final String description;
  final String icon;
  final double cost;
  final double multiplier; // Gelir veya müşteri çarpanı
  bool isPurchased;
  final int minMarketLevel;

  Upgrade({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.cost,
    required this.multiplier,
    this.isPurchased = false,
    this.minMarketLevel = 1,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'isPurchased': isPurchased,
  };

  void loadJson(Map<String, dynamic> json) {
    isPurchased = json['isPurchased'] ?? isPurchased;
  }
}
