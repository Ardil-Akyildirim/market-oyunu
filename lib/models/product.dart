enum ProductCategory {
  farm,      // Tarla & Bahçe
  dairy,     // Süt & Mandıra
  bakery,    // Fırın & Unlu Mamul
  grocery,   // Temel Bakkaliye
  butcher,   // Kasap & Şarküteri
  gourmet,   // Gurme & İthal
}

class Product {
  final String id;
  final String name;
  final String emoji;
  final ProductCategory category;
  final String description;
  
  int stock;
  int maxStock;
  double buyPrice;       // Tedarik maliyeti
  double sellPrice;      // Satış fiyatı
  int level;             // Ürün kalite seviyesi
  bool isUnlocked;
  double unlockCost;
  int unlockLevel;       // Gerekli market seviyesi

  Product({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.description,
    required this.stock,
    required this.maxStock,
    required this.buyPrice,
    required this.sellPrice,
    this.level = 1,
    this.isUnlocked = false,
    required this.unlockCost,
    this.unlockLevel = 1,
  });

  double get profit => sellPrice - buyPrice;

  double get upgradeCost => (buyPrice * 12) * (level * 1.5);

  void upgrade() {
    level++;
    maxStock = (maxStock * 1.35).round();
    sellPrice = double.parse((sellPrice * 1.25).toStringAsFixed(2));
    buyPrice = double.parse((buyPrice * 1.15).toStringAsFixed(2));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stock': stock,
    'maxStock': maxStock,
    'buyPrice': buyPrice,
    'sellPrice': sellPrice,
    'level': level,
    'isUnlocked': isUnlocked,
  };

  void loadJson(Map<String, dynamic> json) {
    stock = json['stock'] ?? stock;
    maxStock = json['maxStock'] ?? maxStock;
    buyPrice = (json['buyPrice'] as num?)?.toDouble() ?? buyPrice;
    sellPrice = (json['sellPrice'] as num?)?.toDouble() ?? sellPrice;
    level = json['level'] ?? level;
    isUnlocked = json['isUnlocked'] ?? isUnlocked;
  }
}
