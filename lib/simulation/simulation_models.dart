import 'package:material_ui/material_ui.dart';

// Ürün Türleri (Başlangıçta: Süt, Un, Yumurta -> Kademeli: Domates, Biber, Peynir...)
enum SimProductType {
  milk,      // Taze Süt (Başlangıçta Açık - Ahırdan)
  flour,     // Doğal Un (Başlangıçta Açık - Tarladan)
  egg,       // Köy Yumurtası (Başlangıçta Açık - Tavuk Çiftliğinden)
  tomato,    // Tarla Domatesi (Kademe 2 - Sonradan Açılır)
  pepper,    // Köy Biberi (Kademe 3 - Sonradan Açılır)
  cheese,    // Tulum Peyniri (Kademe 4 - Sonradan Açılır)
  apple,     // Amasya Elması (Kademe 5 - Sonradan Açılır)
  bread,     // Köy Ekmeği (Kademe 6 - Sonradan Açılır)
}

class SimProductDef {
  final SimProductType type;
  final String name;
  final String emoji;
  final Color primaryColor;
  final Color secondaryColor;
  final double orderCostPerItem;
  final double retailPrice;
  final int boxSize;

  const SimProductDef({
    required this.type,
    required this.name,
    required this.emoji,
    required this.primaryColor,
    required this.secondaryColor,
    required this.orderCostPerItem,
    required this.retailPrice,
    required this.boxSize,
  });

  double get boxCost => orderCostPerItem * boxSize;
  double get profitPerItem => retailPrice - orderCostPerItem;
}

final Map<SimProductType, SimProductDef> productCatalog = {
  SimProductType.milk: const SimProductDef(
    type: SimProductType.milk,
    name: 'Taze Köy Sütü',
    emoji: '🥛',
    primaryColor: Color(0xFF0284C7),
    secondaryColor: Color(0xFFE0F2FE),
    orderCostPerItem: 10.0,
    retailPrice: 24.0,
    boxSize: 8,
  ),
  SimProductType.flour: const SimProductDef(
    type: SimProductType.flour,
    name: 'Doğal Buğday Unu',
    emoji: '🌾',
    primaryColor: Color(0xFFD97706),
    secondaryColor: Color(0xFFFEF3C7),
    orderCostPerItem: 8.0,
    retailPrice: 20.0,
    boxSize: 10,
  ),
  SimProductType.egg: const SimProductDef(
    type: SimProductType.egg,
    name: 'Köy Yumurtası',
    emoji: '🥚',
    primaryColor: Color(0xFFF59E0B),
    secondaryColor: Color(0xFFFEF3C7),
    orderCostPerItem: 4.0,
    retailPrice: 10.0,
    boxSize: 12,
  ),
  SimProductType.tomato: const SimProductDef(
    type: SimProductType.tomato,
    name: 'Tarla Domatesi',
    emoji: '🍅',
    primaryColor: Color(0xFFEF4444),
    secondaryColor: Color(0xFFFEE2E2),
    orderCostPerItem: 12.0,
    retailPrice: 30.0,
    boxSize: 10,
  ),
  SimProductType.pepper: const SimProductDef(
    type: SimProductType.pepper,
    name: 'Taze Köy Biberi',
    emoji: '🫑',
    primaryColor: Color(0xFF16A34A),
    secondaryColor: Color(0xFFDCFCE7),
    orderCostPerItem: 11.0,
    retailPrice: 28.0,
    boxSize: 10,
  ),
  SimProductType.cheese: const SimProductDef(
    type: SimProductType.cheese,
    name: 'Tulum Peyniri',
    emoji: '🧀',
    primaryColor: Color(0xFFEAB308),
    secondaryColor: Color(0xFFFEF9C3),
    orderCostPerItem: 35.0,
    retailPrice: 80.0,
    boxSize: 6,
  ),
  SimProductType.apple: const SimProductDef(
    type: SimProductType.apple,
    name: 'Amasya Elması',
    emoji: '🍎',
    primaryColor: Color(0xFFDC2626),
    secondaryColor: Color(0xFFBBF7D0),
    orderCostPerItem: 14.0,
    retailPrice: 32.0,
    boxSize: 10,
  ),
  SimProductType.bread: const SimProductDef(
    type: SimProductType.bread,
    name: 'Taş Fırın Ekmeği',
    emoji: '🥖',
    primaryColor: Color(0xFFB45309),
    secondaryColor: Color(0xFFFED7AA),
    orderCostPerItem: 8.0,
    retailPrice: 18.0,
    boxSize: 8,
  ),
};

// Çiftlik Üretim Alanı Türleri (Arkada: Ahır, Tarla, Tavuk Çiftliği)
enum FarmZoneType {
  barn,   // İnek Ahırı (Süt Kovası ile içeri girip ineklerden süt sağılır)
  field,  // Bereketli Tarla (Tırpan ile içeri girip buğday/mahsul biçilir)
  coop,   // Tavuk Çiftliği (Yumurta Kovası ile içeri girip folluklardan yumurta toplanır)
}

// Çiftlik Ekipmanları (Ahır için Süt Kovası, Tarla için Tırpan, Kümes için Yumurta Kovası)
enum FarmToolType {
  milkBucket, // 🪣 Süt Kovası
  scythe,     // 🌾 Hasat Tırpanı
  eggBucket,  // 🪣 Yumurta Kovası
}

extension FarmToolTypeExt on FarmToolType {
  String get name {
    switch (this) {
      case FarmToolType.milkBucket:
        return 'Süt Kovası';
      case FarmToolType.scythe:
        return 'Hasat Tırpanı';
      case FarmToolType.eggBucket:
        return 'Yumurta Kovası';
    }
  }

  String get emoji {
    switch (this) {
      case FarmToolType.milkBucket:
        return '🪣';
      case FarmToolType.scythe:
        return '🌾';
      case FarmToolType.eggBucket:
        return '🪣';
    }
  }

  String get actionVerb {
    switch (this) {
      case FarmToolType.milkBucket:
        return 'İnekten Süt Sağılıyor';
      case FarmToolType.scythe:
        return 'Tırpanla Biçiliyor';
      case FarmToolType.eggBucket:
        return 'Kovaya Yumurta Toplanıyor';
    }
  }
}

// Çiftlik İçindeki Tekil Hasat / Sağım / Toplama Noktası (İnek, Buğday Öbeği, Folluk)
class FarmHarvestSpot {
  final String id;
  final int index;
  final double x;
  final double y;
  SimProductType productType;
  bool isReady;
  double regrowTimer;
  final double regrowDuration;
  double harvestProgress; // 0.0 -> 1.0 (tırpan sallarken / süt sağarken / yumurta toplarken)
  double justProducedTimer; // 1.0 -> 0.0 (yumurtlama / süt dolumu / başaklanma anı animasyonu)

  FarmHarvestSpot({
    required this.id,
    required this.index,
    required this.x,
    required this.y,
    required this.productType,
    this.isReady = true,
    this.regrowTimer = 0.0,
    this.regrowDuration = 6.5,
    this.harvestProgress = 0.0,
    this.justProducedTimer = 0.0,
  });
}

class FarmProducer {
  final String id;
  final String name;
  final String emoji;
  final FarmZoneType zoneType;
  final Rect rect;
  final Rect solidBuildingRect;
  final double gateMinX;
  final double gateMaxX;
  final Offset toolStandPos;
  final FarmToolType requiredTool;
  final SimProductType primaryProduct;
  final List<FarmHarvestSpot> spots;
  int readyBoxes;
  final int maxBoxes;
  double productionTimer;
  final double productionDuration;
  bool isUnlocked;
  bool isHovered;
  bool isToolStandHovered;

  FarmProducer({
    required this.id,
    required this.name,
    required this.emoji,
    required this.zoneType,
    required this.rect,
    required this.solidBuildingRect,
    required this.gateMinX,
    required this.gateMaxX,
    required this.toolStandPos,
    required this.requiredTool,
    required this.primaryProduct,
    required this.spots,
    this.readyBoxes = 2,
    this.maxBoxes = 4,
    this.productionTimer = 0.0,
    this.productionDuration = 7.0,
    this.isUnlocked = true,
    this.isHovered = false,
    this.isToolStandHovered = false,
  });

  int get readySpotCount => spots.where((s) => s.isReady).length;
  Offset get gateCenter => Offset((gateMinX + gateMaxX) / 2, rect.top);
}

// Parçacık Efekti (Uçuşan paralar, duman, pırıltı)
class WorldParticle {
  double x;
  double y;
  double vx;
  double vy;
  double life;     // 1.0 -> 0.0
  final double maxLife;
  final String text;
  final Color color;
  final double size;

  WorldParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.text,
    required this.color,
    this.size = 14,
    this.maxLife = 1.0,
  }) : life = maxLife;
}

// Yerdeki Koli (3D Derinlikli Kutu)
class DeliveryBox {
  final String id;
  final SimProductType productType;
  int currentCount;
  final int maxCount;
  double x;
  double y;
  bool isHovered;

  DeliveryBox({
    required this.id,
    required this.productType,
    required this.currentCount,
    required this.maxCount,
    required this.x,
    required this.y,
    this.isHovered = false,
  });

  bool get isEmpty => currentCount <= 0;
  Rect get bounds => Rect.fromCenter(center: Offset(x, y), width: 44, height: 38);
}

// Reyon / Raf (3D İzometrik Derinlikli, Açılır Kapaklı & Kademeli Kilit Açma Destekli)
class StoreShelf {
  final String id;
  final String name;
  final SimProductType assignedProduct;
  final Rect rect; // Rafların konumu
  int currentStock;
  final int maxCapacity;
  bool isUnlocked;
  final double unlockCost;
  bool isHovered;
  double doorOpenProgress; // 0.0 (kapalı) -> 1.0 (reyon kapısı / dolap kapağı açık)
  double lastPlacedBounceTimer; // 1.0 -> 0.0 (yeni dizilen ürünün zıplama efekti)
  double stockStepTimer; // Ürünleri rafa tekli tekli dizme zamanlayıcısı

  StoreShelf({
    required this.id,
    required this.name,
    required this.assignedProduct,
    required this.rect,
    this.currentStock = 0,
    this.maxCapacity = 16,
    this.isUnlocked = true,
    this.unlockCost = 0.0,
    this.isHovered = false,
    this.doorOpenProgress = 0.0,
    this.lastPlacedBounceTimer = 0.0,
    this.stockStepTimer = 0.0,
  });
}

// Rafa Tekli Tekli Dizilen veya Raftan Alınan Uçan Ürün Animasyonu
class ShelfFlyingItem {
  final SimProductType productType;
  final Offset startPos;
  final Offset endPos;
  double progress; // 0.0 -> 1.0
  final double duration;
  final bool isToShelf;

  ShelfFlyingItem({
    required this.productType,
    required this.startPos,
    required this.endPos,
    this.progress = 0.0,
    this.duration = 0.25,
    this.isToShelf = true,
  });
}

// Oyuncunun Taşıdığı Eşya (Koli, Çiftlikten Toplanan Kova/Sepet, Dolaptan Tek Tek Alınan Ürün veya Paketlenmiş Kurye Sipariş Paketi)
class CarriedBox {
  final SimProductType productType;
  int currentCount;
  final int maxCount;
  final bool isFromFarm;
  final bool isCourierPackage;
  final bool isPickedFromShelf;

  CarriedBox({
    required this.productType,
    required this.currentCount,
    required this.maxCount,
    this.isFromFarm = false,
    this.isCourierPackage = false,
    this.isPickedFromShelf = false,
  });

  String get containerName {
    if (isCourierPackage) {
      return 'Kurye Sipariş Paketi (${productCatalog[productType]!.name})';
    }
    if (isPickedFromShelf) {
      return 'Elde ${productCatalog[productType]!.name}';
    }
    if (!isFromFarm) return 'Ürün Kolisi';
    switch (productType) {
      case SimProductType.milk:
        return 'Sağılmış Taze Süt';
      case SimProductType.egg:
        return 'Toplanmış Köy Yumurtası';
      case SimProductType.flour:
        return 'Biçilmiş Buğday Demeti';
      case SimProductType.cheese:
        return 'Taze Tulum Peyniri';
      default:
        return 'Taze Tarla Mahsulü';
    }
  }

  String get containerEmoji {
    if (isCourierPackage) return '📦';
    if (isPickedFromShelf) return productCatalog[productType]!.emoji;
    if (!isFromFarm) return '📦';
    switch (productType) {
      case SimProductType.milk:
        return '🥛';
      case SimProductType.egg:
        return '🥚';
      case SimProductType.flour:
        return '🌾';
      case SimProductType.cheese:
        return '🧀';
      default:
        return '🧺';
    }
  }
}

// Müşteri Karakter Arketipleri (Farklı Görünüm, Hız ve Alışveriş Alışkanlıkları)
enum CustomerArchetype {
  regular, // 🛒 Mahalleli Müşteri
  grandma, // 👵 Tonton Nine / Dede (Bastonlu, yavaş yürür, un/süt/ekmek sever, +%20 bahşiş)
  athlete, // 🏃 Sporcu Genç (Kafa bantlı, çok hızlı yürür, süt/yumurta/elma alır)
  chef,    // 👨‍🍳 Gurme Aşçı / Şef (Beyaz aşçı şapkalı, bol malzeme alır, +%45 bahşiş)
  student, // 🎒 Üniversiteli Öğrenci (Sırt çantalı ve şapkalı, hızlı yürür)
  family,  // 👩‍👧 Kalabalık Aile (Çoklu alışveriş yapar, +%30 bonus)
  vip,     // 👑 VIP İş İnsanı / Gurme (Altın haleli, güneş gözlüklü, 2.2x ödeme)
}

// Müşteri State
enum CustomerState {
  walkingToEntrance,
  shopping,
  goingToCheckout,
  waitingAtCheckout,
  leavingHappy,
  leavingSad,
}

class SimCustomer {
  final String id;
  final String name;
  final String avatar;
  final CustomerArchetype archetype;
  final bool isVip;
  double x;
  double y;
  double walkAngle;
  CustomerState state;
  final List<SimProductType> shoppingList;
  final List<SimProductType> basket;
  int currentShoppingIndex;
  int checkoutIndex;
  int packedCount; // Kasada poşete paketlenen ürün sayısı
  SimProductType? baggingProduct; // Şu an poşetin içine doğru uçan ürün (animasyon için)
  double baggingAnimTimer; // 0.0 -> 1.0 poşete girme animasyonu ilerlemesi
  double waitTimer;
  double shelfGrabTimer; // Reyon kapısı açılırken müşterinin ürünü raftan alma animasyon süresi

  SimCustomer({
    required this.id,
    required this.name,
    required this.avatar,
    required this.x,
    required this.y,
    required this.shoppingList,
    this.archetype = CustomerArchetype.regular,
    this.isVip = false,
    this.checkoutIndex = 0,
    this.packedCount = 0,
    this.baggingProduct,
    this.baggingAnimTimer = 0.0,
    this.shelfGrabTimer = 0.0,
  })  : state = CustomerState.walkingToEntrance,
        basket = [],
        currentShoppingIndex = 0,
        waitTimer = 0.0,
        walkAngle = 0.0;

  int get unpackedCount => (basket.length - packedCount).clamp(0, basket.length);
  bool get isFullyPacked => basket.isNotEmpty && packedCount >= basket.length;

  double get speedMultiplier {
    switch (archetype) {
      case CustomerArchetype.athlete:
        return 1.38;
      case CustomerArchetype.student:
        return 1.18;
      case CustomerArchetype.grandma:
        return 0.78;
      case CustomerArchetype.chef:
        return 1.08;
      default:
        return 1.0;
    }
  }

  double get bonusMultiplier {
    switch (archetype) {
      case CustomerArchetype.vip:
        return 2.2;
      case CustomerArchetype.chef:
        return 1.45;
      case CustomerArchetype.family:
        return 1.30;
      case CustomerArchetype.grandma:
        return 1.20;
      case CustomerArchetype.athlete:
        return 1.15;
      default:
        return 1.0;
    }
  }

  String get archetypeBadge {
    switch (archetype) {
      case CustomerArchetype.grandma:
        return '👵 Tonton';
      case CustomerArchetype.athlete:
        return '🏃 Sporcu';
      case CustomerArchetype.chef:
        return '👨‍🍳 Aşçı Şef';
      case CustomerArchetype.student:
        return '🎒 Öğrenci';
      case CustomerArchetype.family:
        return '👩‍👧 Aile';
      case CustomerArchetype.vip:
        return '👑 VIP';
      case CustomerArchetype.regular:
        return '🛒 Müşteri';
    }
  }
}

// Kurye Motoru Durumu
enum CourierState {
  away,
  arriving,
  waitingForOrder,
  departing,
}

// Acil Online Paket Siparişi (Getir / Hızlı Kurye Görevi)
class CourierOrder {
  final String id;
  final String customerName;
  final SimProductType productType;
  final int requiredQty;
  int deliveredQty;
  final double rewardAmount;
  double remainingTime;
  final double totalTime;

  CourierOrder({
    required this.id,
    required this.customerName,
    required this.productType,
    required this.requiredQty,
    this.deliveredQty = 0,
    required this.rewardAmount,
    required this.remainingTime,
    required this.totalTime,
  });

  bool get isCompleted => deliveredQty >= requiredQty;
  int get remainingQty => (requiredQty - deliveredQty).clamp(0, requiredQty);
  double get progress => (deliveredQty / requiredQty).clamp(0.0, 1.0);
  double get timeRatio => (remainingTime / totalTime).clamp(0.0, 1.0);
}

// Otomatik Reyon & Çiftlik Görevlisi (Stokçu Ali)
class RestockerWorker {
  double x;
  double y;
  CarriedBox? carriedBox;
  FarmToolType? equippedTool;
  double actionAnimTimer;
  String statusText;
  double walkTimer;

  RestockerWorker({
    this.x = 1140,
    this.y = 640,
    this.carriedBox,
    this.equippedTool,
    this.actionAnimTimer = 0.0,
    this.statusText = '📦 Rafları Kontrol Ediyor',
    this.walkTimer = 0.0,
  });
}
