enum StaffType {
  cashier,       // Otomatik satış yapar
  shelfStocker,  // Stokları otomatik doldurur
  logistics,     // Tedarikçilerden otomatik sipariş çeker
  marketer,      // Müşteri sayısını artırır
  manager,       // Genel ciroyu katlar
}

class Staff {
  final String id;
  final String name;
  final String roleName;
  final String avatar;
  final StaffType type;
  final String description;
  
  bool isHired;
  double hireCost;
  double salaryPerMinute;
  int level;
  double efficiency; // Örneğin kasiyer için saniyede kaç müşteri, reyoncu için dolum hızı

  Staff({
    required this.id,
    required this.name,
    required this.roleName,
    required this.avatar,
    required this.type,
    required this.description,
    this.isHired = false,
    required this.hireCost,
    required this.salaryPerMinute,
    this.level = 1,
    this.efficiency = 1.0,
  });

  double get upgradeCost => hireCost * (level * 1.6);

  void upgrade() {
    level++;
    efficiency = double.parse((efficiency * 1.3).toStringAsFixed(2));
    salaryPerMinute = double.parse((salaryPerMinute * 1.2).toStringAsFixed(2));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'isHired': isHired,
    'level': level,
    'efficiency': efficiency,
  };

  void loadJson(Map<String, dynamic> json) {
    isHired = json['isHired'] ?? isHired;
    level = json['level'] ?? level;
    efficiency = (json['efficiency'] as num?)?.toDouble() ?? efficiency;
  }
}
