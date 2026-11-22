import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'simulation_models.dart';

class SimulationEngine with ChangeNotifier {
  // Para & Market Durumu
  double cash = 400.0;
  double totalRevenue = 0.0;
  int day = 1;
  int storeLevel = 1;
  bool isStoreOpen = true;

  // Kasiyer ve Stokçu başlangıçta kapalıdır; market seviyesi arttıkça açılır ve işe alınır!
  bool hasAutoCashier = false;
  bool hasRestocker = false;
  bool isRestockerHired = false;

  // DEVAASA HARİTA BOYUTLARI (2000 x 1880 - Geniş Cadde + Büyük Market + 2 Sıralı Arka Bahçe Çiftlik Vadisi)
  final double worldWidth = 2000;
  final double worldHeight = 1880;

  // Kamera Takip & Yakınlaştırma (WASD ile hareket ettikçe oyuncuyu yumuşakça takip eder)
  double cameraX = 1000;
  double cameraY = 480;
  double cameraZoom = 1.0;
  double worldTime = 0.0;

  // Oyuncu (Geniş marketin orta koridorunda doğar)
  double playerX = 1000;
  double playerY = 480;
  double playerSpeed = 215; // top walking speed (smooth acceleration below)
  Offset? _cachedWp; // tap-to-walk route point, refreshed a few times per second
  double _wpTimer = 0;
  double? _wpTx, _wpTy;
  double velX = 0;
  double velY = 0;
  int playerFacing = 0; // 0 = down, 1 = left, 2 = right, 3 = up
  double _stepDist = 0;
  double get playerSpeedNow => sqrt(velX * velX + velY * velY);

  /// Sound effect hook: the screen plugs the audio service in here.
  void Function(String name)? onSfx;
  void _sfx(String name) => onSfx?.call(name);
  void playSfx(String name) => onSfx?.call(name);
  double moveDirX = 0;
  double moveDirY = 0;
  double playerAngle = 0;
  double walkAnimTime = 0;
  CarriedBox? carriedBox;

  // Oyuncunun Elindeki Çiftlik Aleti (🧺 Süt Kovası, 🌾 Hasat Tırpanı, 🧺 Yumurta Kovası)
  // Sadece çiftliğin içindeyken taşınır; çiftlikten çıkınca otomatik bırakılır!
  FarmToolType? playerTool;
  double playerActionAnimTimer = 0.0;
  FarmHarvestSpot? activeHarvestSpot;
  String? pendingAutoFarmId;
  bool _pendingToolOnly = false;

  // 🧀 3D PEYNİR YAPMA MAKİNESİ (Tulum Peyniri reyonu açıldığında aktif olur; Sütü Peynire dönüştürür)
  final Rect cheeseMachineRect = const Rect.fromLTWH(185, 1040, 195, 92);
  int cheeseMachineMilkInput = 0;
  int cheeseMachineReadyBoxes = 0;
  final int cheeseMachineMaxBoxes = 3;
  double cheeseMachineTimer = 0.0;
  final double cheeseMachineDuration = 4.5;
  bool isCheeseMachineHovered = false;
  bool pendingDeliverMilkToCheese = false;

  // Mouse ile Hedefleme (Click-To-Move)
  double? targetMoveX;
  double? targetMoveY;
  double mouseWorldX = 0;
  double mouseWorldY = 0;

  // Sabit Nesneler ve Bölgeler (Sol Üst Kasa Alanı Ferah Bırakıldı; Seviye Atladıkça 3 Kasa Açılır!)
  final List<Rect> checkoutCounters = const [
    Rect.fromLTWH(520, 290, 180, 110), // Register 1 (open from the start)
    Rect.fromLTWH(330, 290, 180, 110), // Register 2 (store level 2)
    Rect.fromLTWH(140, 290, 180, 110), // Register 3 (store level 3)
  ];
  int get unlockedCheckoutCount => storeLevel.clamp(1, 3);
  List<Rect> get unlockedCheckouts => checkoutCounters.take(unlockedCheckoutCount).toList();
  Rect get checkoutCounter => checkoutCounters.first;

  /// Oyuncu açık bir kasa tezgahının arkasındaki kasiyer alanına girdiğinde ilgili kasa indeksini döndürür.
  int? getCheckoutTriggerZoneIndex() {
    final pos = Offset(playerX, playerY);
    for (int i = 0; i < unlockedCheckoutCount; i++) {
      final r = checkoutCounters[i];
      final triggerRect = Rect.fromLTRB(r.left - 18, 230, r.right + 18, r.top + 10);
      if (triggerRect.contains(pos)) {
        return i;
      }
    }
    return null;
  }

  final Rect computerDesk = const Rect.fromLTWH(1170, 285, 150, 105);   // Yönetim & Sipariş Ofis Masası
  final Rect trashCan = const Rect.fromLTWH(1400, 890, 64, 64);         // Geri Dönüşüm & Çöp Kutusu
  final Rect courierStation = const Rect.fromLTWH(1285, 148, 215, 74);  // 🛵 3D Hızlı Kurye & Online Sipariş Durağı
  final Rect courierPackingDesk = const Rect.fromLTWH(1335, 305, 145, 82); // 📦 3D Kurye Sipariş Paketleme İstasyonu (Kasadan Ayrı!)

  // 🛵 Motorlu Kurye & Acil Online Sipariş Sistemi
  CourierState courierState = CourierState.arriving;
  double courierX = 2120;
  final double courierParkX = 1365;
  double courierCooldown = 2.0;
  CourierOrder? activeCourierOrder;
  int completedCourierOrders = 0;
  bool isCourierHovered = false;

  // 📦 Kurye Paketleme İstasyonu Durumu (Ürün kuryeye verilmeden önce burada paketlenir; kasada yapılmaz!)
  bool isCourierPackingDeskHovered = false;
  int courierStagedCount = 0;
  SimProductType? courierStagedProduct;
  double courierPackingProgress = 0.0;
  bool pendingPackForCourier = false;
  bool pendingDeliverToCourier = false;
  bool shouldOpenCourierPackingDialog = false;
  bool _warnedExcessAtDesk = false;
  String? pendingTakeOneShelfId;

  // 🥚✨ Tek Tek Rafa Dizme Uçuş Efektleri & Kasa Barkod Okutma Animasyonu
  final List<ShelfFlyingItem> flyingShelfItems = [];
  int? activePlayerCheckoutIndex;
  double playerScanAnimTimer = 0.0;
  SimProductType? currentScanningProduct;

  // 👷 3D Otomatik Reyon & Çiftlik Görevlisi (Stokçu Ali - Seviye 3'te açılır)
  final RestockerWorker restocker = RestockerWorker();

  // Raflar
  List<StoreShelf> shelves = [];

  // Arka Bahçe Çiftlik Üretim Alanları (Ahır, Tarla, Tavuk Çiftliği ve Meyve/Sebze Tarlaları)
  List<FarmProducer> farmProducers = [];

  // Yerdeki Teslimat Kolileri
  List<DeliveryBox> deliveryBoxes = [];

  // Müşteriler
  List<SimCustomer> customers = [];
  double customerSpawnTimer = 9.0;

  // Kamyon Animasyonu
  bool isTruckArriving = false;
  double truckX = -260;
  double truckTargetX = 1000; // stops at the back door
  List<SimProductType> incomingShipment = [];

  // Parçacıklar
  final List<WorldParticle> particles = [];

  // Anlık Etkileşim Durumu
  String? activeInteractionText;
  VoidCallback? activeInteractionAction;

  SimulationEngine() {
    _initStore();
  }

  // The farm and the cheese machine were scrapped: everything is ordered from the computer.
  bool get isCheeseUnlocked => false;

  // The store grows with the store level. Outside this range the floor is roped off.
  double get storeMinX => storeLevel <= 1 ? 500.0 : (storeLevel == 2 ? 300.0 : 90.0);
  double get storeMaxX => storeLevel <= 1 ? 1500.0 : (storeLevel == 2 ? 1700.0 : worldWidth - 90.0);
  List<String> dawnUnlocks = [];

  double get nextLevelUpgradeCost {
    if (storeLevel == 1) return 500.0;
    if (storeLevel == 2) return 900.0;
    return 1500.0;
  }

  // Kamera Ölçek ve Koordinat Hesaplaması (%50'ye kadar küçültme destekli!)
  double getEffectiveScale(Size screenSize) {
    final baseScaleX = screenSize.width / 1020.0;
    final baseScaleY = screenSize.height / 640.0;
    return max(baseScaleX, baseScaleY) * cameraZoom;
  }

  Offset getCameraTopLeft(Size screenSize) {
    final scale = getEffectiveScale(screenSize);
    final visibleW = screenSize.width / scale;
    final visibleH = screenSize.height / scale;

    final double camX;
    if (visibleW >= worldWidth) {
      camX = (worldWidth - visibleW) / 2.0;
    } else {
      camX = (cameraX - visibleW / 2).clamp(0.0, worldWidth - visibleW);
    }

    final double camY;
    if (visibleH >= worldHeight) {
      camY = (worldHeight - visibleH) / 2.0;
    } else {
      camY = (cameraY - visibleH / 2).clamp(0.0, worldHeight - visibleH);
    }

    return Offset(camX, camY);
  }

  void adjustZoom(double delta) {
    cameraZoom = (cameraZoom + delta).clamp(0.50, 1.85);
    notifyListeners();
  }

  void _initStore() {
    shelves = [
      // Store layout: the starting store is small (x 500..1500). Buying store levels
      // opens the side strips. One product is available at the start; the others
      // open one by one as the days pass (see unlockDay / zoneLevel).
      StoreShelf(
        id: 'shelf_milk',
        name: 'Fresh Milk Cooler',
        assignedProduct: SimProductType.milk,
        rect: const Rect.fromLTWH(540, 540, 145, 175),
        currentStock: 12,
        maxCapacity: 16,
        isUnlocked: true,
        unlockCost: 0,
        unlockDay: 1,
        zoneLevel: 1,
      ),
      StoreShelf(
        id: 'shelf_flour',
        name: 'Natural Flour Shelf',
        assignedProduct: SimProductType.flour,
        rect: const Rect.fromLTWH(1150, 560, 210, 120),
        currentStock: 12,
        maxCapacity: 16,
        isUnlocked: true,
        unlockCost: 0,
        unlockDay: 1,
        zoneLevel: 1,
      ),
      StoreShelf(
        id: 'shelf_egg',
        name: 'Village Eggs Shelf',
        assignedProduct: SimProductType.egg,
        rect: const Rect.fromLTWH(540, 780, 155, 155),
        currentStock: 12,
        maxCapacity: 16,
        isUnlocked: true,
        unlockCost: 0,
        unlockDay: 1,
        zoneLevel: 1,
      ),
      // Seviye arttıkça açılabilen 3 ek reyon (açılana kadar sadece adları görünür!)
      StoreShelf(
        id: 'shelf_tomato',
        name: 'Tomato Stand',
        assignedProduct: SimProductType.tomato,
        rect: const Rect.fromLTWH(1150, 770, 210, 120),
        currentStock: 0,
        maxCapacity: 16,
        isUnlocked: false,
        unlockCost: 120,
        unlockDay: 1,
        zoneLevel: 2,
      ),
      StoreShelf(
        id: 'shelf_pepper',
        name: 'Pepper Stand',
        assignedProduct: SimProductType.pepper,
        rect: const Rect.fromLTWH(310, 560, 180, 125),
        currentStock: 0,
        maxCapacity: 16,
        isUnlocked: false,
        unlockCost: 160,
        unlockDay: 1,
        zoneLevel: 2,
      ),
      StoreShelf(
        id: 'shelf_apple',
        name: 'Apple Stand',
        assignedProduct: SimProductType.apple,
        rect: const Rect.fromLTWH(1510, 560, 180, 125),
        currentStock: 0,
        maxCapacity: 16,
        isUnlocked: false,
        unlockCost: 220,
        unlockDay: 1,
        zoneLevel: 3,
      ),
    ];

    // Arka Bahçe Çiftlikleri:
    // 1. Sıra (Başlangıçta Açık): Cow Farm (Milk Bucket), Flour Field (Hoe), Chicken Farm (Egg Bucket)
    // 2. Sıra (Seviye Artınca Açılan 3 Kilitli Tarla): Tomato Field, Pepper Field, Apple Field
    farmProducers = [
      FarmProducer(
        id: 'farm_barn',
        name: 'Cow Farm',
        emoji: '🐄',
        zoneType: FarmZoneType.barn,
        rect: const Rect.fromLTWH(140, 1160, 440, 290),
        solidBuildingRect: Rect.zero,
        gateMinX: 310,
        gateMaxX: 420,
        toolStandPos: const Offset(255, 1126),
        requiredTool: FarmToolType.milkBucket,
        primaryProduct: SimProductType.milk,
        isUnlocked: true,
        spots: [
          FarmHarvestSpot(id: 'cow_0', index: 0, x: 215, y: 1248, productType: SimProductType.milk, regrowDuration: 5.2),
          FarmHarvestSpot(id: 'cow_1', index: 1, x: 465, y: 1255, productType: SimProductType.milk, regrowDuration: 6.4),
          FarmHarvestSpot(id: 'cow_2', index: 2, x: 230, y: 1372, productType: SimProductType.milk, regrowDuration: 7.6),
          FarmHarvestSpot(id: 'cow_3', index: 3, x: 475, y: 1378, productType: SimProductType.milk, regrowDuration: 8.8),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 6.5,
      ),
      FarmProducer(
        id: 'farm_field',
        name: 'Flour Field',
        emoji: '🌾',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(780, 1160, 440, 290),
        solidBuildingRect: const Rect.fromLTWH(805, 1245, 88, 102),
        gateMinX: 995,
        gateMaxX: 1105,
        toolStandPos: const Offset(945, 1126),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.flour,
        isUnlocked: true,
        spots: [
          FarmHarvestSpot(id: 'crop_0', index: 0, x: 960, y: 1242, productType: SimProductType.flour, regrowDuration: 4.8),
          FarmHarvestSpot(id: 'crop_1', index: 1, x: 1062, y: 1248, productType: SimProductType.flour, regrowDuration: 5.7),
          FarmHarvestSpot(id: 'crop_2', index: 2, x: 1162, y: 1242, productType: SimProductType.flour, regrowDuration: 6.6),
          FarmHarvestSpot(id: 'crop_3', index: 3, x: 960, y: 1362, productType: SimProductType.flour, regrowDuration: 7.5),
          FarmHarvestSpot(id: 'crop_4', index: 4, x: 1062, y: 1368, productType: SimProductType.flour, regrowDuration: 8.4),
          FarmHarvestSpot(id: 'crop_5', index: 5, x: 1162, y: 1362, productType: SimProductType.flour, regrowDuration: 9.2),
        ],
        readyBoxes: 6,
        maxBoxes: 6,
        productionDuration: 6.0,
      ),
      FarmProducer(
        id: 'farm_coop',
        name: 'Chicken Farm',
        emoji: '🐔',
        zoneType: FarmZoneType.coop,
        rect: const Rect.fromLTWH(1420, 1160, 440, 290),
        solidBuildingRect: const Rect.fromLTWH(1700, 1205, 140, 205),
        gateMinX: 1500,
        gateMaxX: 1605,
        toolStandPos: const Offset(1455, 1126),
        requiredTool: FarmToolType.eggBucket,
        primaryProduct: SimProductType.egg,
        isUnlocked: true,
        spots: [
          FarmHarvestSpot(id: 'nest_0', index: 0, x: 1475, y: 1242, productType: SimProductType.egg, regrowDuration: 4.5),
          FarmHarvestSpot(id: 'nest_1', index: 1, x: 1615, y: 1255, productType: SimProductType.egg, regrowDuration: 5.8),
          FarmHarvestSpot(id: 'nest_2', index: 2, x: 1480, y: 1368, productType: SimProductType.egg, regrowDuration: 7.1),
          FarmHarvestSpot(id: 'nest_3', index: 3, x: 1620, y: 1380, productType: SimProductType.egg, regrowDuration: 8.4),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      // 2. Sıra: Seviye arttıkça açılan 3 kilitli tarla (Domates, Biber, Elma)
      FarmProducer(
        id: 'farm_tomato',
        name: 'Tomato Field',
        emoji: '🍅',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(140, 1555, 440, 265),
        solidBuildingRect: Rect.zero,
        gateMinX: 310,
        gateMaxX: 420,
        toolStandPos: const Offset(255, 1522),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.tomato,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'tom_0', index: 0, x: 245, y: 1640, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_1', index: 1, x: 455, y: 1640, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_2', index: 2, x: 245, y: 1745, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_3', index: 3, x: 455, y: 1745, productType: SimProductType.tomato, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      FarmProducer(
        id: 'farm_pepper',
        name: 'Pepper Field',
        emoji: '🌶️',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(780, 1555, 440, 265),
        solidBuildingRect: Rect.zero,
        gateMinX: 995,
        gateMaxX: 1105,
        toolStandPos: const Offset(945, 1522),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.pepper,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'pep_0', index: 0, x: 885, y: 1640, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_1', index: 1, x: 1095, y: 1640, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_2', index: 2, x: 885, y: 1745, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_3', index: 3, x: 1095, y: 1745, productType: SimProductType.pepper, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      FarmProducer(
        id: 'farm_apple',
        name: 'Apple Field',
        emoji: '🍎',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(1420, 1555, 440, 265),
        solidBuildingRect: Rect.zero,
        gateMinX: 1500,
        gateMaxX: 1605,
        toolStandPos: const Offset(1455, 1522),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.apple,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'app_0', index: 0, x: 1525, y: 1640, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_1', index: 1, x: 1735, y: 1640, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_2', index: 2, x: 1525, y: 1745, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_3', index: 3, x: 1735, y: 1745, productType: SimProductType.apple, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
    ];
  }

  StoreShelf? shelfForProduct(SimProductType t) {
    for (final s in shelves) {
      if (s.assignedProduct == t) return s;
    }
    return null;
  }

  FarmProducer? farmForProduct(SimProductType t) {
    for (final f in farmProducers) {
      if (f.primaryProduct == t) return f;
    }
    return null;
  }

  List<SimProductType> get unlockedProducts {
    return shelves.where((s) => s.isUnlocked).map((s) => s.assignedProduct).toList();
  }

  /// Opens every free shelf whose day/level has come; paid shelves wait for the player to unlock them.
  List<String> refreshShelfUnlocks() {
    final opened = <String>[];
    for (final s in shelves) {
      if (s.isUnlocked) continue;
      if (s.unlockCost <= 0 && day >= s.unlockDay && storeLevel >= s.zoneLevel) {
        if (unlockShelf(s)) {
          final def = productCatalog[s.assignedProduct]!;
          opened.add('${def.emoji} ${def.name}');
        }
      }
    }
    return opened;
  }

  /// Short text explaining why a shelf / field is still closed or how to unlock it.
  String shelfLockReason(StoreShelf s) {
    if (storeLevel < s.zoneLevel) return 'Level ${s.zoneLevel} Required';
    if (day < s.unlockDay) return 'Day ${s.unlockDay} Required';
    if (s.unlockCost > 0) return 'Click to Unlock (\$${s.unlockCost.toInt()})';
    return 'Click to Unlock';
  }

  bool tryUnlockShelfOrFarm(StoreShelf shelf, {Offset? feedbackPos}) {
    final pos = feedbackPos ?? shelf.rect.center;
    if (shelf.isUnlocked) return true;
    if (storeLevel < shelf.zoneLevel) {
      _sfx('error');
      spawnParticle(
        pos.dx,
        pos.dy - 14,
        '🔒 Level ${shelf.zoneLevel} Required! (Upgrade Store via Manager)',
        Colors.orangeAccent,
        size: 15,
      );
      return false;
    }
    if (cash < shelf.unlockCost) {
      _sfx('error');
      spawnParticle(
        pos.dx,
        pos.dy - 14,
        '⚠️ \$${shelf.unlockCost.toInt()} required to unlock!',
        Colors.redAccent,
        size: 15,
      );
      return false;
    }
    _sfx('cash');
    return unlockShelf(shelf);
  }

  bool unlockShelf(StoreShelf shelf) {
    if (shelf.isUnlocked || cash < shelf.unlockCost) return false;

    cash -= shelf.unlockCost;
    shelf.isUnlocked = true;
    final def = productCatalog[shelf.assignedProduct]!;
    shelf.currentStock = def.boxSize;

    // Oyuncu, stokçu veya müşteriler kilitli alanın tam üstündeyken raf açılırsa onları rafın önüne çıkar
    final shelfGuardRect = Rect.fromLTRB(
      shelf.rect.left - 24,
      shelf.rect.top - 48,
      shelf.rect.right + 34,
      shelf.rect.bottom + 22,
    );
    if (shelfGuardRect.contains(Offset(playerX, playerY))) {
      playerY = shelf.rect.bottom + 26;
    }
    if (shelfGuardRect.contains(Offset(restocker.x, restocker.y))) {
      restocker.y = shelf.rect.bottom + 26;
    }
    for (final c in customers) {
      if (shelfGuardRect.contains(Offset(c.x, c.y))) {
        c.y = shelf.rect.bottom + 28;
      }
    }

    spawnParticle(
      shelf.rect.center.dx,
      shelf.rect.top - 10,
      '🔓 ${def.emoji} ${shelf.name} Unlocked!',
      Colors.greenAccent,
      size: 18,
    );

    // İlgili meyve/sebze/ekmek tarlasını çiftlikte otomatik olarak aç!
    for (final farm in farmProducers) {
      if (farm.primaryProduct == shelf.assignedProduct && !farm.isUnlocked) {
        farm.isUnlocked = true;
        spawnParticle(
          shelf.rect.center.dx,
          shelf.rect.top - 34,
          '🌱 ${def.emoji} ${farm.name} Unlocked at the Farm!',
          Colors.amberAccent,
          size: 17,
        );
        spawnParticle(
          farm.rect.center.dx,
          farm.rect.top - 18,
          '🌱 ${def.emoji} ${farm.name} Unlocked!',
          Colors.greenAccent,
          size: 19,
        );
      }
    }

    if (shelf.assignedProduct == SimProductType.cheese) {
      cheeseMachineReadyBoxes = 1;
      spawnParticle(
        cheeseMachineRect.center.dx,
        cheeseMachineRect.top - 18,
        '🧀 3D Cheese Making Machine Installed!',
        Colors.amberAccent,
        size: 19,
      );
    }

    notifyListeners();
    return true;
  }

  void setTargetMove(double wx, double wy, {bool clearPendingFarm = true}) {
    if (clearPendingFarm) {
      pendingAutoFarmId = null;
      _pendingToolOnly = false;
      pendingDeliverMilkToCheese = false;
      pendingPackForCourier = false;
      pendingDeliverToCourier = false;
      pendingTakeOneShelfId = null;
    }
    targetMoveX = wx.clamp(90, worldWidth - 90);
    targetMoveY = wy.clamp(60, worldHeight - 60);
  }

  void setMousePosition(double wx, double wy) {
    mouseWorldX = wx;
    mouseWorldY = wy;

    final mousePos = Offset(wx, wy);
    for (var shelf in shelves) {
      shelf.isHovered = shelf.rect.inflate(10).contains(mousePos);
    }
    for (var farm in farmProducers) {
      farm.isHovered = farm.rect.inflate(12).contains(mousePos);
      if (!farm.isUnlocked) {
        farm.isToolStandHovered = false;
        continue;
      }
      farm.isToolStandHovered = (farm.toolStandPos - mousePos).distance < 42;
    }
    for (var box in deliveryBoxes) {
      box.isHovered = (Offset(box.x, box.y) - mousePos).distance < 34;
    }
    isCourierHovered = courierStation.inflate(16).contains(mousePos);
    isCourierPackingDeskHovered = courierPackingDesk.inflate(14).contains(mousePos);
    isCheeseMachineHovered = isCheeseUnlocked && cheeseMachineRect.inflate(14).contains(mousePos);
  }

  void setMovement(double dx, double dy) {
    moveDirX = dx;
    moveDirY = dy;
    if (dx != 0 || dy != 0) {
      targetMoveX = null;
      targetMoveY = null;
      pendingAutoFarmId = null;
      _pendingToolOnly = false;
      pendingDeliverMilkToCheese = false;
      pendingPackForCourier = false;
      pendingDeliverToCourier = false;
      pendingTakeOneShelfId = null;
    }
  }

  void spawnParticle(double x, double y, String text, Color color, {double size = 15}) {
    final random = Random();
    particles.add(
      WorldParticle(
        x: x,
        y: y,
        vx: (random.nextDouble() - 0.5) * 45,
        vy: -55 - (random.nextDouble() * 35),
        text: text,
        color: color,
        size: size,
      ),
    );
  }

  // ===============================================================
  // 🌙 DAY / NIGHT CYCLE, THIEVES & STICK
  // ===============================================================
  DayPhase phase = DayPhase.day;
  double phaseTimer = 0.0;
  final double dayLength = 120.0;   // seconds of daylight
  final double nightLength = 50.0;  // seconds of night
  List<Thief> thieves = [];
  double thiefSpawnTimer = 3.0;
  int nightThievesSpawned = 0;
  int nightThievesPlanned = 0;
  int nightStolenItems = 0;
  int nightRecoveredItems = 0;
  int nightThievesRepelled = 0;
  double nightStolenValue = 0.0;
  double nightBounty = 0.0;
  bool dawnReportPending = false;
  int reportDay = 1;
  double stickSwingTimer = 0.0; // 1.0 -> 0.0
  double stickCooldown = 0.0;
  double stickHitDirX = 1.0;
  bool tutorialFreeze = false;  // true while a tutorial card is open
  int nightsSurvived = 0;
  int totalThiefHits = 0;
  int _thiefCounter = 0;

  bool get isNight => phase == DayPhase.night;

  /// Day timer hit 0:00 but shoppers are still inside: wait for them to leave
  /// before the night (and the thieves) begin. No new customers come in.
  bool closingTime = false;

  // Small HUD toasts ("customer waiting", "delivery at the back door")
  String? toastText;
  double toastTimer = 0.0;
  int toastKind = 0; // 0 = register, 1 = delivery
  void showToast(String text, {int kind = 0, double seconds = 3.2}) {
    toastText = text;
    toastKind = kind;
    toastTimer = seconds;
  }
  double _closingTimer = 0.0;
  bool restockerAtHome = false;
  bool get staffOnDuty => !isNight;

  /// 0.0 = full daylight, 1.0 = deep night (used by the painter overlay & HUD).
  double get nightDarkness {
    if (phase == DayPhase.day) {
      final left = dayLength - phaseTimer;
      return (1.0 - left / 12.0).clamp(0.0, 1.0).toDouble();
    }
    final left = nightLength - phaseTimer;
    return (left / 8.0).clamp(0.0, 1.0).toDouble();
  }

  double get phaseTimeLeft =>
      (phase == DayPhase.day ? dayLength : nightLength) - phaseTimer;

  void _updateDayNight(double dt) {
    phaseTimer += dt;
    if (stickSwingTimer > 0) {
      stickSwingTimer = (stickSwingTimer - dt * 4.2).clamp(0.0, 1.0).toDouble();
    }
    if (stickCooldown > 0) stickCooldown -= dt;

    if (phase == DayPhase.day) {
      if (phaseTimer >= dayLength) {
        phaseTimer = dayLength; // clock waits at 0.00
        if (customers.isEmpty) {
          _startNight();
        } else {
          closingTime = true;
          _closingTimer += dt;
          // Stragglers who are still browsing head for the exit after a while
          if (_closingTimer > 6.0) {
            for (final c in customers) {
              if (c.state == CustomerState.walkingToEntrance ||
                  c.state == CustomerState.shopping) {
                c.state = CustomerState.leavingSad;
              }
            }
          }
        }
      }
    } else {
      if (phaseTimer >= nightLength) {
        _endNight();
      }
    }
  }

  void _startNight() {
    phase = DayPhase.night;
    phaseTimer = 0.0;
    closingTime = false;
    _closingTimer = 0.0;
    _sfx('night');
    customers.clear(); // (already empty: we waited for everyone to leave)
    _courierGoHome();
    thieves.clear();
    nightThievesSpawned = 0;
    nightStolenItems = 0;
    nightRecoveredItems = 0;
    nightThievesRepelled = 0;
    nightStolenValue = 0.0;
    nightBounty = 0.0;
    nightThievesPlanned = min(3 + day, 10); // thieves show up about as often as customers
    thiefSpawnTimer = 3.0;
    spawnParticle(playerX, playerY - 40, '🌙 Night falls! Guard the shelves!', Colors.lightBlueAccent, size: 18);
  }

  // ---- Difficulty -------------------------------------------------------
  /// 0 on day 1 (gentle start); from day 2 it jumps to 0.3 and climbs to 1.0 by day 10.
  double get difficulty => day <= 1 ? 0.0 : 0.3 + 0.7 * ((day - 2) / 8.0).clamp(0.0, 1.0).toDouble();

  /// Wholesale prices creep up as the days go by (up to +40%).
  double boxPrice(SimProductDef def) => (def.boxCost * (1.0 + 0.4 * difficulty)).roundToDouble();

  // ---- Daily wages ------------------------------------------------------
  static const double wageCashier = 30.0;
  static const double wageRestocker = 40.0;
  static const double wageCourier = 20.0;
  double lastWageTotal = 0.0;
  final List<String> lastWageLines = [];

  /// What the staff will cost at the next dawn (used by the Manager screen).
  double get dailyWages {
    double t = 0;
    if (hasAutoCashier) t += wageCashier;
    if (hasRestocker && isRestockerHired) t += wageRestocker;
    if (day >= 2) t += wageCourier;
    return t;
  }

  void _payWages() {
    lastWageLines.clear();
    lastWageTotal = 0.0;
    if (hasAutoCashier) {
      lastWageLines.add('Cashier: \$${wageCashier.toStringAsFixed(0)}');
      lastWageTotal += wageCashier;
    }
    if (hasRestocker && isRestockerHired) {
      lastWageLines.add('Stocker: \$${wageRestocker.toStringAsFixed(0)}');
      lastWageTotal += wageRestocker;
    }
    if (day >= 2) {
      lastWageLines.add('Courier: \$${wageCourier.toStringAsFixed(0)}');
      lastWageTotal += wageCourier;
    }
    cash -= lastWageTotal;
  }

  /// Put whatever is in the player's hands down right away (DROP button).
  /// Goods are never lost: they go back on the shelf or onto the floor as a box.
  void quickDrop() {
    if (carriedBox == null && playerTool == null) return;
    final box = carriedBox;
    if (box != null && box.currentCount > 0) {
      // Always put the load on the floor right where the player stands.
      deliveryBoxes.add(
        DeliveryBox(
          id: 'box_${DateTime.now().microsecondsSinceEpoch}',
          productType: box.productType,
          currentCount: box.currentCount,
          maxCount: max(box.maxCount, box.currentCount),
          x: playerX,
          y: playerY + 12,
        ),
      );
      spawnParticle(playerX, playerY - 40, 'Put down', Colors.lightBlueAccent, size: 13);
    }
    carriedBox = null;
    playerTool = null;
    _sfx('pickup');
    notifyListeners();
  }

  /// Called at the start of every new day so the screen can write the autosave.
  VoidCallback? onAutosave;

  /// Everything that has to survive a restart (taken at dawn, when the shop is quiet).
  Map<String, dynamic> toSave() => {
        'v': 1,
        'day': day,
        'cash': cash,
        'totalRevenue': totalRevenue,
        'storeLevel': storeLevel,
        'hasAutoCashier': hasAutoCashier,
        'hasRestocker': hasRestocker,
        'isRestockerHired': isRestockerHired,
        'nightsSurvived': nightsSurvived,
        'shelves': {
          for (final s in shelves) s.id: {'unlocked': s.isUnlocked, 'stock': s.currentStock},
        },
      };

  void loadSave(Map<String, dynamic> m) {
    day = (m['day'] as num?)?.toInt() ?? 1;
    cash = (m['cash'] as num?)?.toDouble() ?? cash;
    totalRevenue = (m['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    storeLevel = ((m['storeLevel'] as num?)?.toInt() ?? 1).clamp(1, 99);
    hasAutoCashier = m['hasAutoCashier'] == true;
    hasRestocker = m['hasRestocker'] == true;
    isRestockerHired = m['isRestockerHired'] == true;
    nightsSurvived = (m['nightsSurvived'] as num?)?.toInt() ?? 0;
    final sh = m['shelves'];
    if (sh is Map) {
      for (final s in shelves) {
        final d = sh[s.id];
        if (d is Map) {
          s.isUnlocked = d['unlocked'] == true;
          s.currentStock = ((d['stock'] as num?)?.toInt() ?? 0).clamp(0, s.maxCapacity);
        }
      }
    }
    for (final f in farmProducers) {
      final s = shelfForProduct(f.primaryProduct);
      if (s != null) f.isUnlocked = s.isUnlocked;
    }
    phase = DayPhase.day;
    phaseTimer = 0.0;
    closingTime = false;
    customerSpawnTimer = 5.0;
    thieves.clear();
    customers.clear();
    refreshShelfUnlocks();
    notifyListeners();
  }

  void _endNight() {
    // Anyone still inside escapes with whatever they are holding.
    for (final t in thieves) {
      if (t.carried > 0 && t.loot != null) {
        final def = productCatalog[t.loot!];
        nightStolenItems += t.carried;
        nightStolenValue += t.carried * (def?.retailPrice ?? 0.0);
      }
    }
    thieves.clear();
    phase = DayPhase.day;
    phaseTimer = 0.0;
    closingTime = false;
    _closingTimer = 0.0;
    nightsSurvived++;
    _sfx('dawn');
    reportDay = day;
    day++;
    customerSpawnTimer = 5.0;
    dawnUnlocks = refreshShelfUnlocks();
    _payWages();
    dawnReportPending = true;
    spawnParticle(playerX, playerY - 40, '☀️ A new day begins!', Colors.amberAccent, size: 18);
    onAutosave?.call();
  }

  void _updateThieves(double dt) {
    if (!isNight) return;

    // Spawn thieves spread across the first part of the night
    if (nightThievesSpawned < nightThievesPlanned && phaseTimer < nightLength - 10) {
      thiefSpawnTimer -= dt;
      if (thiefSpawnTimer <= 0) {
        _spawnThief();
        thiefSpawnTimer = max(3.0, (nightLength - 14) / max(1, nightThievesPlanned));
      }
    }

    for (int i = thieves.length - 1; i >= 0; i--) {
      final t = thieves[i];
      if (t.hitFlash > 0) t.hitFlash = (t.hitFlash - dt * 4.0).clamp(0.0, 1.0).toDouble();

      switch (t.state) {
        case ThiefState.sneaking:
          _thiefSneak(t, dt);
          break;
        case ThiefState.stealing:
          _thiefSteal(t, dt);
          break;
        case ThiefState.stunned:
          t.stunTimer -= dt;
          final knx = t.x + t.knockX * dt;
          final kny = t.y + t.knockY * dt;
          if (_thiefPosOk(t.x, t.y, knx, kny)) {
            t.x = knx;
            t.y = kny;
          } else {
            t.knockX = 0;
            t.knockY = 0;
          }
          t.knockX *= 0.86;
          t.knockY *= 0.86;
          if (t.stunTimer <= 0) {
            t.state = ThiefState.fleeing;
          }
          break;
        case ThiefState.fleeing:
          _moveThiefTowards(t, worldWidth / 2, 232, t.speed * 1.25, dt, isExit: true);
          break;
      }

      // Made it out of the door
      if (t.state == ThiefState.fleeing && (t.fromBack ? t.y >= 1025 : t.y <= 60)) {
        if (t.carried > 0 && t.loot != null) {
          final def = productCatalog[t.loot!];
          nightStolenItems += t.carried;
          nightStolenValue += t.carried * (def?.retailPrice ?? 0.0);
          spawnParticle(t.x, t.y, '🦹 Escaped with ${t.carried} ${def?.emoji ?? ''}!', Colors.redAccent, size: 15);
        }
        thieves.removeAt(i);
      }
    }
  }

  void _spawnThief() {
    final r = Random();
    final hp = 2 + (day >= 2 ? 1 : 0) + (day ~/ 4).clamp(0, 3).toInt();
    _thiefCounter++;
    // About 40% of the thieves sneak in through the back door (south alley)
    final fromBack = r.nextDouble() < 0.4;
    final t = Thief(
      id: 'thief_$_thiefCounter',
      x: worldWidth / 2 + (r.nextDouble() - 0.5) * (fromBack ? 160 : 160),
      y: fromBack ? 1035 : 25,
      hp: hp,
      speed: 105 + r.nextDouble() * 35 + min(day, 10) * 4.0 + difficulty * 25.0,
    );
    t.fromBack = fromBack;
    final target = _pickThiefTarget();
    if (target == null) {
      t.state = ThiefState.fleeing;
    } else {
      t.targetShelfId = target.id;
      t.loot = target.assignedProduct;
    }
    thieves.add(t);
    nightThievesSpawned++;
  }

  StoreShelf? _pickThiefTarget() {
    final candidates = shelves.where((s) => s.isUnlocked && s.currentStock > 0).toList();
    if (candidates.isEmpty) return null;
    return candidates[Random().nextInt(candidates.length)];
  }

  StoreShelf? _shelfById(String? id) {
    if (id == null) return null;
    for (final s in shelves) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _thiefSneak(Thief t, double dt) {
    var shelf = _shelfById(t.targetShelfId);
    if (shelf == null || shelf.currentStock <= 0) {
      shelf = _pickThiefTarget();
      if (shelf == null) {
        t.state = ThiefState.fleeing;
        return;
      }
      t.targetShelfId = shelf.id;
      t.loot = shelf.assignedProduct;
    }
    final tx = shelf.rect.center.dx;
    final ty = shelf.rect.bottom + 30;
    if (shelf.rect.inflate(48).contains(Offset(t.x, t.y))) {
      t.state = ThiefState.stealing;
      t.stealTimer = 0.6;
      return;
    }
    _moveThiefTowards(t, tx, ty, t.speed, dt);
  }

  void _thiefSteal(Thief t, double dt) {
    final shelf = _shelfById(t.targetShelfId);
    if (shelf == null) {
      t.state = ThiefState.fleeing;
      return;
    }
    t.stealTimer -= dt;
    if (t.stealTimer <= 0) {
      if (shelf.currentStock > 0 && t.carried < 3) {
        shelf.currentStock--;
        t.carried++;
        _sfx('steal');
        t.loot = shelf.assignedProduct;
        t.stealTimer = 1.0 - 0.35 * difficulty;
        spawnParticle(t.x, t.y - 26, '🦹 -1 ${productCatalog[shelf.assignedProduct]?.emoji ?? ''}', Colors.redAccent, size: 14);
      } else {
        t.state = ThiefState.fleeing;
      }
    }
  }

  void _moveThiefTowards(Thief t, double targetX, double targetY, double speed, double dt, {bool isExit = false}) {
    // Once outside the shop the thief just runs straight up the street.
    double gx = targetX;
    double gy = targetY;
    final doorCenter = worldWidth / 2;
    if (isExit && t.fromBack) {
      // Back-door thieves leave the same way they came in
      gx = doorCenter;
      gy = 1040;
    } else if (isExit && t.y <= 235) {
      gx = worldWidth / 2;
      gy = -40;
    }
    Offset wp;
    if (t.fromBack && !isExit && t.y > 982) {
      // Still in the back alley: go through the back door first
      wp = Offset(t.x.clamp(doorCenter - 100, doorCenter + 100).toDouble(), 955.0);
    } else if (t.y < 235 && gy >= 225 && (t.x - doorCenter).abs() > 100) {
      // Outside: walk to the door first, never through the front wall
      wp = Offset(doorCenter, 28);
    } else if (t.y < 235 && gy >= 225) {
      wp = Offset((t.x).clamp(doorCenter - 100, doorCenter + 100).toDouble(), 255.0);
    } else {
      // The route is expensive to compute: refresh it only a few times per second.
      t.wpTimer -= dt;
      if (t.wpCache == null ||
          t.wpTimer <= 0 ||
          (t.wpGx - gx).abs() > 1 ||
          (t.wpGy - gy).abs() > 1 ||
          (Offset(t.x, t.y) - t.wpCache!).distance < 4) {
        t.wpCache = _getStoreSmartWaypoint(t.x, t.y, gx, gy);
        t.wpGx = gx;
        t.wpGy = gy;
        t.wpTimer = 0.2;
      }
      wp = t.wpCache!;
    }
    final dx = wp.dx - t.x;
    final dy = wp.dy - t.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > 0.5) {
      final step = speed * dt;
      double nx, ny;
      if (step >= dist) {
        nx = wp.dx;
        ny = wp.dy;
      } else {
        nx = t.x + (dx / dist) * step;
        ny = t.y + (dy / dist) * step;
      }
      if (_thiefPosOk(t.x, t.y, nx, ny)) {
        t.x = nx;
        t.y = ny;
      } else if (_thiefPosOk(t.x, t.y, nx, t.y)) {
        t.x = nx; // slide along walls / shelves
      } else if (_thiefPosOk(t.x, t.y, t.x, ny)) {
        t.y = ny;
      }
      t.walkAngle = atan2(dy, dx);
      t.walkAnim += dt * 10;
    }
  }

  /// Walls, shelves and desks block thieves just like they block the player.
  bool _thiefPosOk(double ox, double oy, double nx, double ny) {
    final doorCenter = worldWidth / 2;
    if (ny >= 225) {
      if (ny > 975) {
        // Only the back door opening leads out of the shop
        if ((nx - doorCenter).abs() > 125 || ny > 1055) return false;
      } else if (nx < storeMinX || nx > storeMaxX) {
        return false;
      }
    }
    if ((oy < 230 && ny >= 230) || (oy >= 230 && ny < 230)) {
      if ((nx - doorCenter).abs() > 130) return false;
    }
    if (ny >= 232) {
      final r = Rect.fromCircle(center: Offset(nx, ny), radius: 10);
      for (final obs in _getStoreObstacleRects()) {
        if (r.overlaps(obs.deflate(4))) {
          // allow stepping out of an obstacle we are already touching
          final cur = Rect.fromCircle(center: Offset(ox, oy), radius: 10);
          if (cur.overlaps(obs.deflate(4))) continue;
          return false;
        }
      }
    }
    return true;
  }

  /// Swing the stick. Hits every thief close to the player.
  void swingStick() {
    // The stick only comes out after dark
    if (!isNight) return;
    if (stickCooldown > 0) return;
    stickCooldown = 0.42;
    stickSwingTimer = 1.0;
    _sfx('swish');

    // Face the nearest thief in reach so the swing looks right
    Thief? nearest;
    double best = 150;
    for (final t in thieves) {
      final d = sqrt(pow(t.x - playerX, 2) + pow(t.y - playerY, 2)).toDouble();
      if (d < best) {
        best = d;
        nearest = t;
      }
    }
    if (nearest != null) {
      playerAngle = atan2(nearest.y - playerY, nearest.x - playerX);
    }
    stickHitDirX = cos(playerAngle) >= 0 ? 1.0 : -1.0;

    bool hitAny = false;
    for (final t in List<Thief>.from(thieves)) {
      final d = sqrt(pow(t.x - playerX, 2) + pow(t.y - playerY, 2)).toDouble();
      if (d <= 92) {
        _hitThief(t);
        hitAny = true;
      }
    }
    if (!hitAny) {
      spawnParticle(playerX + stickHitDirX * 36, playerY - 10, 'swish', Colors.white70, size: 11);
    }
  }

  /// Called when the player taps on a thief: swing if close, otherwise run at it.
  void attackThiefAt(Thief t) {
    final d = sqrt(pow(t.x - playerX, 2) + pow(t.y - playerY, 2)).toDouble();
    if (d <= 92) {
      swingStick();
    } else {
      setTargetMove(t.x, t.y + 20);
    }
  }

  Thief? thiefNear(double wx, double wy, {double radius = 40}) {
    Thief? best;
    double bestD = radius;
    for (final t in thieves) {
      final d = sqrt(pow(t.x - wx, 2) + pow(t.y - 6 - wy, 2)).toDouble();
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    return best;
  }

  void _hitThief(Thief t) {
    // A thief that was already driven off can't be hit again (no bounty farming)
    if (t.hp <= 0) return;
    totalThiefHits++;
    _sfx('hit');
    t.hp--;
    t.hitFlash = 1.0;
    var kx = t.x - playerX;
    var ky = t.y - playerY;
    final len = max(1.0, sqrt(kx * kx + ky * ky));
    kx /= len;
    ky /= len;
    t.knockX = kx * 340;
    t.knockY = ky * 340;
    t.state = ThiefState.stunned;
    t.stunTimer = 0.45;
    spawnParticle(t.x, t.y - 30, '💥', Colors.orangeAccent, size: 20);

    if (t.hp <= 0) {
      // Drops the loot back on the shelf and runs away empty-handed
      if (t.carried > 0 && t.loot != null) {
        returnItemsToShelfOrBox(t.loot!, t.carried);
        nightRecoveredItems += t.carried;
        t.carried = 0;
      }
      nightThievesRepelled++;
      const bounty = 15.0;
      cash += bounty;
      nightBounty += bounty;
      spawnParticle(t.x, t.y - 46, 'Thief driven off! +\$15', Colors.greenAccent, size: 16);
      t.state = ThiefState.stunned;
      t.stunTimer = 0.45;
      t.hp = 0;
    }
  }

  void update(double dt) {
    if (tutorialFreeze) {
      notifyListeners();
      return;
    }
    worldTime += dt;
    if (playerScanAnimTimer > 0) {
      playerScanAnimTimer = (playerScanAnimTimer - dt * 1.65).clamp(0.0, 1.0);
      if (playerScanAnimTimer <= 0) {
        currentScanningProduct = null;
      }
    }
    _updatePlayer(dt);
    _updatePlayerFarmActions(dt);
    _updateCheeseMachine(dt);
    _updateShelvesAndDoors(dt);

    // Kamera oyuncuyu yumuşak ve akıcı biçimde takip eder
    final camLerp = (4.5 * dt).clamp(0.0, 1.0);
    cameraX += (playerX - cameraX) * camLerp;
    cameraY += (playerY - cameraY) * camLerp;

    _updateFarmProduction(dt);
    _updateTruck(dt);
    _updateCourier(dt);
    _updateCourierPacking(dt);
    if (hasRestocker && isRestockerHired) {
      if (isNight) {
        _restockerGoHome(dt);
      } else {
        if (restockerAtHome) {
          restockerAtHome = false;
          restocker.x = worldWidth / 2;
          restocker.y = 70;
          restocker.carriedBox = null;
          restocker.equippedTool = null;
        }
        _updateRestocker(dt);
      }
    }
    if (isStoreOpen && !isNight) {
      _updateCustomers(dt);
    }
    _updateDayNight(dt);
    _updateThieves(dt);
    _updateParticles(dt);
    if (toastTimer > 0) toastTimer -= dt;
    _checkInteractions();
    notifyListeners();
  }

  // ===============================================================
  // 🧀 3D PEYNİR YAPMA MAKİNESİ SİSTEMİ (SÜTÜ TULUM PEYNİRİNE DÖNÜŞTÜRÜR)
  // ===============================================================
  void _updateCheeseMachine(double dt) {
    if (!isCheeseUnlocked) return;

    if (cheeseMachineMilkInput > 0 && cheeseMachineReadyBoxes < cheeseMachineMaxBoxes) {
      cheeseMachineTimer += dt;
      if (Random().nextDouble() < 0.08) {
        spawnParticle(
          cheeseMachineRect.center.dx,
          cheeseMachineRect.top - 10,
          '🧀',
          Colors.amberAccent,
          size: 13,
        );
      }
      if (cheeseMachineTimer >= cheeseMachineDuration) {
        cheeseMachineTimer = 0.0;
        cheeseMachineMilkInput--;
        cheeseMachineReadyBoxes++;
        spawnParticle(
          cheeseMachineRect.center.dx,
          cheeseMachineRect.top - 16,
          '🧀 Tulum Cheese Ready! ($cheeseMachineReadyBoxes/$cheeseMachineMaxBoxes)',
          Colors.greenAccent,
          size: 16,
        );
      }
    }
  }

  void handleCheeseMachineClick() {
    if (!isCheeseUnlocked) return;

    final playerPos = Offset(playerX, playerY);
    final isNear = cheeseMachineRect.inflate(65).contains(playerPos);

    if (isNear) {
      interactWithCheeseMachine();
      return;
    }

    // Oyuncunun elinde süt varsa makineye götürsün
    if (carriedBox != null && carriedBox!.productType == SimProductType.milk) {
      pendingDeliverMilkToCheese = true;
      setTargetMove(cheeseMachineRect.center.dx, cheeseMachineRect.bottom + 18, clearPendingFarm: false);
      return;
    }

    // Makinede hazır peynir varsa ve elleri boşsa almaya gitsin
    if (cheeseMachineReadyBoxes > 0 && carriedBox == null) {
      pendingDeliverMilkToCheese = true;
      setTargetMove(cheeseMachineRect.center.dx, cheeseMachineRect.bottom + 18, clearPendingFarm: false);
      return;
    }

    // Makinede peynir yoksa ve elinde süt de yoksa: önce Ahıra gidip süt sağsın, sonra makineye getirsin!
    if (carriedBox == null) {
      final barn = farmProducers.firstWhere((f) => f.zoneType == FarmZoneType.barn);
      pendingDeliverMilkToCheese = true;
      startAutoFarmHarvest(barn);
      spawnParticle(
        cheeseMachineRect.center.dx,
        cheeseMachineRect.top - 15,
        '🥛 Milking at the Barn First, Then Bringing It to the Cheese Machine...',
        Colors.lightBlueAccent,
        size: 14,
      );
    }
  }

  bool interactWithCheeseMachine() {
    if (!isCheeseUnlocked) return false;

    // 1. Oyuncunun elinde Süt varsa makineye döksün!
    if (carriedBox != null && carriedBox!.productType == SimProductType.milk && carriedBox!.currentCount > 0) {
      if (cheeseMachineMilkInput + cheeseMachineReadyBoxes >= cheeseMachineMaxBoxes) {
        spawnParticle(
          cheeseMachineRect.center.dx,
          cheeseMachineRect.top - 15,
          '⚠️ Cheese Machine Is Full!',
          Colors.orangeAccent,
        );
        return false;
      }
      carriedBox = null;
      playerTool = null;
      cheeseMachineMilkInput++;
      spawnParticle(
        cheeseMachineRect.center.dx,
        cheeseMachineRect.top - 18,
        '🥛➔🧀 Milk Poured into the Cheese Machine!',
        Colors.cyanAccent,
        size: 16,
      );
      notifyListeners();
      return true;
    }

    // 2. Makinede hazır Tulum Peyniri varsa ve oyuncunun eli boşsa peyniri alsın!
    if (carriedBox == null && cheeseMachineReadyBoxes > 0) {
      final def = productCatalog[SimProductType.cheese]!;
      cheeseMachineReadyBoxes--;
      playerTool = null;
      carriedBox = CarriedBox(
        productType: SimProductType.cheese,
        currentCount: def.boxSize,
        maxCount: def.boxSize,
        isFromFarm: true,
      );
      spawnParticle(
        cheeseMachineRect.center.dx,
        cheeseMachineRect.top - 18,
        '🧀 +${def.boxSize} Tulum Cheese Collected!',
        Colors.amberAccent,
        size: 16,
      );
      notifyListeners();
      return true;
    }

    // 3. Elinde süt yoksa ve hazır peynir yoksa ahıra süt sağmaya yönlendir
    if (carriedBox == null && cheeseMachineMilkInput == 0) {
      final barn = farmProducers.firstWhere((f) => f.zoneType == FarmZoneType.barn);
      pendingDeliverMilkToCheese = true;
      startAutoFarmHarvest(barn);
      return true;
    }

    return false;
  }

  // ===============================================================
  // 🧺🌾 ÇİFTLİK EKİPMAN & İÇERİ GİRİP HASAT / SAĞIM / TOPLAMA SİSTEMİ
  // Çiftlikten çıkınca Tırpan ve Kova otomatik bırakılır!
  // ===============================================================

  /// Oyuncu alet standından Kova veya Çapa alır
  void equipToolFromStand(FarmProducer farm) {
    playerTool = farm.requiredTool;
    _sfx('pickup');
    spawnParticle(
      playerX,
      playerY - 38,
      '${farm.requiredTool.emoji} ${farm.requiredTool.name} Picked Up!',
      Colors.amberAccent,
      size: 16,
    );
    notifyListeners();
  }

  /// Tıklanan veya [E] basılan çiftlik alanında: kilitliyse seviye yetiyorsa açar, açıksa ekipmanı alıp toplama başlatır
  void handleFarmZoneOrToolClick(FarmProducer farm, Offset clickWorldPos) {
    if (!farm.isUnlocked) {
      final shelf = shelfForProduct(farm.primaryProduct);
      if (shelf != null) {
        tryUnlockShelfOrFarm(shelf, feedbackPos: farm.rect.center);
      }
      return;
    }
    startAutoFarmHarvest(farm, preferredPos: clickWorldPos);
  }

  void startAutoFarmHarvest(FarmProducer farm, {Offset? preferredPos}) {
    if (!farm.isUnlocked) return;
    if (carriedBox != null) {
      final isCompatible = _isProductFromFarm(carriedBox!.productType, farm) &&
          carriedBox!.currentCount < carriedBox!.maxCount;
      if (!isCompatible) {
        spawnParticle(
          playerX,
          playerY - 35,
          '⚠️ Put what you are holding on the store shelf first!',
          Colors.orangeAccent,
          size: 15,
        );
        return;
      }
    }

    // 1. Oyuncunun elinde bu alanın ekipmanı (Süt Kovası / Tırpan / Yumurta Kovası) yoksa önce standa gidip alsın!
    if (playerTool != farm.requiredTool) {
      final playerPos = Offset(playerX, playerY);
      if ((playerPos - farm.toolStandPos).distance < 75) {
        equipToolFromStand(farm);
      } else {
        final keepCheeseFlag = pendingDeliverMilkToCheese;
        pendingAutoFarmId = farm.id;
        _pendingToolOnly = false;
        setTargetMove(farm.toolStandPos.dx, farm.toolStandPos.dy + 12, clearPendingFarm: false);
        pendingDeliverMilkToCheese = keepCheeseFlag;
        spawnParticle(
          farm.toolStandPos.dx,
          farm.toolStandPos.dy - 20,
          '${farm.requiredTool.emoji} Picking Up ${farm.requiredTool.name} First...',
          Colors.cyanAccent,
          size: 14,
        );
        return;
      }
    }

    // 2. Elinde ekipman varsa doğrudan çiftliğin İÇİNE (ineğin / mahsulün / folluğun yanına) girsin!
    final keepCheeseFlag = pendingDeliverMilkToCheese;
    final spot = _findBestReadySpot(farm, preferredPos ?? Offset(playerX, playerY));
    if (spot != null) {
      pendingAutoFarmId = farm.id;
      _pendingToolOnly = false;
      setTargetMove(spot.x, spot.y, clearPendingFarm: false);
      pendingDeliverMilkToCheese = keepCheeseFlag;
    } else {
      setTargetMove(farm.gateCenter.dx, farm.rect.top + 85, clearPendingFarm: false);
      pendingDeliverMilkToCheese = keepCheeseFlag;
      spawnParticle(
        farm.gateCenter.dx,
        farm.rect.top + 30,
        '⏳ New crops/milk are being prepared...',
        Colors.amberAccent,
        size: 14,
      );
    }
  }

  bool _isProductFromFarm(SimProductType type, FarmProducer farm) {
    return farm.primaryProduct == type;
  }

  FarmHarvestSpot? _findBestReadySpot(FarmProducer farm, Offset refPos, {SimProductType? filterProduct}) {
    FarmHarvestSpot? best;
    double bestDist = double.infinity;
    for (final s in farm.spots) {
      if (!s.isReady) continue;
      if (filterProduct != null && s.productType != filterProduct) continue;
      final d = (Offset(s.x, s.y) - refPos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    if (best == null && filterProduct != null) {
      return _findBestReadySpot(farm, refPos);
    }
    return best;
  }

  void _updatePlayerFarmActions(double dt) {
    activeHarvestSpot = null;
    final playerPos = Offset(playerX, playerY);

    // 0. Oyuncu peynir makinesine otomatik yürüyorsa ve makineye ulaştıysa:
    if (pendingDeliverMilkToCheese && cheeseMachineRect.inflate(62).contains(playerPos)) {
      if (carriedBox != null && carriedBox!.productType == SimProductType.milk) {
        pendingDeliverMilkToCheese = false;
        interactWithCheeseMachine();
        targetMoveX = null;
        targetMoveY = null;
        return;
      } else if (carriedBox == null && cheeseMachineReadyBoxes > 0) {
        pendingDeliverMilkToCheese = false;
        interactWithCheeseMachine();
        targetMoveX = null;
        targetMoveY = null;
        return;
      }
    }

    // 1. Eğer oyuncu otomatik olarak önce kova/tırpan standına yürüyorsa:
    if (pendingAutoFarmId != null) {
      final farm = farmProducers.firstWhere((f) => f.id == pendingAutoFarmId, orElse: () => farmProducers.first);

      if (playerTool != farm.requiredTool && (playerPos - farm.toolStandPos).distance < 55) {
        equipToolFromStand(farm);
        if (_pendingToolOnly) {
          pendingAutoFarmId = null;
          _pendingToolOnly = false;
          targetMoveX = null;
          targetMoveY = null;
          return;
        }
        final keepCheese = pendingDeliverMilkToCheese;
        final nextSpot = _findBestReadySpot(farm, playerPos);
        if (nextSpot != null) {
          setTargetMove(nextSpot.x, nextSpot.y, clearPendingFarm: false);
        } else {
          setTargetMove(farm.gateCenter.dx, farm.rect.top + 85, clearPendingFarm: false);
          pendingAutoFarmId = null;
        }
        pendingDeliverMilkToCheese = keepCheese;
      }
    }

    // 2. TARLADAN / ÇİFTLİKTEN ÇIKTIĞINDA ÇAPAYI VE KOVAYI OTOMATİK BIRAK!
    if (playerTool != null) {
      final insideMatchingFarm = farmProducers.any(
        (f) => f.isUnlocked && f.requiredTool == playerTool && f.rect.inflate(10).contains(playerPos),
      );
      final walkingIntoMatchingFarm = pendingAutoFarmId != null &&
          farmProducers.any((f) => f.id == pendingAutoFarmId && f.requiredTool == playerTool);

      if (!insideMatchingFarm && !walkingIntoMatchingFarm) {
        final droppedTool = playerTool!;
        playerTool = null;
        spawnParticle(
          playerX,
          playerY - 24,
          '${droppedTool.emoji} ${droppedTool.name} Left at the Field',
          Colors.white70,
          size: 14,
        );
      }
    }

    // 3. Oyuncu bir çiftlik alanının İÇİNDEYSE ve doğru ekipmanı (Süt Kovası / Çapa / Tavuk Kovası) tutuyorsa:
    for (final farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if (!farm.rect.inflate(10).contains(playerPos)) continue;

      if (pendingAutoFarmId == farm.id) {
        pendingAutoFarmId = null;
      }

      if (carriedBox != null) {
        if (!_isProductFromFarm(carriedBox!.productType, farm)) continue;
        if (carriedBox!.currentCount >= carriedBox!.maxCount) continue;
      }

      // WASD / D-pad ile doğrudan çiftliğin içine yürüdüyse ekipmanı otomatik eline alsın
      if (playerTool != farm.requiredTool) {
        equipToolFromStand(farm);
      }

      FarmHarvestSpot? nearbySpot;
      double minDist = 66.0;
      for (final spot in farm.spots) {
        if (!spot.isReady) continue;
        final d = (Offset(spot.x, spot.y) - playerPos).distance;
        if (d < minDist) {
          minDist = d;
          nearbySpot = spot;
        }
      }

      if (nearbySpot != null) {
        activeHarvestSpot = nearbySpot;
        playerActionAnimTimer += dt * 15.0;
        nearbySpot.harvestProgress += dt / 1.15;

        if (Random().nextDouble() < 0.22) {
          final pDef = productCatalog[farm.primaryProduct]!;
          spawnParticle(nearbySpot.x, nearbySpot.y - 12, pDef.emoji, const Color(0xFFFDE047), size: 13);
        }

        if (nearbySpot.harvestProgress >= 1.0) {
          nearbySpot.harvestProgress = 0.0;
          nearbySpot.isReady = false;
          nearbySpot.regrowTimer = 0.0;
          _sfx('pickup');

          final SimProductType harvestedProd = farm.primaryProduct;
          final def = productCatalog[harvestedProd]!;
          final int gain = (def.boxSize / 2).ceil(); // 2 nokta = 1 tam dolu kova / çuval!

          if (carriedBox == null) {
            carriedBox = CarriedBox(
              productType: harvestedProd,
              currentCount: gain,
              maxCount: def.boxSize,
              isFromFarm: true,
            );
          } else {
            carriedBox!.currentCount = min(carriedBox!.maxCount, carriedBox!.currentCount + gain);
          }

          final isFull = carriedBox!.currentCount >= carriedBox!.maxCount;
          if (isFull) {
            pendingAutoFarmId = null;
            playerTool = null;

            String msg = '${def.emoji} ${def.name} Harvested! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            if (farm.zoneType == FarmZoneType.barn) {
              msg = '🥛 Milk Bucket Full! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            } else if (farm.primaryProduct == SimProductType.flour) {
              msg = '🌾 Flour Harvested with Hoe! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            } else if (farm.zoneType == FarmZoneType.coop) {
              msg = '🥚 Egg Bucket Full! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            }
            spawnParticle(playerX, playerY - 40, msg, Colors.greenAccent, size: 15);

            // Eğer Peynir Makinesi için süt alındıysa otomatik olarak Peynir Makinesine götürsün!
            if (pendingDeliverMilkToCheese && harvestedProd == SimProductType.milk) {
              setTargetMove(
                cheeseMachineRect.center.dx,
                cheeseMachineRect.bottom + 18,
                clearPendingFarm: false,
              );
              pendingDeliverMilkToCheese = true;
            }
          } else {
            final stepMsg = '+$gain ${def.emoji} ${def.name} (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            spawnParticle(playerX, playerY - 36, stepMsg, Colors.lightGreenAccent, size: 15);

            if (moveDirX == 0 && moveDirY == 0) {
              final keepCheese = pendingDeliverMilkToCheese;
              final nextSpot = _findBestReadySpot(farm, playerPos);
              if (nextSpot != null) {
                setTargetMove(nextSpot.x, nextSpot.y, clearPendingFarm: false);
                pendingDeliverMilkToCheese = keepCheese;
              }
            }
          }
        }
      }
    }
  }

  // ===============================================================
  // 🛵 MOTORLU KURYE & ACİL ONLİNE SİPARİŞ DÖNGÜSÜ
  // ===============================================================
  /// Courier clocks out for the night: drops the current order and rides off.
  void _courierGoHome() {
    if (courierState == CourierState.arriving ||
        courierState == CourierState.waitingForOrder) {
      activeCourierOrder = null;
      courierStagedCount = 0;
      courierStagedProduct = null;
      courierPackingProgress = 0.0;
      pendingPackForCourier = false;
      pendingDeliverToCourier = false;
      shouldOpenCourierPackingDialog = false;
      _warnedExcessAtDesk = false;
      courierState = CourierState.departing;
    }
  }

  void _updateCourier(double dt) {
    if (isNight && (courierState == CourierState.arriving || courierState == CourierState.waitingForOrder)) {
      _courierGoHome();
    }
    switch (courierState) {
      case CourierState.away:
        if (isNight) break; // off duty until morning
        courierCooldown -= dt;
        if (courierCooldown <= 0) {
          courierX = worldWidth + 140;
          courierState = CourierState.arriving;
        }
        break;

      case CourierState.arriving:
        if (courierX > courierParkX) {
          courierX -= 420 * dt;
          if (Random().nextDouble() < 0.25) {
            spawnParticle(courierX + 45, 162, '💨', Colors.white60, size: 11);
          }
        } else {
          courierX = courierParkX;
          courierState = CourierState.waitingForOrder;
          _generateNewCourierOrder();
        }
        break;

      case CourierState.waitingForOrder:
        if (activeCourierOrder == null) {
          _generateNewCourierOrder();
          break;
        }
        activeCourierOrder!.remainingTime -= dt;
        if (activeCourierOrder!.remainingTime <= 0) {
          spawnParticle(
            courierStation.center.dx,
            courierStation.top - 15,
            '⏰ Courier Time Is Up!',
            Colors.redAccent,
            size: 16,
          );
          activeCourierOrder = null;
          courierStagedCount = 0;
          courierStagedProduct = null;
          courierPackingProgress = 0.0;
          pendingPackForCourier = false;
          pendingDeliverToCourier = false;
          shouldOpenCourierPackingDialog = false;
          _warnedExcessAtDesk = false;
          courierState = CourierState.departing;
        }
        break;

      case CourierState.departing:
        courierX -= 520 * dt;
        if (Random().nextDouble() < 0.35) {
          spawnParticle(courierX + 55, 162, '💨', Colors.amberAccent, size: 12);
        }
        if (courierX < -180) {
          courierState = CourierState.away;
          courierCooldown = 5.5;
        }
        break;
    }
  }

  void _generateNewCourierOrder() {
    final available = unlockedProducts;
    if (available.isEmpty) return;

    final random = Random();
    final chosenProd = available[random.nextInt(available.length)];
    final def = productCatalog[chosenProd]!;
    final qty = 3 + random.nextInt(4);
    final reward = (def.retailPrice * qty * 2.2).roundToDouble();

    final onlineNames = ['QuickBite #402', 'FastMarket #108', 'Local Courier #85', 'Urgent Parcel #219', 'VIP Order #77'];
    activeCourierOrder = CourierOrder(
      id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
      customerName: onlineNames[random.nextInt(onlineNames.length)],
      productType: chosenProd,
      requiredQty: qty,
      deliveredQty: 0,
      rewardAmount: reward,
      remainingTime: 55.0,
      totalTime: 55.0,
    );
    courierStagedCount = 0;
    courierStagedProduct = null;
    courierPackingProgress = 0.0;
    _warnedExcessAtDesk = false;
    shouldOpenCourierPackingDialog = false;

    spawnParticle(
      courierStation.center.dx,
      courierStation.top - 20,
      '🛵 New Courier Order: ${qty}x ${def.emoji} (Grab One by One from the Cabinet & 📦 Pack!)',
      Colors.amberAccent,
      size: 17,
    );
  }

  /// 📦 Kurye Paketleme İstasyonu & Kurye Teslimat Akışı
  /// Motorlu kurye açık/paketsiz ürünü kabul etmez ve kasada paketlenmez; SADECE Paketleme İstasyonunda 📦 paketlenir!
  void _updateCourierPacking(double dt) {
    if (courierState != CourierState.waitingForOrder || activeCourierOrder == null) {
      courierPackingProgress = 0.0;
      _warnedExcessAtDesk = false;
      return;
    }

    final order = activeCourierOrder!;
    final def = productCatalog[order.productType]!;
    final playerPos = Offset(playerX, playerY);

    // Oyuncu Paketleme İstasyonunun yanındaysa:
    final nearPackDesk = courierPackingDesk.inflate(62).contains(playerPos);
    if (nearPackDesk) {
      if (carriedBox != null &&
          !carriedBox!.isCourierPackage &&
          carriedBox!.productType == order.productType &&
          carriedBox!.currentCount > 0) {
        final needed = order.remainingQty;
        final totalWithHeld = courierStagedCount + carriedBox!.currentCount;

        if (totalWithHeld > needed) {
          // Fazla ürün getirildiyse otomatik paketleme yapma! Uyarı ver ve paketleme penceresini aç.
          final excess = totalWithHeld - needed;
          if (!_warnedExcessAtDesk || pendingPackForCourier) {
            _warnedExcessAtDesk = true;
            spawnParticle(
              courierPackingDesk.center.dx,
              courierPackingDesk.top - 22,
              '⚠️ Too many! The courier wants $needed ${def.emoji} ($excess extra)!',
              Colors.orangeAccent,
              size: 16,
            );
            if (pendingPackForCourier) {
              pendingPackForCourier = false;
              targetMoveX = null;
              targetMoveY = null;
              shouldOpenCourierPackingDialog = true;
            }
          }
        } else {
          _warnedExcessAtDesk = false;
          _stageHeldItemsAtCourierDesk();
        }
      } else if (pendingPackForCourier) {
        pendingPackForCourier = false;
        targetMoveX = null;
        targetMoveY = null;
        if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType != order.productType) {
          spawnParticle(
            courierPackingDesk.center.dx,
            courierPackingDesk.top - 18,
            '❌ Wrong Item! The courier wants ${order.requiredQty}x ${def.emoji} ${def.name}!',
            Colors.redAccent,
            size: 15,
          );
        } else if (courierStagedCount < order.remainingQty) {
          shouldOpenCourierPackingDialog = true;
        }
      }

      // Masada TAM gereken miktarda ürün biriktiyse canlı paketleme & bantlama animasyonunu ilerlet
      if (courierStagedCount >= order.remainingQty &&
          courierStagedCount > 0 &&
          courierStagedProduct == order.productType &&
          carriedBox == null) {
        playerActionAnimTimer += dt * 15.0;
        courierPackingProgress += dt * 1.15;
        if (Random().nextDouble() < 0.22) {
          spawnParticle(
            courierPackingDesk.center.dx,
            courierPackingDesk.top - 10,
            '📦',
            const Color(0xFFFDE047),
            size: 13,
          );
        }
        if (courierPackingProgress >= 1.0) {
          final packedQty = courierStagedCount;
          courierStagedCount = 0;
          courierStagedProduct = null;
          courierPackingProgress = 0.0;
          playerTool = null;
          carriedBox = CarriedBox(
            productType: order.productType,
            currentCount: packedQty,
            maxCount: order.requiredQty,
            isCourierPackage: true,
          );
          spawnParticle(
            courierPackingDesk.center.dx,
            courierPackingDesk.top - 22,
            '📦 ${def.emoji} Courier Package Ready! Take It to the Bike! ($packedQty/${order.requiredQty})',
            Colors.greenAccent,
            size: 16,
          );
          if (pendingPackForCourier) {
            pendingPackForCourier = false;
            pendingDeliverToCourier = true;
            setTargetMove(
              courierStation.center.dx,
              courierStation.bottom + 18,
              clearPendingFarm: false,
            );
          }
        }
      }
    } else {
      _warnedExcessAtDesk = false;
    }

    // Oyuncu elinde hazır 📦 Kurye Paketi ile motora ulaştıysa teslim et!
    if (pendingDeliverToCourier &&
        carriedBox != null &&
        carriedBox!.isCourierPackage &&
        courierStation.inflate(82).contains(playerPos)) {
      pendingDeliverToCourier = false;
      targetMoveX = null;
      targetMoveY = null;
      deliverToCourier();
    }
  }

  /// Dolaptan / raftan HER BASIŞTA TAM 1 ADET ürün alır (Yumurta, Un, Süt vb.)
  bool takeOneFromShelf(StoreShelf shelf) {
    if (!shelf.isUnlocked) {
      final def = productCatalog[shelf.assignedProduct]!;
      spawnParticle(
        shelf.rect.center.dx,
        shelf.rect.top - 14,
        '🔒 ${def.emoji} ${shelfLockReason(shelf)}',
        Colors.redAccent,
        size: 14,
      );
      return false;
    }

    final def = productCatalog[shelf.assignedProduct]!;
    if (carriedBox != null) {
      if (carriedBox!.isCourierPackage) {
        spawnParticle(
          playerX,
          playerY - 32,
          '🛵 Hand the Courier Package you are holding to the bike first!',
          Colors.orangeAccent,
          size: 14,
        );
        return false;
      }
      if (carriedBox!.productType != shelf.assignedProduct) {
        spawnParticle(
          playerX,
          playerY - 32,
          '⚠️ You are holding another item! Drop it or pack it first.',
          Colors.orangeAccent,
          size: 14,
        );
        return false;
      }
      if (!carriedBox!.isPickedFromShelf) {
        // Çiftlikten veya kamyondan getirilen ürün ise rafa diz
        _stockSingleItemFromPlayer(shelf);
        return true;
      }
      if (carriedBox!.currentCount >= carriedBox!.maxCount) {
        spawnParticle(
          playerX,
          playerY - 32,
          '⚠️ Your hands are full! (Max ${carriedBox!.maxCount} items)',
          Colors.orangeAccent,
          size: 14,
        );
        return false;
      }
    }

    if (shelf.currentStock <= 0) {
      spawnParticle(
        shelf.rect.center.dx,
        shelf.rect.top - 14,
        '❌ ${def.emoji} ${def.name} Out of Stock in the Cabinet!',
        Colors.redAccent,
        size: 15,
      );
      return false;
    }

    final slotPos = getShelfItemSlotPos(shelf, shelf.currentStock - 1);
    shelf.currentStock -= 1;
    shelf.doorOpenProgress = 1.0;
    shelf.lastPlacedBounceTimer = 1.0;
    playerTool = null;

    if (carriedBox == null) {
      carriedBox = CarriedBox(
        productType: shelf.assignedProduct,
        currentCount: 1,
        maxCount: max(def.boxSize, 12),
        isFromFarm: false,
        isCourierPackage: false,
        isPickedFromShelf: true,
      );
    } else {
      carriedBox!.currentCount += 1;
    }

    flyingShelfItems.add(
      ShelfFlyingItem(
        productType: shelf.assignedProduct,
        startPos: slotPos,
        endPos: Offset(playerX, playerY - 24),
        duration: 0.22,
      ),
    );

    String msg = '+1 ${def.emoji} Picked (In Hand: ${carriedBox!.currentCount})';
    if (courierState == CourierState.waitingForOrder &&
        activeCourierOrder != null &&
        activeCourierOrder!.productType == shelf.assignedProduct) {
      final needed = activeCourierOrder!.remainingQty;
      final total = courierStagedCount + carriedBox!.currentCount;
      if (total > needed) {
        msg = '+1 ${def.emoji} (In Hand: ${carriedBox!.currentCount} • ⚠️ ${total - needed} extra for the courier!)';
      } else {
        msg = '+1 ${def.emoji} Picked ($total/$needed for the courier)';
      }
    }

    spawnParticle(
      shelf.rect.center.dx,
      shelf.rect.top - 16,
      msg,
      Colors.cyanAccent,
      size: 14,
    );
    notifyListeners();
    return true;
  }

  /// Eldeki/dolaptan alınan ürünü rafa veya masaya geri döndürür
  bool returnItemsToShelfOrBox(SimProductType productType, int count) {
    if (count <= 0) return false;
    int remaining = count;
    for (final s in shelves) {
      if (s.isUnlocked && s.assignedProduct == productType && s.currentStock < s.maxCapacity) {
        final add = min(remaining, s.maxCapacity - s.currentStock);
        s.currentStock += add;
        s.lastPlacedBounceTimer = 0.8;
        remaining -= add;
        if (remaining <= 0) break;
      }
    }
    if (remaining > 0) {
      final def = productCatalog[productType]!;
      deliveryBoxes.add(
        DeliveryBox(
          id: 'box_${DateTime.now().microsecondsSinceEpoch}',
          productType: productType,
          currentCount: remaining,
          maxCount: max(def.boxSize, remaining),
          x: courierPackingDesk.left - 30,
          y: courierPackingDesk.bottom + 14,
        ),
      );
    }
    notifyListeners();
    return true;
  }

  /// Raf/dolap tıklaması: kilitliyse açmayı dener; açıksa elinde koli varsa dizer, yoksa her basışta 1 adet alır
  void handleShelfClick(StoreShelf shelf) {
    if (!shelf.isUnlocked) {
      tryUnlockShelfOrFarm(shelf, feedbackPos: shelf.rect.center);
      return;
    }
    final playerPos = Offset(playerX, playerY);
    if (!shelf.rect.inflate(55).contains(playerPos)) {
      if (carriedBox == null ||
          (carriedBox!.isPickedFromShelf && carriedBox!.productType == shelf.assignedProduct)) {
        pendingTakeOneShelfId = shelf.id;
      }
      setTargetMove(shelf.rect.center.dx, shelf.rect.bottom + 24, clearPendingFarm: false);
      return;
    }

    if (carriedBox != null &&
        !carriedBox!.isCourierPackage &&
        !carriedBox!.isPickedFromShelf &&
        carriedBox!.productType == shelf.assignedProduct) {
      _stockSingleItemFromPlayer(shelf);
    } else {
      takeOneFromShelf(shelf);
    }
  }

  /// Kurye paketleme masasına yalnızca gereken veya daha az miktardaki ürünü koyar (fazlaysa koymaz, uyarı verir)
  void _stageHeldItemsAtCourierDesk() {
    if (activeCourierOrder == null || carriedBox == null || carriedBox!.isCourierPackage) return;
    final order = activeCourierOrder!;
    if (carriedBox!.productType != order.productType || carriedBox!.currentCount <= 0) return;

    final needed = max(0, order.remainingQty - courierStagedCount);
    if (needed <= 0) return;
    if (carriedBox!.currentCount > needed) return; // Fazla ürün varsa dialogda ayarlanacak!

    final take = carriedBox!.currentCount;
    courierStagedProduct = order.productType;
    courierStagedCount += take;
    carriedBox = null;

    flyingShelfItems.add(
      ShelfFlyingItem(
        productType: order.productType,
        startPos: Offset(playerX, playerY - 24),
        endPos: courierPackingDesk.center,
        duration: 0.22,
      ),
    );

    final def = productCatalog[order.productType]!;
    final remAfter = max(0, order.remainingQty - courierStagedCount);
    spawnParticle(
      courierPackingDesk.center.dx,
      courierPackingDesk.top - 14,
      remAfter > 0
          ? '📦 +$take ${def.emoji} Placed on the Table ($courierStagedCount/${order.requiredQty}) — bring $remAfter more!'
          : '📦 +$take ${def.emoji} Complete! Taping the Package...',
      Colors.amberAccent,
      size: 15,
    );
  }

  /// Paketleme penceresinden (fazla çıkarılıp tam sayıya ayarlandıktan sonra) kurye paketini mühürler
  bool sealCourierPackageFromDialog({required int packCount, required int excessReturned}) {
    if (courierState != CourierState.waitingForOrder || activeCourierOrder == null) return false;
    final order = activeCourierOrder!;
    if (packCount <= 0 || packCount > order.remainingQty) return false;

    final def = productCatalog[order.productType]!;

    // Varsa çıkarılan fazlalığı rafa (veya masa yanındaki kasaya) geri koy
    if (excessReturned > 0) {
      returnItemsToShelfOrBox(order.productType, excessReturned);
      spawnParticle(
        courierPackingDesk.left - 18,
        courierPackingDesk.top - 12,
        '↩️ $excessReturned extra ${def.emoji} returned to the shelf',
        Colors.lightBlueAccent,
        size: 14,
      );
    }

    courierStagedCount = 0;
    courierStagedProduct = null;
    courierPackingProgress = 0.0;
    pendingPackForCourier = false;
    _warnedExcessAtDesk = false;
    playerTool = null;

    carriedBox = CarriedBox(
      productType: order.productType,
      currentCount: packCount,
      maxCount: order.requiredQty,
      isCourierPackage: true,
    );

    spawnParticle(
      courierPackingDesk.center.dx,
      courierPackingDesk.top - 22,
      '📦 ${def.emoji} Courier Package Ready! ($packCount/${order.requiredQty}) Take It to the Bike!',
      Colors.greenAccent,
      size: 16,
    );
    notifyListeners();
    return true;
  }

  /// Paketleme penceresinden kısmi ürünleri masada bırakıp geri kalanını dolaptan almak için
  void keepStagedAtPackingDeskFromDialog({required int stageCount, required int excessReturned}) {
    if (courierState != CourierState.waitingForOrder || activeCourierOrder == null) return;
    final order = activeCourierOrder!;
    final def = productCatalog[order.productType]!;
    if (excessReturned > 0) {
      returnItemsToShelfOrBox(order.productType, excessReturned);
    }
    courierStagedProduct = stageCount > 0 ? order.productType : null;
    courierStagedCount = stageCount;
    carriedBox = null;
    _warnedExcessAtDesk = false;
    if (stageCount > 0) {
      spawnParticle(
        courierPackingDesk.center.dx,
        courierPackingDesk.top - 16,
        '📦 $stageCount/${order.remainingQty} ${def.emoji} waiting on the table!',
        Colors.amberAccent,
        size: 14,
      );
    }
    notifyListeners();
  }

  void handleCourierPackingDeskClick() {
    if (courierState != CourierState.waitingForOrder || activeCourierOrder == null) {
      spawnParticle(
        courierPackingDesk.center.dx,
        courierPackingDesk.top - 14,
        '📦 Waiting for an active courier order...',
        Colors.white70,
        size: 14,
      );
      return;
    }

    final order = activeCourierOrder!;
    final def = productCatalog[order.productType]!;
    final playerPos = Offset(playerX, playerY);

    // Elinde zaten hazır kurye paketi varsa motora yönlendir!
    if (carriedBox != null && carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
      pendingDeliverToCourier = true;
      setTargetMove(courierStation.center.dx, courierStation.bottom + 18, clearPendingFarm: false);
      spawnParticle(
        playerX,
        playerY - 30,
        '🛵 Taking the Ready Courier Package to the Bike!',
        Colors.greenAccent,
        size: 15,
      );
      return;
    }

    // Masanın yakınındaysak paketleme penceresini aç veya eksik/fazla kontrolü yap
    if (courierPackingDesk.inflate(62).contains(playerPos)) {
      if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType != order.productType) {
        spawnParticle(
          courierPackingDesk.center.dx,
          courierPackingDesk.top - 16,
          '❌ Wrong Item! The courier wants ${order.requiredQty}x ${def.emoji} ${def.name}!',
          Colors.redAccent,
          size: 15,
        );
        return;
      }

      if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
        final total = courierStagedCount + carriedBox!.currentCount;
        if (total > order.remainingQty) {
          final excess = total - order.remainingQty;
          spawnParticle(
            courierPackingDesk.center.dx,
            courierPackingDesk.top - 18,
            '⚠️ Too many! The courier wants ${order.remainingQty} ${def.emoji} ($excess extra)!',
            Colors.orangeAccent,
            size: 16,
          );
        }
      }

      shouldOpenCourierPackingDialog = true;
      notifyListeners();
      return;
    }

    // Uzaktaysak önce Paketleme İstasyonuna yürüsün!
    pendingPackForCourier = true;
    setTargetMove(courierPackingDesk.center.dx, courierPackingDesk.bottom + 20, clearPendingFarm: false);
    if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
      spawnParticle(
        courierPackingDesk.center.dx,
        courierPackingDesk.top - 16,
        '📦 Heading to the Courier Packing Station...',
        Colors.amberAccent,
        size: 15,
      );
    } else {
      spawnParticle(
        courierPackingDesk.center.dx,
        courierPackingDesk.top - 16,
        '📦 First Take ${order.requiredQty}x ${def.emoji} One by One from the Cabinet & Bring Them Here!',
        Colors.cyanAccent,
        size: 15,
      );
    }
  }

  /// Kurye siparişini SADECE paketlenmiş 📦 Kurye Paketi (`isCourierPackage == true`) ile tamamlar!
  /// Eğer oyuncunun elinde açık/paketsiz ürün varsa kurye kabul etmez ve Paketleme İstasyonuna yönlendirir.
  bool deliverToCourier() {
    if (courierState != CourierState.waitingForOrder || activeCourierOrder == null) {
      return false;
    }

    final order = activeCourierOrder!;
    final needed = order.remainingQty;
    if (needed <= 0) return false;
    final def = productCatalog[order.productType]!;
    final playerPos = Offset(playerX, playerY);

    // 1. Oyuncunun elinde AÇIK (paketlenmemiş) ürün varsa kurye direkt kabul etmez!
    if (carriedBox != null && !carriedBox!.isCourierPackage) {
      if (carriedBox!.productType == order.productType) {
        final total = courierStagedCount + carriedBox!.currentCount;
        final warnText = total > needed
            ? '⚠️ The Courier Will Not Take Open Items & You Are Holding Extra! Fix It at the Packing Station!'
            : '⚠️ The Courier Will Not Take Open Items! Pack 📦 at the Packing Station First!';
        spawnParticle(
          courierStation.center.dx,
          courierStation.top - 18,
          warnText,
          Colors.orangeAccent,
          size: 16,
        );
        pendingPackForCourier = true;
        setTargetMove(
          courierPackingDesk.center.dx,
          courierPackingDesk.bottom + 20,
          clearPendingFarm: false,
        );
      } else {
        spawnParticle(
          courierStation.center.dx,
          courierStation.top - 16,
          '❌ The Courier Is Waiting for a ${def.emoji} ${def.name} Package!',
          Colors.redAccent,
          size: 15,
        );
      }
      notifyListeners();
      return false;
    }

    // 2. Oyuncunun elinde hazır 📦 Kurye Sipariş Paketi varsa:
    if (carriedBox != null && carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
      // Henüz motorun yanında değilse motora yürüsün
      if (!courierStation.inflate(85).contains(playerPos)) {
        pendingDeliverToCourier = true;
        setTargetMove(
          courierStation.center.dx,
          courierStation.bottom + 18,
          clearPendingFarm: false,
        );
        spawnParticle(
          playerX,
          playerY - 30,
          '🛵 Taking the Courier Package to the Bike...',
          Colors.lightGreenAccent,
          size: 15,
        );
        notifyListeners();
        return false;
      }

      final take = min(needed, carriedBox!.currentCount);
      carriedBox!.currentCount -= take;
      order.deliveredQty += take;
      if (carriedBox!.currentCount <= 0) {
        carriedBox = null;
      }

      flyingShelfItems.add(
        ShelfFlyingItem(
          productType: order.productType,
          startPos: Offset(playerX, playerY - 24),
          endPos: Offset(courierX, 152),
          duration: 0.25,
        ),
      );

      if (order.isCompleted) {
        cash += order.rewardAmount;
        _sfx('cash');
        totalRevenue += order.rewardAmount;
        completedCourierOrders++;
        spawnParticle(
          courierStation.center.dx,
          courierStation.top - 25,
          '🛵 COURIER PACKAGE DELIVERED! +\$${order.rewardAmount.toStringAsFixed(0)} 🌟',
          Colors.greenAccent,
          size: 21,
        );
        activeCourierOrder = null;
        courierStagedCount = 0;
        courierStagedProduct = null;
        courierPackingProgress = 0.0;
        _warnedExcessAtDesk = false;
        courierState = CourierState.departing;
      } else {
        spawnParticle(
          courierStation.center.dx,
          courierStation.top - 15,
          '📦 +$take ${def.emoji} Package Loaded to the Courier (${order.deliveredQty}/${order.requiredQty})',
          Colors.lightBlueAccent,
          size: 15,
        );
      }

      notifyListeners();
      return true;
    }

    // 3. Oyuncunun elleri boşsa -> Paketleme İstasyonuna yönlendir / bilgi ver
    handleCourierPackingDeskClick();
    return false;
  }

  // ===============================================================
  // 👷 3D OTOMATİK REYON & ÇİFTLİK GÖREVLİSİ (STOKÇU ALİ - Seviye 3'te Açılır)
  // Tarladan çıkınca tırpanı/kovayı bırakır; Peynir için sütü Peynir Makinesine götürür!
  // ===============================================================
  /// At night the restocker walks out of the front door and goes home.
  void _restockerGoHome(double dt) {
    if (restockerAtHome) return;
    restocker.carriedBox = null;
    restocker.equippedTool = null;
    restocker.statusText = 'Going home';
    final wp = _getStoreSmartWaypoint(restocker.x, restocker.y, worldWidth / 2, 20);
    final dx = wp.dx - restocker.x;
    final dy = wp.dy - restocker.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > 0.5) {
      final step = 150.0 * dt;
      restocker.walkTimer += dt * 10.0;
      if (step >= dist) {
        restocker.x = wp.dx;
        restocker.y = wp.dy;
      } else {
        restocker.x += dx / dist * step;
        restocker.y += dy / dist * step;
      }
    }
    if (restocker.y <= 40) restockerAtHome = true;
  }

  void _updateRestocker(double dt) {
    const double workerSpeed = 165.0;
    final doorCenter = worldWidth / 2;

    // En çok stoğa ihtiyacı olan açık rafı bul
    StoreShelf? needyShelf;
    double lowestRatio = 0.88;
    for (final s in shelves) {
      if (!s.isUnlocked) continue;
      final ratio = s.currentStock / s.maxCapacity;
      if (ratio < lowestRatio) {
        lowestRatio = ratio;
        needyShelf = s;
      }
    }

    // Eğer Tulum Peyniri rafı stok bekliyorsa ve Stokçu Ali'nin elinde tam dolu Süt varsa -> Sütü Peynir Makinesine götürsün!
    if (needyShelf != null &&
        needyShelf.assignedProduct == SimProductType.cheese &&
        restocker.carriedBox != null &&
        restocker.carriedBox!.productType == SimProductType.milk &&
        restocker.carriedBox!.currentCount >= restocker.carriedBox!.maxCount) {
      restocker.equippedTool = null;

      // Önce ahırın içindeyse kapıdan çıksın
      for (final f in farmProducers) {
        if (f.rect.inflate(8).contains(Offset(restocker.x, restocker.y))) {
          _moveWorkerTowards(f.gateCenter.dx, f.rect.top - 24, workerSpeed, dt);
          restocker.statusText = '🥛 Taking Milk to the Cheese Machine';
          return;
        }
      }

      final mx = cheeseMachineRect.center.dx;
      final my = cheeseMachineRect.bottom + 18;
      _moveWorkerTowards(mx, my, workerSpeed, dt);
      restocker.statusText = '🥛➔🧀 Pouring Milk into the Cheese Machine';

      if ((restocker.x - mx).abs() < 26 && (restocker.y - my).abs() < 26) {
        restocker.carriedBox = null;
        cheeseMachineMilkInput++;
        spawnParticle(mx, cheeseMachineRect.top - 14, '👷 🥛➔🧀 Milk Added to the Machine', Colors.cyanAccent, size: 13);
      }
      return;
    }

    // 1. Elinde ürün varsa (tam dolu veya çiftlikten çıkmışsa) ilgili rafa götürüp TEK TEK dizsin
    if (restocker.carriedBox != null &&
        restocker.carriedBox!.currentCount > 0 &&
        (restocker.carriedBox!.currentCount >= restocker.carriedBox!.maxCount ||
            restocker.equippedTool == null)) {
      restocker.equippedTool = null; // Çiftlikten çıkarken tırpanı/kovayı bırak!
      final box = restocker.carriedBox!;
      final targetShelf = shelves.firstWhere(
        (s) => s.isUnlocked && s.assignedProduct == box.productType,
        orElse: () => shelves.first,
      );

      for (final f in farmProducers) {
        if (!f.isUnlocked) continue;
        if (f.rect.inflate(8).contains(Offset(restocker.x, restocker.y))) {
          _moveWorkerTowards(f.gateCenter.dx, f.rect.top - 24, workerSpeed, dt);
          restocker.statusText = '${box.containerEmoji} Leaving the Farm';
          return;
        }
      }

      // 2. sıradaki meyve/sebze tarlalarından (y > 1460) üst bahçeye çıkarken 1. sıra çiftliklerin arasındaki koridordan geç!
      if (restocker.y > 1460) {
        final corridorX = (restocker.x - 680).abs() < (restocker.x - 1320).abs() ? 680.0 : 1320.0;
        if ((restocker.x - corridorX).abs() > 45) {
          _moveWorkerTowards(corridorX, 1505, workerSpeed, dt);
          restocker.statusText = '${box.containerEmoji} Walking the Garden Corridor';
          return;
        }
        _moveWorkerTowards(corridorX, 1100, workerSpeed, dt);
        restocker.statusText = '${box.containerEmoji} Heading to the Store';
        return;
      }

      if (restocker.y > 995 && (restocker.x - doorCenter).abs() > 90) {
        _moveWorkerTowards(doorCenter, 975, workerSpeed, dt);
        restocker.statusText = '${box.containerEmoji} Carrying to the Store';
        return;
      }

      final tx = targetShelf.rect.center.dx;
      final ty = targetShelf.rect.bottom + 24;
      _moveWorkerTowards(tx, ty, workerSpeed, dt);
      final def = productCatalog[box.productType]!;
      restocker.statusText = '${box.containerEmoji} Stacking ${def.emoji} ${def.name} One by One';

      if ((restocker.x - tx).abs() < 24 && (restocker.y - ty).abs() < 24) {
        final space = targetShelf.maxCapacity - targetShelf.currentStock;
        if (space <= 0) {
          restocker.carriedBox = null;
          restocker.statusText = '✅ Shelf Filled';
          return;
        }
        targetShelf.doorOpenProgress = (targetShelf.doorOpenProgress + dt * 4.5).clamp(0.0, 1.0);
        restocker.actionAnimTimer += dt * 14.0;
        targetShelf.stockStepTimer += dt;
        if (targetShelf.stockStepTimer >= 0.16) {
          targetShelf.stockStepTimer = 0.0;
          final slotIdx = targetShelf.currentStock;
          targetShelf.currentStock++;
          box.currentCount--;
          targetShelf.lastPlacedBounceTimer = 1.0;
          final dest = getShelfItemSlotPos(targetShelf, slotIdx);
          flyingShelfItems.add(
            ShelfFlyingItem(
              productType: targetShelf.assignedProduct,
              startPos: Offset(restocker.x, restocker.y - 22),
              endPos: dest,
              duration: 0.18,
            ),
          );
          spawnParticle(dest.dx, dest.dy - 8, '👷 +1 ${def.emoji}', Colors.cyanAccent, size: 12);
          if (box.currentCount <= 0 || targetShelf.currentStock >= targetShelf.maxCapacity) {
            restocker.carriedBox = null;
            restocker.statusText = '✅ Shelf Filled';
          }
        }
      }
      return;
    }

    if (needyShelf == null) {
      restocker.equippedTool = null;
      for (final f in farmProducers) {
        if (f.rect.inflate(8).contains(Offset(restocker.x, restocker.y))) {
          _moveWorkerTowards(f.gateCenter.dx, f.rect.top - 24, workerSpeed, dt);
          return;
        }
      }
      _moveWorkerTowards(1160, 620, workerSpeed * 0.7, dt);
      restocker.statusText = '👍 All Shelves Are Full';
      return;
    }

    SimProductType wantedProd = needyShelf.assignedProduct;
    SimProductDef def = productCatalog[wantedProd]!;

    // Önce yerde bu üründen teslimat kolisi var mı?
    if (restocker.carriedBox == null) {
      DeliveryBox? matchingBox;
      for (final b in deliveryBoxes) {
        if (b.productType == wantedProd) {
          matchingBox = b;
          break;
        }
      }

      if (matchingBox != null) {
        restocker.equippedTool = null;
        _moveWorkerTowards(matchingBox.x, matchingBox.y, workerSpeed, dt);
        restocker.statusText = '📦 Going to Get a ${def.emoji} Box';
        if ((restocker.x - matchingBox.x).abs() < 24 && (restocker.y - matchingBox.y).abs() < 24) {
          restocker.carriedBox = CarriedBox(
            productType: matchingBox.productType,
            currentCount: matchingBox.currentCount,
            maxCount: matchingBox.maxCount,
          );
          deliveryBoxes.remove(matchingBox);
        }
        return;
      }
    }

    // 🧀 Eğer Tulum Peyniri gerekiyorsa Peynir Makinesini kontrol et!
    if (wantedProd == SimProductType.cheese && isCheeseUnlocked) {
      if (cheeseMachineReadyBoxes > 0 && restocker.carriedBox == null) {
        restocker.equippedTool = null;
        if (restocker.y < 980 && (restocker.x - doorCenter).abs() > 95) {
          _moveWorkerTowards(doorCenter, 1010, workerSpeed, dt);
          return;
        }
        final mx = cheeseMachineRect.center.dx;
        final my = cheeseMachineRect.bottom + 18;
        _moveWorkerTowards(mx, my, workerSpeed, dt);
        restocker.statusText = '🧀 Taking Cheese from the Cheese Machine';
        if ((restocker.x - mx).abs() < 26 && (restocker.y - my).abs() < 26) {
          cheeseMachineReadyBoxes--;
          restocker.carriedBox = CarriedBox(
            productType: SimProductType.cheese,
            currentCount: def.boxSize,
            maxCount: def.boxSize,
            isFromFarm: true,
          );
          spawnParticle(mx, cheeseMachineRect.top - 14, '👷 +${def.boxSize} 🧀 Taken', Colors.amberAccent, size: 13);
        }
        return;
      } else if (cheeseMachineMilkInput > 0 && restocker.carriedBox == null) {
        restocker.equippedTool = null;
        final mx = cheeseMachineRect.center.dx;
        final my = cheeseMachineRect.bottom + 18;
        _moveWorkerTowards(mx, my, workerSpeed * 0.7, dt);
        restocker.statusText = '⏳ Waiting for the Cheese to Be Ready';
        return;
      } else {
        // Peynir makinesine dökmek için önce Ahırdan Süt sağsın!
        wantedProd = SimProductType.milk;
        def = productCatalog[wantedProd]!;
      }
    }

    // Yoksa arka bahçedeki uygun çiftlik tesisine (Ahır, Tarlalar, Elma Bahçesi, Kümes) gitsin
    FarmProducer? targetFarm;
    for (final f in farmProducers) {
      if (!f.isUnlocked || f.readySpotCount <= 0) continue;
      if (f.primaryProduct == wantedProd) {
        targetFarm = f;
        break;
      }
    }

    if (targetFarm == null) {
      restocker.equippedTool = null;
      if (restocker.carriedBox != null && restocker.carriedBox!.currentCount > 0) {
        restocker.carriedBox = CarriedBox(
          productType: restocker.carriedBox!.productType,
          currentCount: restocker.carriedBox!.currentCount,
          maxCount: restocker.carriedBox!.currentCount,
          isFromFarm: true,
        );
        return;
      }
      _moveWorkerTowards(1160, 620, workerSpeed * 0.6, dt);
      restocker.statusText = '⏳ Waiting for a Delivery';
      return;
    }

    for (final f in farmProducers) {
      if (!f.isUnlocked) continue;
      if (f != targetFarm && f.rect.inflate(8).contains(Offset(restocker.x, restocker.y))) {
        _moveWorkerTowards(f.gateCenter.dx, f.rect.top - 24, workerSpeed, dt);
        return;
      }
    }

    if (restocker.y < 980 && (restocker.x - doorCenter).abs() > 95) {
      _moveWorkerTowards(doorCenter, 1010, workerSpeed, dt);
      restocker.statusText = '🚜 Heading Down to the Farm';
      return;
    }

    // Hedef tarla 2. sıradaysa (y > 1500) ve Ali henüz 1. sıra çiftliklerin üstündeyse koridordan aşağı insin
    if (targetFarm.rect.top > 1500 && restocker.y < 1465) {
      final corridorX = (targetFarm.gateCenter.dx - 680).abs() < (targetFarm.gateCenter.dx - 1320).abs()
          ? 680.0
          : 1320.0;
      if (restocker.y < 1150 && (restocker.x - corridorX).abs() > 45) {
        _moveWorkerTowards(corridorX, 1110, workerSpeed, dt);
        restocker.statusText = '🚜 On the Way to ${targetFarm.name}';
        return;
      }
      _moveWorkerTowards(corridorX, 1500, workerSpeed, dt);
      restocker.statusText = '🚜 Coming Down the ${targetFarm.name} Corridor';
      return;
    }

    // Hedef tarla 1. sıradaysa (y < 1500) ve Ali 2. sıradaysa (y > 1465) koridordan yukarı çıksın
    if (targetFarm.rect.top < 1500 && restocker.y > 1465) {
      final corridorX = (restocker.x - 680).abs() < (restocker.x - 1320).abs() ? 680.0 : 1320.0;
      if ((restocker.x - corridorX).abs() > 45) {
        _moveWorkerTowards(corridorX, 1500, workerSpeed, dt);
        return;
      }
      _moveWorkerTowards(corridorX, 1110, workerSpeed, dt);
      return;
    }

    // ADIM 1: Elinde doğru Kova / Tırpan yoksa önce o çiftliğin Alet Standına gidip Kova / Tırpan alsın!
    if (restocker.equippedTool != targetFarm.requiredTool) {
      final stand = targetFarm.toolStandPos;
      _moveWorkerTowards(stand.dx, stand.dy + 10, workerSpeed, dt);
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${targetFarm.requiredTool.name} Picking Up';
      if ((restocker.x - stand.dx).abs() < 26 && (restocker.y - (stand.dy + 10)).abs() < 26) {
        restocker.equippedTool = targetFarm.requiredTool;
        spawnParticle(
          stand.dx,
          stand.dy - 18,
          '👷 ${targetFarm.requiredTool.emoji} ${targetFarm.requiredTool.name} Picked Up',
          Colors.cyanAccent,
          size: 13,
        );
      }
      return;
    }

    // ADIM 2: Çiftliğin dışındaysa önce açık kapıdan İÇERİ girsin
    final isInsideTargetFarm = targetFarm.rect.contains(Offset(restocker.x, restocker.y));
    if (!isInsideTargetFarm) {
      _moveWorkerTowards(targetFarm.gateCenter.dx, targetFarm.rect.top + 28, workerSpeed, dt);
      restocker.statusText = '${targetFarm.requiredTool.emoji} Going Into ${targetFarm.name}';
      return;
    }

    // ADIM 3: İçerideki hazır ineğe / buğday öbeğine / yumurta folluğuna yürüsün ve toplasın!
    final spot = _findBestReadySpot(targetFarm, Offset(restocker.x, restocker.y));
    if (spot == null) return;

    _moveWorkerTowards(spot.x, spot.y, workerSpeed, dt);
    if ((restocker.x - spot.x).abs() < 24 && (restocker.y - spot.y).abs() < 24) {
      restocker.actionAnimTimer += dt * 15.0;
      spot.harvestProgress += dt / 1.25;
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${targetFarm.requiredTool.actionVerb}...';

      if (Random().nextDouble() < 0.18) {
        final pEmoji = targetFarm.zoneType == FarmZoneType.field
            ? '🌾'
            : (targetFarm.zoneType == FarmZoneType.barn ? '🥛' : '🥚');
        spawnParticle(spot.x, spot.y - 12, pEmoji, Colors.amberAccent, size: 12);
      }

      if (spot.harvestProgress >= 1.0) {
        spot.harvestProgress = 0.0;
        spot.isReady = false;
        spot.regrowTimer = 0.0;

        final gain = (def.boxSize / 2).ceil();
        if (restocker.carriedBox == null) {
          restocker.carriedBox = CarriedBox(
            productType: wantedProd,
            currentCount: gain,
            maxCount: def.boxSize,
            isFromFarm: true,
          );
        } else {
          restocker.carriedBox!.currentCount =
              min(def.boxSize, restocker.carriedBox!.currentCount + gain);
        }

        if (restocker.carriedBox!.currentCount >= def.boxSize) {
          restocker.equippedTool = null; // Tamamlanınca tırpanı/kovayı bırak!
        }

        spawnParticle(
          spot.x,
          spot.y - 20,
          '👷 +$gain ${def.emoji} (${restocker.carriedBox!.currentCount}/${def.boxSize})',
          Colors.cyanAccent,
          size: 13,
        );
      }
    } else {
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${def.emoji} Walking to Collect';
    }
  }

  void _moveWorkerTowards(double tx, double ty, double speed, double dt) {
    final wp = _getStoreSmartWaypoint(restocker.x, restocker.y, tx, ty);
    final dx = wp.dx - restocker.x;
    final dy = wp.dy - restocker.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > 2.0) {
      restocker.walkTimer += dt * 10.0;
      final step = min(dist, speed * dt);
      restocker.x += (dx / dist) * step;
      restocker.y += (dy / dist) * step;
    }
  }

  void _updateFarmProduction(double dt) {
    for (var farm in farmProducers) {
      if (!farm.isUnlocked) continue;

      // Çiftlikteki tavukların, ineklerin ve ekinlerin sırayla (teker teker) canlı üretim döngüsü
      farm.productionTimer += dt;
      if (farm.productionTimer >= 2.2) {
        farm.productionTimer = 0.0;
        final activeIdx = (worldTime ~/ 2.2) % farm.spots.length;
        final activeSpot = farm.spots[activeIdx];
        if (activeSpot.isReady && activeSpot.justProducedTimer <= 0.0) {
          activeSpot.justProducedTimer = 1.0;
        }
      }

      for (final spot in farm.spots) {
        if (spot.justProducedTimer > 0.0) {
          spot.justProducedTimer = (spot.justProducedTimer - dt * 0.85).clamp(0.0, 1.0);
        }

        if (!spot.isReady) {
          spot.regrowTimer += dt;
          if (spot.regrowTimer >= spot.regrowDuration) {
            spot.regrowTimer = 0.0;
            spot.isReady = true;
            spot.harvestProgress = 0.0;
            spot.justProducedTimer = 1.0;

            final def = productCatalog[spot.productType]!;
            String popText = '✨ +1 ${def.emoji} Ready!';
            if (farm.zoneType == FarmZoneType.coop) {
              popText = '🐔 Laid an Egg! +1 🥚';
            } else if (farm.zoneType == FarmZoneType.barn) {
              popText = '🐄 Milk Refilled! +1 🥛';
            } else {
              popText = '🌱 ${def.emoji} Grew!';
            }
            spawnParticle(spot.x, spot.y - 22, popText, Colors.amberAccent, size: 13);
          }
        }
      }

      farm.readyBoxes = farm.readySpotCount;
    }
  }

  bool _canMoveTo(double nx, double ny) {
    final bool insideStore = ny >= 225 && ny <= 985;
    final double minX = insideStore ? storeMinX : 90.0;
    final double maxX = insideStore ? storeMaxX : (worldWidth - 90);
    if (nx < minX || nx > maxX || ny < 60 || ny > (worldHeight - 40)) {
      return false;
    }

    final doorCenter = worldWidth / 2; // 1000

    // Üst duvar (Ön Cadde Giriş Kapısı: x: 860 - 1140 arası geniş kapı)
    if (playerY >= 230 && ny < 230) {
      if (nx < doorCenter - 140 || nx > doorCenter + 140) return false;
    } else if (playerY < 230 && ny >= 230) {
      if (nx < doorCenter - 140 || nx > doorCenter + 140) return false;
    }

    // Alt duvar (Arka Bahçe Çiftlik Kapısı: x: 860 - 1140 arası geniş kapı)
    if (ny > 975 && ny < 1005) {
      if (nx < doorCenter - 138 || nx > doorCenter + 138) return false;
    }
    if (playerY <= 990 && ny > 990) {
      if (nx < doorCenter - 138 || nx > doorCenter + 138) return false;
    } else if (playerY > 990 && ny <= 990) {
      if (nx < doorCenter - 138 || nx > doorCenter + 138) return false;
    }

    final playerRect = Rect.fromCircle(center: Offset(nx, ny), radius: 14);
    if (playerRect.overlaps(computerDesk.deflate(6))) return false;
    if (playerRect.overlaps(courierPackingDesk.deflate(6))) return false;
    for (final cRect in unlockedCheckouts) {
      if (playerRect.overlaps(cRect.deflate(6))) return false;
    }
    if (isCheeseUnlocked && playerRect.overlaps(cheeseMachineRect.deflate(8))) return false;

    for (var shelf in shelves) {
      if (!shelf.isUnlocked) continue;
      if (playerRect.overlaps(shelf.rect.deflate(6))) {
        return false;
      }
    }

    for (var farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if (!farm.solidBuildingRect.isEmpty && playerRect.overlaps(farm.solidBuildingRect.deflate(6))) {
        return false;
      }

      final r = farm.rect;
      if (playerY <= r.top && ny > r.top && nx >= r.left - 8 && nx <= r.right + 8) {
        if (nx < farm.gateMinX || nx > farm.gateMaxX) return false;
      } else if (playerY > r.top && ny <= r.top && nx >= r.left - 8 && nx <= r.right + 8) {
        if (nx < farm.gateMinX || nx > farm.gateMaxX) return false;
      }

      if (ny > r.top && ny < r.bottom + 8) {
        if (playerX >= r.left + 12 && nx < r.left + 12) return false;
        if (playerX <= r.left - 12 && nx > r.left - 12) return false;
        if (playerX <= r.right - 12 && nx > r.right - 12) return false;
        if (playerX >= r.right + 12 && nx < r.right + 12) return false;
      }
      if (nx > r.left && nx < r.right) {
        if (playerY <= r.bottom - 12 && ny > r.bottom - 12) return false;
        if (playerY >= r.bottom + 12 && ny < r.bottom + 12) return false;
      }
    }

    return true;
  }

  /// Click-to-Move ile yürürken kapılardan ve çiftlik çit kapılarından akıllı geçiş noktası hesaplar
  Offset _getSmartWaypoint(double destX, double destY) {
    final doorCenter = worldWidth / 2;

    for (final farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      final insideNow = farm.rect.contains(Offset(playerX, playerY));
      final destInside = farm.rect.contains(Offset(destX, destY));
      if (insideNow && !destInside) {
        if (playerY > farm.rect.top + 8 && (playerX < farm.gateMinX || playerX > farm.gateMaxX)) {
          return Offset(farm.gateCenter.dx, farm.rect.top + 22);
        }
        return Offset(farm.gateCenter.dx, farm.rect.top - 22);
      }
    }

    if (playerY < 985 && destY > 995 && (playerX - doorCenter).abs() > 115) {
      if (playerY < 955) {
        return _getStoreSmartWaypoint(playerX, playerY, doorCenter, 965);
      }
      return Offset(doorCenter, 1020);
    }
    if (playerY > 995 && destY < 985 && (playerX - doorCenter).abs() > 115) {
      return Offset(doorCenter, 1020);
    }

    if (playerY >= 235 && destY < 225 && (playerX - doorCenter).abs() > 115) {
      if (playerY > 265) {
        return _getStoreSmartWaypoint(playerX, playerY, doorCenter, 250);
      }
      return Offset(doorCenter, 210);
    }
    if (playerY < 225 && destY >= 235 && (playerX - doorCenter).abs() > 115) {
      return Offset(doorCenter, 250);
    }

    // 1. sıra çiftlikler (y: 1160..1450) ile 2. sıra tarlalar (y: 1565..1825) arasında yürürken koridoru kullan
    if (playerY < 1150 && destY > 1470) {
      final corridorX = (destX - 680).abs() < (destX - 1320).abs() ? 680.0 : 1320.0;
      if ((playerX - corridorX).abs() > 55) {
        return Offset(corridorX, 1115);
      }
      return Offset(corridorX, 1500);
    }
    if (playerY >= 1150 && playerY < 1465 && destY > 1470) {
      final corridorX = (playerX - 680).abs() < (playerX - 1320).abs() ? 680.0 : 1320.0;
      return Offset(corridorX, 1500);
    }
    if (playerY > 1470 && destY < 1440) {
      final corridorX = (playerX - 680).abs() < (playerX - 1320).abs() ? 680.0 : 1320.0;
      if ((playerX - corridorX).abs() > 55) {
        return Offset(corridorX, 1500);
      }
      return Offset(corridorX, 1110);
    }

    for (final farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      final insideNow = farm.rect.contains(Offset(playerX, playerY));
      final destInside = farm.rect.contains(Offset(destX, destY));
      if (!insideNow && destInside) {
        if (playerY > farm.rect.top - 5 || playerX < farm.gateMinX || playerX > farm.gateMaxX) {
          return Offset(farm.gateCenter.dx, farm.rect.top - 18);
        }
      }
    }

    return _getStoreSmartWaypoint(playerX, playerY, destX, destY);
  }

  /// Market içindeki reyonların, açık kasaların, paketleme istasyonunun ve ofis masasının 3D engel sınırlarını döndürür
  List<Rect>? _obstacleCache;
  int _obstacleSig = -1;

  /// The obstacle list only changes when a shelf / register is unlocked or store level expands,
  /// so build it once and reuse it (it used to be rebuilt several times per frame per thief).
  List<Rect> _getStoreObstacleRects() {
    int sig = (storeLevel * 13) + unlockedCheckouts.length + 1;
    for (final sh in shelves) {
      sig = sig * 31 + (sh.isUnlocked ? 7 : 3);
      sig &= 0x3FFFFFFFFFFF;
    }
    if (_obstacleCache != null && sig == _obstacleSig) return _obstacleCache!;
    _obstacleSig = sig;
    return _obstacleCache = _buildStoreObstacleRects();
  }

  List<Rect> _buildStoreObstacleRects() {
    final List<Rect> obstacles = [
      // Sağ üst Kurye Paketleme İstasyonu (kasalardan ayrı özel paketleme bölgesi)
      Rect.fromLTRB(
        courierPackingDesk.left - 12,
        courierPackingDesk.top - 12,
        courierPackingDesk.right + 12,
        courierPackingDesk.bottom + 14,
      ),
      // Sağ üst bilgisayar masası
      computerDesk.inflate(10),
      // Trash can
      trashCan.inflate(12),
    ];

    // Sadece seviyesi açılmış kasalar fiziksel engel oluşturur (kilitli kasa alanları boş kalır!)
    for (int i = 0; i < unlockedCheckouts.length; i++) {
      final cRect = unlockedCheckouts[i];
      obstacles.add(
        Rect.fromLTRB(
          cRect.left - 24.0,
          248.0,
          cRect.right + 20.0,
          410.0,
        ),
      );
    }

    for (final shelf in shelves) {
      if (!shelf.isUnlocked) continue;
      // Duvara veya kilitli market sınırına (storeMinX / storeMaxX) yakın reyonların sınır tarafını kapatarak
      // müşterilerin ve karakterlerin reyon ile sınır arasındaki dar boşluğa sıkışmasını önle!
      // Reyonlar arasındaki dar dikey ve yatay koridorların (örn. Biber x=490 ile Süt x=540 arası 50px)
      // kapanmaması için yatay/dikey marginleri dar tutuyoruz.
      final double rawLeft = shelf.rect.left - 12.0;
      final double rawRight = shelf.rect.right + 12.0;
      final double left = (rawLeft - storeMinX < 34.0) ? min(storeMinX, 85.0) : rawLeft;
      final double right = (storeMaxX - rawRight < 34.0) ? max(storeMaxX, worldWidth - 85.0) : rawRight;
      final double top = shelf.rect.top - 22.0;
      final double bottom = shelf.rect.bottom + 12.0;
      obstacles.add(Rect.fromLTRB(left, top, right, bottom));
    }

    return obstacles;
  }

  bool _segmentIntersectsRect(Offset a, Offset b, Rect r) {
    if (max(a.dx, b.dx) <= r.left ||
        min(a.dx, b.dx) >= r.right ||
        max(a.dy, b.dy) <= r.top ||
        min(a.dy, b.dy) >= r.bottom) {
      return false;
    }

    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    double tMin = 0.0;
    double tMax = 1.0;

    if (dx.abs() < 1e-6) {
      if (a.dx <= r.left || a.dx >= r.right) return false;
    } else {
      final invDx = 1.0 / dx;
      double t1 = (r.left - a.dx) * invDx;
      double t2 = (r.right - a.dx) * invDx;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tMin = max(tMin, t1);
      tMax = min(tMax, t2);
      if (tMin >= tMax) return false;
    }

    if (dy.abs() < 1e-6) {
      if (a.dy <= r.top || a.dy >= r.bottom) return false;
    } else {
      final invDy = 1.0 / dy;
      double t1 = (r.top - a.dy) * invDy;
      double t2 = (r.bottom - a.dy) * invDy;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tMin = max(tMin, t1);
      tMax = min(tMax, t2);
      if (tMin >= tMax) return false;
    }

    return true;
  }

  bool _isSegmentClearOfObstacles(Offset a, Offset b, List<Rect> obstacles) {
    for (final obs in obstacles) {
      if (_segmentIntersectsRect(a, b, obs.deflate(2.5))) {
        return false;
      }
    }
    return true;
  }

  Offset _pushOutOfRect(Offset p, Rect r) {
    final dLeft = (p.dx - r.left).abs();
    final dRight = (r.right - p.dx).abs();
    final dTop = (p.dy - r.top).abs();
    final dBottom = (r.bottom - p.dy).abs();

    final minValidX = max(102.0, storeMinX + 8.0);
    final maxValidX = min(worldWidth - 102.0, storeMaxX - 8.0);

    double minD = dBottom;
    Offset out = Offset(p.dx.clamp(minValidX, maxValidX), r.bottom + 8);

    if (r.left - 8 >= minValidX && dLeft < minD) {
      minD = dLeft;
      out = Offset(r.left - 8, p.dy);
    }
    if (r.right + 8 <= maxValidX && dRight < minD) {
      minD = dRight;
      out = Offset(r.right + 8, p.dy);
    }
    if (r.top > 250 && dTop < minD) {
      minD = dTop;
      out = Offset(p.dx.clamp(minValidX, maxValidX), r.top - 8);
    }
    return out;
  }

  /// Reyonların ve kasaların içinden geçmeden koridorları takip eden en kısa ara hedefi hesaplar
  Offset _getStoreSmartWaypoint(double startX, double startY, double destX, double destY) {
    final start = Offset(startX, startY);
    final goal = Offset(destX, destY);

    if ((startY < 225 && destY < 225) || (startY > 995 && destY > 995)) {
      return goal;
    }

    final doorCenter = worldWidth / 2;
    Offset effectiveGoal = goal;

    // Market içinden dışarı (caddeye veya çiftliğe) çıkarken önce kapının iç ağzına yönel
    if (startY >= 230 && startY <= 985) {
      if (destY > 990 && (startX - doorCenter).abs() > 95 && startY < 955) {
        effectiveGoal = Offset(doorCenter, 965);
      } else if (destY < 228 && (startX - doorCenter).abs() > 95 && startY > 265) {
        effectiveGoal = Offset(doorCenter, 250);
      }
    }

    final obstacles = _getStoreObstacleRects();
    final minValidX = max(102.0, storeMinX + 8.0);
    final maxValidX = min(worldWidth - 102.0, storeMaxX - 8.0);

    // 1. Eğer karakter şu an kilitli alanın veya bir reyonun / engelin sınırının içindeyse, önce en yakın koridor kenarına çıkar!
    if (startY >= 235 && startY <= 980) {
      if (startX < minValidX) {
        return Offset(minValidX + 4, startY);
      }
      if (startX > maxValidX) {
        return Offset(maxValidX - 4, startY);
      }
    }
    for (final obs in obstacles) {
      if (obs.deflate(1.5).contains(start)) {
        return _pushOutOfRect(start, obs);
      }
    }

    // 2. Eğer hedef nokta yanlışlıkla bir engelin içindeyse, hedefi engelin dışına çek
    Offset safeGoal = effectiveGoal;
    if (safeGoal.dy >= 235 && safeGoal.dy <= 980) {
      safeGoal = Offset(safeGoal.dx.clamp(minValidX, maxValidX), safeGoal.dy);
    }
    for (final obs in obstacles) {
      if (obs.deflate(1.5).contains(safeGoal)) {
        safeGoal = _pushOutOfRect(safeGoal, obs);
      }
    }

    // 3. Başlangıç ile hedef arasında hiçbir reyon engeli yoksa doğrudan hedefe yürü!
    if (_isSegmentClearOfObstacles(start, safeGoal, obstacles)) {
      return safeGoal;
    }

    // 4. Reyonların etrafından dolaşan en kısa koridor yolunu (Visibility Graph Dijkstra) hesapla
    const double cornerOffset = 6.0;
    const double minNodeDist = 1.5;

    final List<Offset> nodes = [start, safeGoal];

    bool isPointValid(Offset pt) {
      if (pt.dx < minValidX || pt.dx > maxValidX || pt.dy < 238 || pt.dy > 978) {
        return false;
      }
      for (final obs in obstacles) {
        if (obs.deflate(1.0).contains(pt)) return false;
      }
      return true;
    }

    void tryAddWaypoint(Offset pt) {
      if ((pt - start).distance < minNodeDist) return;
      if (!isPointValid(pt)) return;
      for (final existing in nodes) {
        if ((existing - pt).distance < 4.0) return;
      }
      nodes.add(pt);
    }

    for (final obs in obstacles) {
      tryAddWaypoint(Offset(obs.left - cornerOffset, obs.top - cornerOffset));
      tryAddWaypoint(Offset(obs.right + cornerOffset, obs.top - cornerOffset));
      tryAddWaypoint(Offset(obs.left - cornerOffset, obs.bottom + cornerOffset));
      tryAddWaypoint(Offset(obs.right + cornerOffset, obs.bottom + cornerOffset));
      tryAddWaypoint(Offset(obs.center.dx, obs.top - cornerOffset));
      tryAddWaypoint(Offset(obs.center.dx, obs.bottom + cornerOffset));
      tryAddWaypoint(Offset(obs.left - cornerOffset, obs.center.dy));
      tryAddWaypoint(Offset(obs.right + cornerOffset, obs.center.dy));
    }

    // Ana market koridor kavşak noktaları
    const aisleHubs = [
      Offset(1000, 290), // Ön giriş koridoru
      Offset(1000, 488), // Orta koridor - Kasa koridoru kavşağı
      Offset(840, 488),  // Kasa koridoru doğu ucu
      Offset(720, 488),  // Sol-orta reyon üst kavşağı
      Offset(610, 488),  // Kasa 1 önü / Süt dolabı üstü
      Offset(610, 745),  // Süt dolabı ile Yumurta reyonu arası yatay koridor
      Offset(610, 955),  // Yumurta reyonu altı
      Offset(740, 620),  // Süt dolabı sağ koridoru
      Offset(740, 745),  // Orta-sol ara kavşak
      Offset(740, 860),  // Yumurta reyonu sağ koridoru
      Offset(740, 955),  // Sol-alt koridor kavşağı
      Offset(505, 500),  // Biber-Süt arası üst geçiş
      Offset(505, 620),  // Biber-Süt arası orta geçiş
      Offset(505, 745),  // Biber-Yumurta arası kavşak
      Offset(505, 955),  // Sol alt geçiş
      Offset(380, 488),  // Sol reyon koridoru üst kavşağı
      Offset(380, 725),  // Sol reyon koridoru orta kavşağı
      Offset(380, 948),  // Sol reyon koridoru alt kavşağı
      Offset(1000, 620), // Orta ana koridor üst
      Offset(1000, 725), // Orta ana koridor orta
      Offset(1000, 840), // Orta ana koridor alt
      Offset(1000, 955), // Arka kapı iç kavşağı
      Offset(1115, 620), // Un reyonu sol koridoru
      Offset(1115, 725), // Un-Domates arası sol kavşak
      Offset(1115, 840), // Domates reyonu sol koridoru
      Offset(1255, 495), // Un reyonu üstü
      Offset(1255, 725), // Un ile Domates reyonu arası yatay koridor
      Offset(1255, 925), // Domates reyonu altı
      Offset(1395, 275), // Kurye paketleme üst geçişi
      Offset(1435, 488), // Sağ reyon koridoru üst
      Offset(1435, 620), // Un-Elma arası koridor
      Offset(1435, 725), // Sağ reyon koridoru orta
      Offset(1435, 925), // Sağ reyon koridoru alt
      Offset(1600, 488), // Elma reyonu üstü
      Offset(1600, 725), // Elma reyonu altı
    ];
    for (final hub in aisleHubs) {
      tryAddWaypoint(hub);
    }

    final int n = nodes.length;
    final List<double> dist = List.filled(n, double.infinity);
    final List<int> parent = List.filled(n, -1);
    final List<bool> visited = List.filled(n, false);
    dist[0] = 0.0;

    for (int step = 0; step < n; step++) {
      int u = -1;
      double bestD = double.infinity;
      for (int i = 0; i < n; i++) {
        if (!visited[i] && dist[i] < bestD) {
          bestD = dist[i];
          u = i;
        }
      }
      if (u == -1 || u == 1) break;
      visited[u] = true;

      for (int v = 1; v < n; v++) {
        if (visited[v]) continue;
        final d = (nodes[u] - nodes[v]).distance;
        if (dist[u] + d >= dist[v]) continue;
        if (_isSegmentClearOfObstacles(nodes[u], nodes[v], obstacles)) {
          dist[v] = dist[u] + d;
          parent[v] = u;
        }
      }
    }

    if (parent[1] != -1) {
      int cur = 1;
      while (parent[cur] != -1 && parent[cur] != 0) {
        cur = parent[cur];
      }
      return nodes[cur];
    }

    return safeGoal;
  }

  /// Kasada bekleyen müşterilerin alttaki reyonların içine taşmadan koridor boyunca dizilmesini sağlar
  Offset _getCheckoutQueueSlot(int checkoutIdx, int queueIndex) {
    final idx = checkoutIdx.clamp(0, unlockedCheckoutCount - 1);
    final counterRect = checkoutCounters[idx];
    final clamped = queueIndex.clamp(0, 6);
    if (clamped <= 2) {
      return Offset(
        counterRect.center.dx + 10,
        counterRect.bottom + 20.0 + (clamped * 28.0),
      );
    } else {
      return Offset(
        counterRect.center.dx + 10 + ((clamped - 2) * 34.0),
        counterRect.bottom + 76.0,
      );
    }
  }

  void _updatePlayer(double dt) {
    double dx = moveDirX;
    double dy = moveDirY;

    if (targetMoveX != null && targetMoveY != null) {
      final totalDist = sqrt(pow(targetMoveX! - playerX, 2) + pow(targetMoveY! - playerY, 2));
      if (totalDist <= 10) {
        targetMoveX = null;
        targetMoveY = null;
        dx = 0;
        dy = 0;
      } else {
        _wpTimer -= dt;
        if (_cachedWp == null ||
            _wpTimer <= 0 ||
            _wpTx != targetMoveX ||
            _wpTy != targetMoveY ||
            (Offset(playerX, playerY) - _cachedWp!).distance < 6) {
          _cachedWp = _getSmartWaypoint(targetMoveX!, targetMoveY!);
          _wpTimer = 0.1;
          _wpTx = targetMoveX;
          _wpTy = targetMoveY;
        }
        final wp = _cachedWp!;
        double tdx = wp.dx - playerX;
        double tdy = wp.dy - playerY;
        double dist = sqrt(tdx * tdx + tdy * tdy);
        if (dist > 2.0) {
          dx = tdx / dist;
          dy = tdy / dist;
        }
      }
    }

    // Smooth walking: accelerate / decelerate instead of instant start & stop
    double speedScale = 1.0;
    if (targetMoveX != null && targetMoveY != null) {
      final remaining = sqrt(pow(targetMoveX! - playerX, 2) + pow(targetMoveY! - playerY, 2)).toDouble();
      speedScale = (remaining / 70.0).clamp(0.4, 1.0).toDouble();
    }
    final wantVX = dx * playerSpeed * speedScale;
    final wantVY = dy * playerSpeed * speedScale;
    final bool wantsMove = dx != 0 || dy != 0;
    final double accel = (wantsMove ? 1250.0 : 1700.0) * dt;
    velX += (wantVX - velX).clamp(-accel, accel).toDouble();
    velY += (wantVY - velY).clamp(-accel, accel).toDouble();
    if (!wantsMove && playerSpeedNow < 8) {
      velX = 0;
      velY = 0;
    }
    if (velX == 0 && velY == 0) return;

    final double stepX = velX * dt;
    final double stepY = velY * dt;
    bool moved = false;

    if (_canMoveTo(playerX + stepX, playerY)) {
      playerX += stepX;
      moved = true;
    } else {
      velX = 0;
    }
    if (_canMoveTo(playerX, playerY + stepY)) {
      playerY += stepY;
      moved = true;
    } else {
      velY = 0;
    }

    final double travelled = sqrt(stepX * stepX + stepY * stepY);
    if (moved && travelled > 0) {
      walkAnimTime += travelled * 0.055;
      _stepDist += travelled;
      if (_stepDist >= 36) {
        _stepDist = 0;
        _sfx('step');
      }
      if (playerSpeedNow > 25) {
        playerAngle = atan2(velY, velX);
        // 4-way facing with hysteresis so diagonal walking does not flicker
        final ax = velX.abs();
        final ay = velY.abs();
        final bool horizontalNow = playerFacing == 1 || playerFacing == 2;
        final bool goHorizontal = horizontalNow ? ax * 1.3 > ay : ax > ay * 1.3;
        if (goHorizontal) {
          playerFacing = velX < 0 ? 1 : 2;
        } else {
          playerFacing = velY < 0 ? 3 : 0;
        }
      }
    }

    if (!moved && targetMoveX != null) {
      targetMoveX = null;
      targetMoveY = null;
    }
  }

  void _updateTruck(double dt) {
    if (!isTruckArriving) return;

    if (truckX < truckTargetX) {
      truckX += 380 * dt;
      if (Random().nextDouble() < 0.3) {
        spawnParticle(truckX - 10, 92, '💨', Colors.white54, size: 12);
      }
    } else {
      for (int i = 0; i < incomingShipment.length; i++) {
        final pType = incomingShipment[i];
        final def = productCatalog[pType]!;
        final boxX = worldWidth / 2 - 116 + (i % 5) * 58.0;
        final boxY = 925.0 - (i ~/ 5) * 46.0;
        _sfx('truck');
        deliveryBoxes.add(
          DeliveryBox(
            id: 'box_${DateTime.now().microsecondsSinceEpoch}_$i',
            productType: pType,
            currentCount: def.boxSize,
            maxCount: def.boxSize,
            x: boxX,
            y: boxY,
          ),
        );
        spawnParticle(boxX, boxY - 20, 'Delivery!', Colors.amberAccent, size: 14);
      }
      showToast('Delivery arrived at the BACK DOOR (south)!', kind: 1, seconds: 5.0);
      incomingShipment.clear();
      isTruckArriving = false;
      truckX = -260;
    }
  }

  void _updateParticles(double dt) {
    for (int i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;
      if (p.life <= 0) {
        particles.removeAt(i);
      }
    }
  }

  void _updateCustomers(double dt) {
    customerSpawnTimer -= dt;
    if (customerSpawnTimer <= 0 &&
        customers.length < min(2 + storeLevel + (day ~/ 4), 7) &&
        phaseTimeLeft > 12) {
      _spawnCustomer();
      // Relaxed at the start, a bit busier every day
      customerSpawnTimer = max(8.0, 16.0 - day * 0.6) + Random().nextInt(7);
      _sfx('bell');
    }

    for (int i = customers.length - 1; i >= 0; i--) {
      final c = customers[i];
      _processCustomerAI(c, dt);

      if ((c.state == CustomerState.leavingHappy || c.state == CustomerState.leavingSad) && c.y <= 55) {
        customers.removeAt(i);
      }
    }
  }

  void _spawnCustomer() {
    final random = Random();
    final availableProducts = List<SimProductType>.from(unlockedProducts);
    if (availableProducts.isEmpty) return;

    // Zengin ve çeşitli müşteri tipleri (Her birinin kendine has görünümü, hızı ve alışveriş tercihi var!)
    final roll = random.nextDouble();
    CustomerArchetype archetype;
    String name;
    String avatar;
    bool isVip = false;
    int desiredCount = 2;

    if (roll < 0.14) {
      archetype = CustomerArchetype.vip;
      isVip = true;
      const vipNames = ['👑 Gourmet Vedat', '👑 VIP Elif', '👑 Businessman Bora', '👑 Collector Selim'];
      name = vipNames[random.nextInt(vipNames.length)];
      avatar = '👑';
      desiredCount = 3;
    } else if (roll < 0.30) {
      archetype = CustomerArchetype.chef;
      const chefNames = ['👨‍🍳 Chef Danilo', '👩‍🍳 Pastry Chef Seda', '👨‍🍳 Master Cook Murat', '👩‍🍳 Gourmet Chef Zeynep'];
      name = chefNames[random.nextInt(chefNames.length)];
      avatar = '👨‍🍳';
      desiredCount = 3;
    } else if (roll < 0.46) {
      archetype = CustomerArchetype.grandma;
      const elderNames = ['👵 Granny Hayriye', '👴 Retired Grandpa İhsan', '👵 Kind Granny Fatma', '👴 Uncle Rıza'];
      name = elderNames[random.nextInt(elderNames.length)];
      avatar = name.startsWith('👴') ? '👴' : '👵';
      desiredCount = 2;
    } else if (roll < 0.62) {
      archetype = CustomerArchetype.athlete;
      const athleteNames = ['🏃 Athlete Berk', '🏃 Runner Pelin', '🏋️ Trainer Kaan', '🚴 Cyclist Ece'];
      name = athleteNames[random.nextInt(athleteNames.length)];
      avatar = '🏃';
      desiredCount = 2;
    } else if (roll < 0.78) {
      archetype = CustomerArchetype.student;
      const studentNames = ['🎒 Student Emre', '🎧 College Student Doğa', '📚 Intern Mert', '🎒 Student Sıla'];
      name = studentNames[random.nextInt(studentNames.length)];
      avatar = '🎒';
      desiredCount = 1 + random.nextInt(2);
    } else if (roll < 0.90) {
      archetype = CustomerArchetype.family;
      const familyNames = ['👩‍👧 Mom Ayşe & Efe', '👨‍👩‍👧 The Yılmaz Family', '👩‍👦 Ms. Sevgi', '👨‍👧 Mr. Kemal & Daughter'];
      name = familyNames[random.nextInt(familyNames.length)];
      avatar = '👩‍👧';
      desiredCount = 3;
    } else {
      archetype = CustomerArchetype.regular;
      const regNames = ['👩 Ms. Selin', '👨 Mr. Mehmet', '🧔 Uncle Ali', '👩‍🦰 Teacher Zeynep'];
      name = regNames[random.nextInt(regNames.length)];
      avatar = '🛒';
      desiredCount = 1 + random.nextInt(3);
    }

    availableProducts.shuffle();
    final listCount = min(availableProducts.length, desiredCount);
    final shoppingList = availableProducts.take(listCount).toList();

    // En az kuyruğu olan açık kasayı seç (Seviye 1 -> Kasa 1, Seviye 2 -> Kasa 1-2, Seviye 3 -> Kasa 1-2-3)
    int bestCheckout = 0;
    int minQueue = 999;
    final maxCheckouts = unlockedCheckoutCount;
    for (int i = 0; i < maxCheckouts; i++) {
      final qCount = customers
          .where((other) =>
              (other.state == CustomerState.goingToCheckout ||
                  other.state == CustomerState.waitingAtCheckout) &&
              other.checkoutIndex == i)
          .length;
      if (qCount < minQueue) {
        minQueue = qCount;
        bestCheckout = i;
      }
    }

    final newCustomer = SimCustomer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        avatar: avatar,
        archetype: archetype,
        x: worldWidth / 2,
        y: 25,
        shoppingList: shoppingList,
        isVip: isVip,
        checkoutIndex: bestCheckout,
      );
    // customers get less patient as the days go by
    newCustomer.maxPatience *= 1.0 - 0.35 * difficulty;
    newCustomer.patience = newCustomer.maxPatience;
    customers.add(newCustomer);
  }

  void _processCustomerAI(SimCustomer c, double dt) {
    final double speed = 78.0 * c.speedMultiplier;
    final doorCenter = worldWidth / 2;

    switch (c.state) {
      case CustomerState.walkingToEntrance:
        _moveCustomerTowards(c, doorCenter, 295, speed, dt);
        if (c.y >= 285) {
          c.state = CustomerState.shopping;
          c.currentShoppingIndex = 0;
        }
        break;

      case CustomerState.shopping:
        if (c.currentShoppingIndex >= c.shoppingList.length) {
          if (c.basket.isNotEmpty) {
            // Kasaya giderken o an en boş olan açık kasaya yönelsin
            int bestCheckout = 0;
            int minQueue = 999;
            for (int i = 0; i < unlockedCheckoutCount; i++) {
              final qCount = customers
                  .where((other) =>
                      other != c &&
                      (other.state == CustomerState.goingToCheckout ||
                          other.state == CustomerState.waitingAtCheckout) &&
                      other.checkoutIndex == i)
                  .length;
              if (qCount < minQueue) {
                minQueue = qCount;
                bestCheckout = i;
              }
            }
            c.checkoutIndex = bestCheckout;
            c.state = CustomerState.goingToCheckout;
          } else {
            c.state = CustomerState.leavingSad;
          }
          break;
        }

        final wanted = c.shoppingList[c.currentShoppingIndex];
        final shelf = shelves.firstWhere((s) => s.assignedProduct == wanted, orElse: () => shelves.first);

        // Aynı reyona gelen müşteriler üst üste binip sıkışmasın diye hafif yatay slot farkı ver
        final double slotSpread = ((c.id.hashCode.abs() % 5) - 2) * 10.0;
        double targetX = shelf.rect.center.dx + slotSpread;
        double targetY = shelf.rect.bottom + 24;

        _moveCustomerTowards(c, targetX, targetY, speed, dt);

        if ((c.x - targetX).abs() < 24 && (c.y - targetY).abs() < 24) {
          if (shelf.isUnlocked && shelf.currentStock > 0) {
            final prevTimer = c.shelfGrabTimer;
            c.shelfGrabTimer += dt;
            shelf.doorOpenProgress = (shelf.doorOpenProgress + dt * 5.0).clamp(0.0, 1.0);

            // Kapak açıldıktan hemen sonra (0.22 sn'de) ürünü raftan sepete uçur!
            if (prevTimer < 0.22 && c.shelfGrabTimer >= 0.22) {
              if (shelf.currentStock > 0) {
                final slotPos = getShelfItemSlotPos(shelf, shelf.currentStock - 1);
                shelf.currentStock--;
                shelf.lastPlacedBounceTimer = 0.75;
                c.basket.add(wanted);
                flyingShelfItems.add(
                  ShelfFlyingItem(
                    productType: wanted,
                    startPos: slotPos,
                    endPos: Offset(c.x + 12, c.y - 14),
                    duration: 0.24,
                  ),
                );
                spawnParticle(targetX, targetY - 25, '-1 ${productCatalog[wanted]!.emoji}', Colors.orangeAccent);
              } else {
                spawnParticle(targetX, targetY - 25, '❌ Out of Stock', Colors.redAccent);
              }
            }

            if (c.shelfGrabTimer >= 0.48) {
              c.shelfGrabTimer = 0.0;
              c.currentShoppingIndex++;
            }
          } else {
            c.shelfGrabTimer = 0.0;
            spawnParticle(targetX, targetY - 25, '❌ Out of Stock', Colors.redAccent);
            c.currentShoppingIndex++;
          }
        } else {
          c.shelfGrabTimer = 0.0;
        }
        break;

      case CustomerState.goingToCheckout:
        final idx = c.checkoutIndex.clamp(0, unlockedCheckoutCount - 1);
        final waitingList = customers
            .where((other) =>
                other.state == CustomerState.waitingAtCheckout &&
                other.checkoutIndex.clamp(0, unlockedCheckoutCount - 1) == idx)
            .toList();
        final queueIndex = waitingList.indexOf(c);
        final clampedIndex = (queueIndex == -1 ? waitingList.length : queueIndex).clamp(0, 5);
        final slot = _getCheckoutQueueSlot(idx, clampedIndex);

        double targetX = slot.dx;
        double targetY = slot.dy;
        _moveCustomerTowards(c, targetX, targetY, speed, dt);

        if ((c.x - targetX).abs() < 18 && (c.y - targetY).abs() < 18) {
          c.state = CustomerState.waitingAtCheckout;
          c.waitTimer = 0.0;
          final regNo = c.checkoutIndex + 1;
          showToast('Customer waiting at Register $regNo!', kind: 0);
          spawnParticle(c.x, c.y - 56, 'Waiting!', Colors.amberAccent, size: 14);
        }
        break;

      case CustomerState.waitingAtCheckout:
        if (c.basket.isEmpty) {
          c.state = CustomerState.leavingSad;
          break;
        }

        // Patience: the longer they wait at the register, the angrier they get
        final bool beingServed = hasAutoCashier && customers
                .where((o) =>
                    o.state == CustomerState.waitingAtCheckout &&
                    o.checkoutIndex == c.checkoutIndex)
                .firstOrNull == c;
        if (!beingServed) {
          c.patience -= dt;
          if (c.patience <= 0) {
            c.state = CustomerState.leavingSad;
            spawnParticle(c.x, c.y - 50, 'Too slow! Leaving...', Colors.redAccent, size: 13);
            _sfx('error');
            break;
          }
        }

        // Poşete ürün koyma uçuş animasyonunu ilerlet
        if (c.baggingProduct != null) {
          c.baggingAnimTimer += dt * 2.5;
          if (c.baggingAnimTimer >= 1.0) {
            c.baggingAnimTimer = 0.0;
            c.baggingProduct = null;
          }
        }

        // Öndeki müşteri kasadan ayrıldıkça sıradaki her müşteri bir adım İLERİ yürüsün!
        final idx = c.checkoutIndex.clamp(0, unlockedCheckoutCount - 1);
        final waitingList = customers
            .where((other) =>
                other.state == CustomerState.waitingAtCheckout &&
                other.checkoutIndex.clamp(0, unlockedCheckoutCount - 1) == idx)
            .toList();
        final queueIndex = waitingList.indexOf(c).clamp(0, 5);
        final slot = _getCheckoutQueueSlot(idx, queueIndex);
        final double slotX = slot.dx;
        final double slotY = slot.dy;

        if ((c.x - slotX).abs() > 2.0 || (c.y - slotY).abs() > 2.0) {
          _moveCustomerTowards(c, slotX, slotY, speed * 0.92, dt);
        }

        // Kasiyer Ayşe işe alınmışsa sadece sıranın en önündeki (queueIndex == 0) müşterinin ürünlerini tek tek poşetler
        if (hasAutoCashier && queueIndex == 0) {
          c.waitTimer += dt;
          if (c.waitTimer >= 0.75) {
            c.waitTimer = 0.0;
            packNextItemOrCheckout(c);
          }
        }
        break;

      case CustomerState.leavingHappy:
      case CustomerState.leavingSad:
        if (c.y > 240) {
          _moveCustomerTowards(c, doorCenter, 232, speed, dt);
        } else {
          _moveCustomerTowards(c, doorCenter, -40, speed, dt);
        }
        break;
    }
  }

  void _moveCustomerTowards(SimCustomer c, double targetX, double targetY, double speed, double dt) {
    c.wpTimer -= dt;
    if (c.wpCache == null ||
        c.wpTimer <= 0 ||
        (c.wpGx - targetX).abs() > 1.5 ||
        (c.wpGy - targetY).abs() > 1.5 ||
        (Offset(c.x, c.y) - c.wpCache!).distance < 6.0) {
      c.wpCache = _getStoreSmartWaypoint(c.x, c.y, targetX, targetY);
      c.wpGx = targetX;
      c.wpGy = targetY;
      c.wpTimer = 0.16;
    }

    // Sıkışma algılayıcı: müşteri yürümeye çalışırken yerinden oynamıyorsa ara hedefi yenile veya engelden dışarı it
    final movedSinceLast = (c.x - c.lastMoveX).abs() + (c.y - c.lastMoveY).abs();
    c.lastMoveX = c.x;
    c.lastMoveY = c.y;
    if (movedSinceLast < 0.15 && (Offset(c.x, c.y) - Offset(targetX, targetY)).distance > 18) {
      c.stuckTimer += dt;
      if (c.stuckTimer > 0.35) {
        c.stuckTimer = 0.0;
        for (final obs in _getStoreObstacleRects()) {
          if (obs.inflate(4).contains(Offset(c.x, c.y))) {
            final pushed = _pushOutOfRect(Offset(c.x, c.y), obs.inflate(4));
            c.x = pushed.dx;
            c.y = pushed.dy;
            break;
          }
        }
        c.wpCache = _getStoreSmartWaypoint(c.x, c.y, targetX, targetY);
        c.wpTimer = 0.22;
      }
    } else {
      c.stuckTimer = 0.0;
    }

    final wp = c.wpCache!;
    double dx = wp.dx - c.x;
    double dy = wp.dy - c.y;
    double dist = sqrt(dx * dx + dy * dy);

    if (dist > 0.5) {
      double step = speed * dt;
      if (step >= dist) {
        c.x = wp.dx;
        c.y = wp.dy;
      } else {
        c.x += (dx / dist) * step;
        c.y += (dy / dist) * step;
      }
      c.walkAngle = atan2(dy, dx);
    }
  }

  void collectFromFarm(FarmProducer farm) {
    startAutoFarmHarvest(farm);
  }

  void _checkInteractions() {
    activeInteractionText = null;
    activeInteractionAction = null;

    final playerPos = Offset(playerX, playerY);

    // 🛵 Kurye Durağı Etkileşimi
    if (courierStation.inflate(65).contains(playerPos)) {
      if (courierState == CourierState.waitingForOrder && activeCourierOrder != null) {
        final order = activeCourierOrder!;
        final def = productCatalog[order.productType]!;
        if (carriedBox != null && carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          activeInteractionText =
              '🛵 📦 Deliver Courier Package: ${order.deliveredQty}/${order.requiredQty} ${def.emoji} (+\$${order.rewardAmount.toStringAsFixed(0)}) [E / Click]';
        } else if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          activeInteractionText =
              '⚠️ The Courier Will Not Take Open Items! Make a 📦 Courier Package at the Packing Table First! [E / Click]';
        } else {
          activeInteractionText =
              '🛵 Courier Order: ${order.requiredQty}x ${def.emoji} ${def.name} (Pack & Bring First! Reward: +\$${order.rewardAmount.toStringAsFixed(0)}) [E / Click]';
        }
        activeInteractionAction = () {
          deliverToCourier();
        };
      } else {
        activeInteractionText = '🛵 Express Courier Stop (New Order on the Way...)';
      }
      return;
    }

    // 📦 Kurye Sipariş Paketleme İstasyonu Etkileşimi
    if (courierPackingDesk.inflate(62).contains(playerPos)) {
      if (courierState == CourierState.waitingForOrder && activeCourierOrder != null) {
        final order = activeCourierOrder!;
        final def = productCatalog[order.productType]!;
        if (carriedBox != null && carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          activeInteractionText =
              '✅ 📦 Courier Package in Hand! Take It to the Bike & Deliver! [E / Click]';
          activeInteractionAction = () {
            deliverToCourier();
          };
        } else if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          final total = courierStagedCount + carriedBox!.currentCount;
          if (total > order.remainingQty) {
            final excess = total - order.remainingQty;
            activeInteractionText =
                '⚠️ Too many! The courier wants ${order.remainingQty} ${def.emoji} ($excess extra!) — Open Packing [E / Click]';
          } else {
            activeInteractionText =
                '📦 ${def.emoji} ${def.name} Packing ($total/${order.remainingQty}) [E / Click]';
          }
          activeInteractionAction = () {
            handleCourierPackingDeskClick();
          };
        } else if (courierStagedCount > 0) {
          if (courierStagedCount >= order.remainingQty) {
            final pct = (courierPackingProgress * 100).toInt().clamp(0, 100);
            activeInteractionText =
                '📦 ${def.emoji} ${def.name} Courier Package Being Taped... $pct% ($courierStagedCount/${order.requiredQty})';
          } else {
            final rem = order.remainingQty - courierStagedCount;
            activeInteractionText =
                '📦 On the Table $courierStagedCount/${order.remainingQty} ${def.emoji} Ready (bring $rem more!) [E / Click]';
            activeInteractionAction = () {
              handleCourierPackingDeskClick();
            };
          }
        } else {
          activeInteractionText =
              '📦 Courier Packing Station: ${order.requiredQty}x ${def.emoji} ${def.name} Take from the Cabinet & Pack [E / Click]';
          activeInteractionAction = () {
            handleCourierPackingDeskClick();
          };
        }
      } else {
        activeInteractionText = '📦 Courier Packing Station (Pack Here When a Courier Order Arrives)';
      }
      return;
    }

    if ((playerPos - computerDesk.center).distance < 110) {
      activeInteractionText = '💻 Store Computer (Order Stock)';
      activeInteractionAction = () {};
      return;
    }

    // 🛎️ Açık Kasa Tezgahları Etkileşimi (Sadece Müşteri Ödemesi! Kasada kurye paketi YAPILMAZ!)
    for (int i = 0; i < checkoutCounters.length; i++) {
      final cRect = checkoutCounters[i];
      if ((playerPos - cRect.center).distance < 125) {
        if (i >= unlockedCheckoutCount) {
          activeInteractionText = '🔒 🛎️ Register ${i + 1} Locked (Unlocks at Store Level ${i + 1})';
          return;
        }
        activePlayerCheckoutIndex = i;
        final waiting = customers
            .where((c) =>
                c.state == CustomerState.waitingAtCheckout &&
                c.checkoutIndex.clamp(0, unlockedCheckoutCount - 1) == i)
            .toList();
        final cust = waiting.isNotEmpty ? waiting.first : null;

        if (cust != null) {
          if (!cust.isFullyPacked) {
            final nextProd = productCatalog[cust.basket[cust.packedCount]]!;
            activeInteractionText =
                '🔊 Register ${i + 1}: Scan & Bag ${nextProd.emoji} ${nextProd.name} (${cust.packedCount}/${cust.basket.length}) [E / Click]';
          } else {
            activeInteractionText =
                '💵 Register ${i + 1}: Hand Over Package & Take Payment (${cust.name}) [E / Click]';
          }
          activeInteractionAction = () {
            packNextItemOrCheckout(cust);
          };
        } else if (courierState == CourierState.waitingForOrder &&
            activeCourierOrder != null &&
            carriedBox != null &&
            !carriedBox!.isCourierPackage &&
            carriedBox!.productType == activeCourierOrder!.productType) {
          activeInteractionText =
              '🚫 Register ${i + 1}: No courier packages at the register! Go to the 📦 Courier Packing Station on the right!';
          activeInteractionAction = null;
        } else {
          activeInteractionText = hasAutoCashier
              ? '🛎️ Register ${i + 1} Counter (Cashier on Duty - $unlockedCheckoutCount/3 Registers Open)'
              : '🛎️ Register ${i + 1} Counter (Scan Items at the Barcode When a Customer Arrives)';
          activeInteractionAction = null;
        }
        return;
      }
    }

    if ((playerPos - trashCan.center).distance < 80 && (carriedBox != null || playerTool != null)) {
      activeInteractionText = carriedBox != null ? '🗑️ Empty / Drop Held Item' : '🗑️ Drop Held Equipment';
      activeInteractionAction = () {
        spawnParticle(trashCan.center.dx, trashCan.center.dy, '🗑️ Dropped', Colors.grey);
        carriedBox = null;
        playerTool = null;
      };
      return;
    }

    // 🧀 Peynir Yapma Makinesi Etkileşimi (Yaklaşınca Otomatik Süt Döker veya Hazır Peyniri Alır!)
    if (isCheeseUnlocked && cheeseMachineRect.inflate(58).contains(playerPos)) {
      if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == SimProductType.milk) {
        interactWithCheeseMachine();
        return;
      } else if (carriedBox == null && cheeseMachineReadyBoxes > 0) {
        interactWithCheeseMachine();
        return;
      } else if (cheeseMachineMilkInput > 0) {
        final pct = ((cheeseMachineTimer / cheeseMachineDuration) * 100).toInt().clamp(0, 100);
        activeInteractionText = '⏳ Cheese Machine Running... $pct%';
      } else {
        activeInteractionText = '🧀 Cheese Machine: Bring Milk from the Barn!';
        activeInteractionAction = () {
          interactWithCheeseMachine();
        };
      }
      return;
    }

    // 🧺🌾 Çiftlik Alet Standları (Tıklayınca veya [E] basınca ekipmanı alıp içeri girer)
    for (var farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if ((playerPos - farm.toolStandPos).distance < 58) {
        activeInteractionText =
            '${farm.requiredTool.emoji} Take ${farm.requiredTool.name} & Go Inside [E / Click]';
        activeInteractionAction = () {
          startAutoFarmHarvest(farm);
        };
        return;
      }
    }

    // 🐄🌾🐔🍎🍅🌶️🥖 Çiftlik Alanları Etkileşimi
    for (var farm in farmProducers) {
      if (farm.rect.inflate(45).contains(playerPos)) {
        if (!farm.isUnlocked) {
          final shelf = shelfForProduct(farm.primaryProduct);
          if (shelf != null) {
            activeInteractionText = '🔒 ${farm.name}: ${shelfLockReason(shelf)} [E / Click]';
            activeInteractionAction = () {
              tryUnlockShelfOrFarm(shelf, feedbackPos: farm.rect.center);
            };
          }
          return;
        }
        if (carriedBox != null &&
            (!_isProductFromFarm(carriedBox!.productType, farm) ||
                carriedBox!.currentCount >= carriedBox!.maxCount ||
                carriedBox!.isCourierPackage)) {
          activeInteractionText = '⚠️ You are holding items! Take them to the store shelf (or the Packing Table)!';
          return;
        }

        if (playerTool != farm.requiredTool) {
          activeInteractionText =
              '${farm.requiredTool.emoji} Take the ${farm.requiredTool.name} at the Entrance First! (Click / [E])';
          activeInteractionAction = () {
            startAutoFarmHarvest(farm);
          };
          return;
        }

        if (activeHarvestSpot != null) {
          final pct = (activeHarvestSpot!.harvestProgress * 100).toInt().clamp(0, 100);
          activeInteractionText =
              '${farm.requiredTool.emoji} ${farm.requiredTool.actionVerb}... %$pct';
          return;
        }

        if (farm.readySpotCount > 0) {
          final def = productCatalog[farm.primaryProduct]!;
          String actionDesc = 'Go Inside & Milk the Cow';
          if (farm.zoneType == FarmZoneType.field) {
            actionDesc = 'Go Inside & Harvest ${def.emoji} ${def.name}';
          } else if (farm.zoneType == FarmZoneType.coop) {
            actionDesc = 'Enter the Coop & Collect Eggs in the Bucket';
          }
          activeInteractionText =
              '${farm.requiredTool.emoji} $actionDesc (${farm.readySpotCount} Ready Spots)';
          activeInteractionAction = () {
            startAutoFarmHarvest(farm);
          };
        } else {
          activeInteractionText = '⏳ ${farm.name}: Growing Back...';
        }
        return;
      }
    }

    for (var shelf in shelves) {
      if (shelf.rect.inflate(48).contains(playerPos)) {
        final def = productCatalog[shelf.assignedProduct]!;

        if (!shelf.isUnlocked) {
          activeInteractionText = '🔒 ${def.emoji} ${shelf.name}: ${shelfLockReason(shelf)} [E / Click]';
          activeInteractionAction = () {
            tryUnlockShelfOrFarm(shelf, feedbackPos: shelf.rect.center);
          };
          return;
        }

        if (carriedBox != null) {
          if (carriedBox!.isCourierPackage) {
            activeInteractionText = '🛵 Hand the Courier Package in Your Hand to the Bike!';
          } else if (carriedBox!.productType == shelf.assignedProduct) {
            if (carriedBox!.isPickedFromShelf) {
              if (shelf.currentStock > 0 && carriedBox!.currentCount < carriedBox!.maxCount) {
                activeInteractionText =
                    '🖐️ Take +1 ${def.emoji} ${def.name} (In Hand: ${carriedBox!.currentCount}/${carriedBox!.maxCount}) • Stock: ${shelf.currentStock} [E / Click]';
                activeInteractionAction = () {
                  takeOneFromShelf(shelf);
                };
              } else {
                activeInteractionText =
                    '🖐️ You Are Holding ${carriedBox!.currentCount}x ${def.emoji} ${def.name}';
              }
            } else if (shelf.currentStock < shelf.maxCapacity) {
              activeInteractionText =
                  '✨ Stacking ${def.emoji} ${def.name} on the Shelf One by One... (${shelf.currentStock}/${shelf.maxCapacity})';
              activeInteractionAction = () {
                _stockShelf(shelf);
              };
            } else {
              activeInteractionText = '✅ ${def.name} Shelf Is Completely Full!';
            }
          } else {
            activeInteractionText = '❌ Wrong Shelf! This Shelf: ${def.emoji} ${def.name}';
          }
        } else {
          if (shelf.currentStock > 0) {
            activeInteractionText =
                '🖐️ ${def.emoji} ${shelf.name} (Take 1) • Stock: ${shelf.currentStock}/${shelf.maxCapacity} [E / Click]';
            activeInteractionAction = () {
              takeOneFromShelf(shelf);
            };
          } else {
            activeInteractionText = '❌ ${def.emoji} ${shelf.name}: Out of Stock (0/${shelf.maxCapacity})';
          }
        }
        return;
      }
    }

    if (carriedBox == null) {
      for (var box in deliveryBoxes) {
        if ((playerPos - Offset(box.x, box.y)).distance < 58) {
          final def = productCatalog[box.productType]!;
          activeInteractionText = '{hand} Pick up ${def.name} box (${box.currentCount})';
          activeInteractionAction = () {
            if (carriedBox != null || !deliveryBoxes.contains(box)) return;
            carriedBox = CarriedBox(
              productType: box.productType,
              currentCount: box.currentCount,
              maxCount: box.maxCount,
            );
            _sfx('pickup');
            spawnParticle(playerX, playerY - 35, 'Box picked up', Colors.amberAccent);
            deliveryBoxes.remove(box);
            notifyListeners();
          };
          return;
        }
      }
    } else if (!carriedBox!.isCourierPackage) {
      if (playerY < 230) {
        activeInteractionText = '⬇️ Drop the Box on the Sidewalk';
        activeInteractionAction = () {
          deliveryBoxes.add(
            DeliveryBox(
              id: 'box_${DateTime.now().microsecondsSinceEpoch}',
              productType: carriedBox!.productType,
              currentCount: carriedBox!.currentCount,
              maxCount: carriedBox!.maxCount,
              x: playerX,
              y: playerY,
            ),
          );
          spawnParticle(playerX, playerY, '⬇️ Dropped', Colors.amberAccent);
          carriedBox = null;
        };
      }
    }
  }

  /// Raftaki (slotIndex) sıradaki ürünün tam 3D raf katı koordinatını döndürür
  Offset getShelfItemSlotPos(StoreShelf shelf, int slotIndex) {
    final r = shelf.rect;
    if (shelf.assignedProduct == SimProductType.egg) {
      // Yumurta reyonunda 20 adet tekli yumurta 3 kata (7 + 7 + 6) tek tek dizilir
      final idx = slotIndex.clamp(0, 19);
      final int tier = idx < 7 ? 0 : (idx < 14 ? 1 : 2);
      final int col = idx < 7 ? idx : (idx < 14 ? idx - 7 : idx - 14);
      final int colsInTier = tier < 2 ? 7 : 6;
      final double tierY = r.bottom - 20.0 - (tier * ((r.height - 34.0) / 3.0));
      final double usableW = r.width - 34.0;
      final double stepX = usableW / max(1, colsInTier - 1);
      final double itemX = r.left + 17.0 + (col * stepX);
      return Offset(itemX, tierY);
    }

    final int maxCap = max(1, shelf.maxCapacity);
    final int idx = slotIndex.clamp(0, maxCap - 1);
    final int perTier = (maxCap / 3).ceil();
    final int tier = (idx ~/ perTier).clamp(0, 2);
    final int col = idx % perTier;
    final double tierY = r.bottom - 20.0 - (tier * ((r.height - 34.0) / 3.0));
    final double usableW = r.width - 38.0;
    final double stepX = perTier > 1 ? usableW / (perTier - 1) : 0.0;
    final double itemX = r.left + 19.0 + (col * stepX);
    return Offset(itemX, tierY);
  }

  /// Reyon kapaklarının açılıp kapanmasını ve ürünlerin rafa TEK TEK (canlı animasyonla) dizilmesini yönetir
  void _updateShelvesAndDoors(double dt) {
    // 1. Uçan raf ürünlerini güncelle
    for (int i = flyingShelfItems.length - 1; i >= 0; i--) {
      final item = flyingShelfItems[i];
      item.progress += dt / item.duration;
      if (item.progress >= 1.0) {
        flyingShelfItems.removeAt(i);
      }
    }

    final playerPos = Offset(playerX, playerY);
    final workerPos = Offset(restocker.x, restocker.y);

    for (final shelf in shelves) {
      if (shelf.lastPlacedBounceTimer > 0) {
        shelf.lastPlacedBounceTimer = (shelf.lastPlacedBounceTimer - dt * 3.2).clamp(0.0, 1.0);
      }

      if (!shelf.isUnlocked) {
        shelf.doorOpenProgress = 0.0;
        shelf.stockStepTimer = 0.0;
        continue;
      }

      // Uzaktan rafa/dolaba tıklandıysa yanına varınca 1 adet alsın
      if (pendingTakeOneShelfId == shelf.id && shelf.rect.inflate(55).contains(playerPos)) {
        pendingTakeOneShelfId = null;
        targetMoveX = null;
        targetMoveY = null;
        takeOneFromShelf(shelf);
      }

      final bool playerNearShelf = shelf.rect.inflate(48).contains(playerPos);
      final bool playerStockingThis = playerNearShelf &&
          carriedBox != null &&
          !carriedBox!.isCourierPackage &&
          !carriedBox!.isPickedFromShelf &&
          carriedBox!.productType == shelf.assignedProduct &&
          shelf.currentStock < shelf.maxCapacity &&
          carriedBox!.currentCount > 0;

      final bool playerCloselyInspecting = shelf.rect.inflate(34).contains(playerPos);

      final bool workerNearThis = hasRestocker &&
          isRestockerHired &&
          shelf.rect.inflate(42).contains(workerPos) &&
          restocker.carriedBox != null &&
          restocker.carriedBox!.productType == shelf.assignedProduct;

      bool customerGrabbingFromThis = false;
      for (final c in customers) {
        if (c.state == CustomerState.shopping &&
            c.currentShoppingIndex < c.shoppingList.length &&
            c.shoppingList[c.currentShoppingIndex] == shelf.assignedProduct &&
            shelf.rect.inflate(42).contains(Offset(c.x, c.y))) {
          customerGrabbingFromThis = true;
          break;
        }
      }

      final bool shouldOpenDoor = playerStockingThis ||
          playerCloselyInspecting ||
          workerNearThis ||
          customerGrabbingFromThis;

      if (shouldOpenDoor) {
        shelf.doorOpenProgress = (shelf.doorOpenProgress + dt * 4.2).clamp(0.0, 1.0);
      } else {
        shelf.doorOpenProgress = (shelf.doorOpenProgress - dt * 2.6).clamp(0.0, 1.0);
      }

      // Oyuncu rafa yaklaştığında elindeki ürünleri TEK TEK rafa dizsin!
      if (playerStockingThis && shelf.doorOpenProgress >= 0.28) {
        playerActionAnimTimer += dt * 14.0;
        shelf.stockStepTimer += dt;
        if (shelf.stockStepTimer >= 0.15) {
          shelf.stockStepTimer = 0.0;
          _stockSingleItemFromPlayer(shelf);
        }
      } else if (!playerStockingThis && !workerNearThis) {
        shelf.stockStepTimer = 0.0;
      }
    }
  }

  void _stockSingleItemFromPlayer(StoreShelf shelf) {
    if (carriedBox == null || carriedBox!.isCourierPackage || !shelf.isUnlocked) return;
    if (carriedBox!.productType != shelf.assignedProduct) return;
    if (shelf.currentStock >= shelf.maxCapacity || carriedBox!.currentCount <= 0) return;

    final int slotIdx = shelf.currentStock;
    shelf.currentStock++;
    carriedBox!.currentCount--;
    shelf.lastPlacedBounceTimer = 1.0;

    final Offset dest = getShelfItemSlotPos(shelf, slotIdx);
    flyingShelfItems.add(
      ShelfFlyingItem(
        productType: shelf.assignedProduct,
        startPos: Offset(playerX, playerY - 24),
        endPos: dest,
        duration: 0.18,
      ),
    );

    final def = productCatalog[shelf.assignedProduct]!;
    spawnParticle(dest.dx, dest.dy - 8, '+1 ${def.emoji}', Colors.greenAccent, size: 13);

    if (carriedBox!.currentCount <= 0) {
      spawnParticle(playerX, playerY - 28, '✅ Stacked One by One!', Colors.orangeAccent, size: 15);
      carriedBox = null;
    } else if (shelf.currentStock >= shelf.maxCapacity) {
      spawnParticle(shelf.rect.center.dx, shelf.rect.top - 16, '✅ Shelf Completely Full!', Colors.greenAccent, size: 15);
    }
  }

  void _stockShelf(StoreShelf shelf) {
    _stockSingleItemFromPlayer(shelf);
  }

  bool orderProducts(Map<SimProductType, int> orderCart) {
    double totalCost = 0;
    List<SimProductType> items = [];

    orderCart.forEach((type, boxQty) {
      if (boxQty > 0) {
        final def = productCatalog[type]!;
        totalCost += boxPrice(def) * boxQty;
        for (int i = 0; i < boxQty; i++) {
          items.add(type);
        }
      }
    });

    if (totalCost == 0 || cash < totalCost) return false;

    cash -= totalCost;
    spawnParticle(computerDesk.center.dx, computerDesk.center.dy - 35, '-\$${totalCost.toStringAsFixed(0)} 🚚', Colors.redAccent);
    incomingShipment.addAll(items);
    isTruckArriving = true;
    truckX = -260;
    _sfx('order');
    notifyListeners();
    return true;
  }

  double _checkoutCustomer(SimCustomer customer) {
    double total = 0.0;
    for (var pType in customer.basket) {
      final def = productCatalog[pType]!;
      total += def.retailPrice;
    }

    if (customer.bonusMultiplier > 1.0) {
      total = (total * customer.bonusMultiplier).roundToDouble();
    }

    final idx = customer.checkoutIndex.clamp(0, unlockedCheckoutCount - 1);
    final counterRect = checkoutCounters[idx];

    customer.packedCount = customer.basket.length;
    cash += total;
    totalRevenue += total;
    _sfx('cash');
    customer.state = CustomerState.leavingHappy;

    String paymentText = '🛍️ PACKAGE DELIVERED! +\$${total.toStringAsFixed(0)} 💵';
    if (customer.isVip) {
      paymentText = '👑 VIP PACKAGE & TIP! +\$${total.toStringAsFixed(0)} 🌟';
    } else if (customer.archetype == CustomerArchetype.chef) {
      paymentText = '👨‍🍳 CHEF TIP! +\$${total.toStringAsFixed(0)} 🛍️';
    }

    spawnParticle(
      counterRect.center.dx,
      counterRect.center.dy - 40,
      paymentText,
      customer.isVip ? Colors.amberAccent : Colors.greenAccent,
      size: customer.isVip ? 21 : 19,
    );
    notifyListeners();
    return total;
  }

  /// Kasadaki müşterinin sıradaki ürününü barkod okuyucudan geçirip poşete koyar; tüm ürünler poşetlendiyse paketi teslim edip ödemeyi alır!
  bool packNextItemOrCheckout([SimCustomer? targetCustomer]) {
    final waiting = customers.where((c) => c.state == CustomerState.waitingAtCheckout).toList();
    final cust = targetCustomer ?? (waiting.isNotEmpty ? waiting.first : null);
    if (cust == null || cust.basket.isEmpty) return false;

    final idx = cust.checkoutIndex.clamp(0, unlockedCheckoutCount - 1);
    final counterRect = checkoutCounters[idx];

    if (cust.packedCount < cust.basket.length) {
      final itemType = cust.basket[cust.packedCount];
      final def = productCatalog[itemType]!;
      cust.baggingProduct = itemType;
      cust.baggingAnimTimer = 0.02;
      cust.packedCount++;

      // Dükkan sahibi kasadaysa veya manuel okutuyorsa canlı barkod okutma animasyonunu tetikle!
      activePlayerCheckoutIndex = idx;
      currentScanningProduct = itemType;
      playerScanAnimTimer = 1.0;
      _sfx('scan');
      playerActionAnimTimer += 2.2;
      if ((Offset(playerX, playerY) - counterRect.center).distance < 145) {
        playerAngle = pi / 2;
      }

      spawnParticle(
        counterRect.center.dx,
        counterRect.top - 22,
        '🔊 BEEP! ${def.emoji} ${def.name} Scanned • \$${def.retailPrice.toStringAsFixed(0)} (${cust.packedCount}/${cust.basket.length})',
        const Color(0xFF4ADE80),
        size: 15,
      );
      if (cust.packedCount >= cust.basket.length) {
        spawnParticle(
          counterRect.center.dx,
          counterRect.top - 42,
          '✅ All Items Scanned! Hand Over the Package!',
          Colors.amberAccent,
          size: 16,
        );
      }
      notifyListeners();
      return false;
    } else {
      _checkoutCustomer(cust);
      return true;
    }
  }

  double checkoutCurrentCustomer([SimCustomer? targetCustomer]) {
    final waiting = customers.where((c) => c.state == CustomerState.waitingAtCheckout).toList();
    final cust = targetCustomer ?? (waiting.isNotEmpty ? waiting.first : null);
    if (cust == null) return 0.0;
    return _checkoutCustomer(cust);
  }
}
