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

  // DEVAASA HARİTA BOYUTLARI (2000 x 1900 - Geniş Cadde + Büyük Market + 2 Sıralı Devasa Arka Çiftlik Vadisi)
  final double worldWidth = 2000;
  final double worldHeight = 1900;

  // Kamera Takip & Yakınlaştırma (WASD ile hareket ettikçe oyuncuyu yumuşakça takip eder)
  double cameraX = 1000;
  double cameraY = 480;
  double cameraZoom = 1.0;
  double worldTime = 0.0;

  // Oyuncu (Geniş marketin orta koridorunda doğar)
  double playerX = 1000;
  double playerY = 480;
  double playerSpeed = 320; // Büyük haritada akıcı hız
  double moveDirX = 0;
  double moveDirY = 0;
  double playerAngle = 0;
  double walkAnimTime = 0;
  CarriedBox? carriedBox;

  // Oyuncunun Elindeki Çiftlik Aleti (🪣 Süt Kovası, 🌾 Hasat Tırpanı, 🪣 Yumurta Kovası)
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
    Rect.fromLTWH(145, 290, 180, 110), // 🛎️ 1. Kasa (Seviye 1 - Başlangıçta Açık)
    Rect.fromLTWH(385, 290, 180, 110), // 🛎️ 2. Kasa (Seviye 2'de Açılır)
    Rect.fromLTWH(625, 290, 180, 110), // 🛎️ 3. Kasa (Seviye 3'te Açılır)
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

  final Rect computerDesk = const Rect.fromLTWH(1640, 280, 160, 105);   // Yönetim & Sipariş Ofis Masası
  final Rect trashCan = const Rect.fromLTWH(1790, 875, 64, 64);         // Geri Dönüşüm & Çöp Kutusu
  final Rect courierStation = const Rect.fromLTWH(1285, 148, 215, 74);  // 🛵 3D Hızlı Kurye & Online Sipariş Durağı
  final Rect courierPackingDesk = const Rect.fromLTWH(1420, 305, 170, 82); // 📦 3D Kurye Sipariş Paketleme İstasyonu (Kasadan Ayrı!)

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
  double customerSpawnTimer = 2.0;

  // Kamyon Animasyonu
  bool isTruckArriving = false;
  double truckX = -260;
  double truckTargetX = 450;
  List<SimProductType> incomingShipment = [];

  // Parçacıklar
  final List<WorldParticle> particles = [];

  // Anlık Etkileşim Durumu
  String? activeInteractionText;
  VoidCallback? activeInteractionAction;

  SimulationEngine() {
    _initStore();
  }

  bool get isCheeseUnlocked =>
      shelves.any((s) => s.assignedProduct == SimProductType.cheese && s.isUnlocked);

  double get nextLevelUpgradeCost {
    if (storeLevel == 1) return 300.0;
    if (storeLevel == 2) return 450.0;
    return 600.0;
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
      // ===============================================================
      // BAŞLANGIÇTA AÇIK REYONLAR (Sol Üst Kasa Alanından Uzak, Ferah ve Dağınık!)
      // ===============================================================
      StoreShelf(
        id: 'shelf_milk',
        name: 'Taze Köy Sütü Dolabı',
        assignedProduct: SimProductType.milk,
        rect: const Rect.fromLTWH(145, 610, 145, 175),
        currentStock: 12,
        maxCapacity: 16,
        isUnlocked: true,
        unlockCost: 0,
      ),
      StoreShelf(
        id: 'shelf_flour',
        name: 'Doğal Değirmen Unu',
        assignedProduct: SimProductType.flour,
        rect: const Rect.fromLTWH(510, 555, 210, 120),
        currentStock: 12,
        maxCapacity: 16,
        isUnlocked: true,
        unlockCost: 0,
      ),
      StoreShelf(
        id: 'shelf_egg',
        name: 'Köy Yumurtası Standı',
        assignedProduct: SimProductType.egg,
        rect: const Rect.fromLTWH(1195, 335, 155, 155),
        currentStock: 16,
        maxCapacity: 20,
        isUnlocked: true,
        unlockCost: 0,
      ),

      // ===============================================================
      // SONRADAN KADEMELİ OLARAK AÇILACAK REYONLAR (Açılana Kadar Sadece Yazı Görünür!)
      // ===============================================================
      StoreShelf(
        id: 'shelf_tomato',
        name: 'Tarla Domatesi',
        assignedProduct: SimProductType.tomato,
        rect: const Rect.fromLTWH(1580, 480, 210, 125),
        currentStock: 0,
        maxCapacity: 18,
        isUnlocked: false,
        unlockCost: 200,
      ),
      StoreShelf(
        id: 'shelf_pepper',
        name: 'Taze Köy Biberi',
        assignedProduct: SimProductType.pepper,
        rect: const Rect.fromLTWH(1165, 600, 210, 120),
        currentStock: 0,
        maxCapacity: 18,
        isUnlocked: false,
        unlockCost: 350,
      ),
      StoreShelf(
        id: 'shelf_cheese',
        name: 'Tulum Peyniri',
        assignedProduct: SimProductType.cheese,
        rect: const Rect.fromLTWH(440, 795, 205, 120),
        currentStock: 0,
        maxCapacity: 14,
        isUnlocked: false,
        unlockCost: 500,
      ),
      StoreShelf(
        id: 'shelf_apple',
        name: 'Amasya Elması',
        assignedProduct: SimProductType.apple,
        rect: const Rect.fromLTWH(1565, 750, 210, 125),
        currentStock: 0,
        maxCapacity: 18,
        isUnlocked: false,
        unlockCost: 650,
      ),
      StoreShelf(
        id: 'shelf_bread',
        name: 'Taş Fırın Ekmeği',
        assignedProduct: SimProductType.bread,
        rect: const Rect.fromLTWH(1165, 825, 210, 115),
        currentStock: 0,
        maxCapacity: 16,
        isUnlocked: false,
        unlockCost: 800,
      ),
    ];

    // ===============================================================
    // ARKA BAHÇE DEVASA 3D ÇİFTLİK TESİSLERİ
    // 1. Sıra: Başlangıçta Açık (Ahır, Buğday Tarlası, Kümes)
    // 2. Sıra: Marketten Meyve/Sebze/Ekmek Reyonu Açıldıkça Otomatik Açılan Tarlalar!
    // ===============================================================
    farmProducers = [
      FarmProducer(
        id: 'farm_barn',
        name: 'İnek Merası & Mandıra',
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
        name: 'Değirmen & Buğday Tarlası',
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
        name: 'Tavuk Çiftliği & Kümes',
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

      // ===============================================================
      // MEYVE / SEBZE / EKMEK REYONU AÇILDIĞINDA OTOMATİK AÇILAN TARLALAR!
      // ===============================================================
      FarmProducer(
        id: 'farm_tomato',
        name: 'Domates Tarlası',
        emoji: '🍅',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(120, 1565, 390, 260),
        solidBuildingRect: Rect.zero,
        gateMinX: 260,
        gateMaxX: 360,
        toolStandPos: const Offset(215, 1532),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.tomato,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'tom_0', index: 0, x: 215, y: 1645, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_1', index: 1, x: 395, y: 1645, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_2', index: 2, x: 215, y: 1745, productType: SimProductType.tomato, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'tom_3', index: 3, x: 395, y: 1745, productType: SimProductType.tomato, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      FarmProducer(
        id: 'farm_pepper',
        name: 'Köy Biberi Tarlası',
        emoji: '🫑',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(580, 1565, 390, 260),
        solidBuildingRect: Rect.zero,
        gateMinX: 720,
        gateMaxX: 820,
        toolStandPos: const Offset(675, 1532),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.pepper,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'pep_0', index: 0, x: 675, y: 1645, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_1', index: 1, x: 855, y: 1645, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_2', index: 2, x: 675, y: 1745, productType: SimProductType.pepper, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'pep_3', index: 3, x: 855, y: 1745, productType: SimProductType.pepper, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      FarmProducer(
        id: 'farm_apple',
        name: 'Amasya Elması Bahçesi',
        emoji: '🍎',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(1040, 1565, 390, 260),
        solidBuildingRect: Rect.zero,
        gateMinX: 1180,
        gateMaxX: 1280,
        toolStandPos: const Offset(1135, 1532),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.apple,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'app_0', index: 0, x: 1135, y: 1645, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_1', index: 1, x: 1315, y: 1645, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_2', index: 2, x: 1135, y: 1745, productType: SimProductType.apple, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'app_3', index: 3, x: 1315, y: 1745, productType: SimProductType.apple, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
      FarmProducer(
        id: 'farm_bread',
        name: 'Taş Fırın & Başak Tarlası',
        emoji: '🥖',
        zoneType: FarmZoneType.field,
        rect: const Rect.fromLTWH(1500, 1565, 390, 260),
        solidBuildingRect: Rect.zero,
        gateMinX: 1640,
        gateMaxX: 1740,
        toolStandPos: const Offset(1595, 1532),
        requiredTool: FarmToolType.scythe,
        primaryProduct: SimProductType.bread,
        isUnlocked: false,
        spots: [
          FarmHarvestSpot(id: 'brd_0', index: 0, x: 1595, y: 1645, productType: SimProductType.bread, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'brd_1', index: 1, x: 1775, y: 1645, productType: SimProductType.bread, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'brd_2', index: 2, x: 1595, y: 1745, productType: SimProductType.bread, regrowDuration: 5.5),
          FarmHarvestSpot(id: 'brd_3', index: 3, x: 1775, y: 1745, productType: SimProductType.bread, regrowDuration: 5.5),
        ],
        readyBoxes: 4,
        maxBoxes: 4,
        productionDuration: 5.5,
      ),
    ];
  }

  List<SimProductType> get unlockedProducts {
    return shelves.where((s) => s.isUnlocked).map((s) => s.assignedProduct).toList();
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
      '🔓 ${def.emoji} ${shelf.name} Açıldı!',
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
          '🌱 ${def.emoji} ${farm.name} Çiftlikte Açıldı!',
          Colors.amberAccent,
          size: 17,
        );
        spawnParticle(
          farm.rect.center.dx,
          farm.rect.top - 18,
          '🌱 ${def.emoji} ${farm.name} Açıldı!',
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
        '🧀 3D Peynir Yapma Makinesi Kuruldu!',
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
      if (!farm.isUnlocked) {
        farm.isHovered = false;
        farm.isToolStandHovered = false;
        continue;
      }
      farm.isHovered = farm.rect.inflate(12).contains(mousePos);
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

  void update(double dt) {
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
    final camLerp = (9.0 * dt).clamp(0.0, 1.0);
    cameraX += (playerX - cameraX) * camLerp;
    cameraY += (playerY - cameraY) * camLerp;

    _updateFarmProduction(dt);
    _updateTruck(dt);
    _updateCourier(dt);
    _updateCourierPacking(dt);
    if (hasRestocker && isRestockerHired) {
      _updateRestocker(dt);
    }
    if (isStoreOpen) {
      _updateCustomers(dt);
    }
    _updateParticles(dt);
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
          '🧀 Tulum Peyniri Hazır! ($cheeseMachineReadyBoxes/$cheeseMachineMaxBoxes)',
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
        '🥛 Önce Ahırdan Süt Sağıp Peynir Makinesine Getiriliyor...',
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
          '⚠️ Peynir Makinesi Dolu!',
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
        '🥛➔🧀 Süt Peynir Makinesine Döküldü!',
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
        '🧀 +${def.boxSize} Tulum Peyniri Alındı!',
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
  // 🪣🌾 ÇİFTLİK EKİPMAN & İÇERİ GİRİP HASAT / SAĞIM / TOPLAMA SİSTEMİ
  // Çiftlikten çıkınca Tırpan ve Kova otomatik bırakılır!
  // ===============================================================

  /// Oyuncu alet standından Kova veya Tırpan alır
  void equipToolFromStand(FarmProducer farm) {
    playerTool = farm.requiredTool;
    spawnParticle(
      playerX,
      playerY - 38,
      '${farm.requiredTool.emoji} ${farm.requiredTool.name} Alındı!',
      Colors.amberAccent,
      size: 16,
    );
    notifyListeners();
  }

  /// Tıklanan veya [E] basılan çiftlik alanında önce Kova/Tırpan alıp sonra içeri girerek toplama başlatır
  void handleFarmZoneOrToolClick(FarmProducer farm, Offset clickWorldPos) {
    if (!farm.isUnlocked) return;
    if ((clickWorldPos - farm.toolStandPos).distance < 48) {
      if ((Offset(playerX, playerY) - farm.toolStandPos).distance < 75) {
        equipToolFromStand(farm);
      } else {
        pendingAutoFarmId = farm.id;
        _pendingToolOnly = true;
        setTargetMove(farm.toolStandPos.dx, farm.toolStandPos.dy + 12, clearPendingFarm: false);
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
          '⚠️ Önce elindekini marketteki rafa diz!',
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
          '${farm.requiredTool.emoji} Önce ${farm.requiredTool.name} Alınıyor...',
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
        '⏳ Yeni mahsul/süt hazırlanıyor...',
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

    // 2. SÜT KOVASI / YUMURTA KOVASI / TIRPAN ARKA BAHÇEDE YÜRÜRKEN ELİMİZDE KALSIN!
    // Sadece market binasının içine geri girildiğinde (playerY < 960) otomatik bırakılır.
    if (playerTool != null && playerY < 960) {
      final droppedTool = playerTool!;
      playerTool = null;
      spawnParticle(
        playerX,
        playerY - 24,
        '${droppedTool.emoji} ${droppedTool.name} Çiftlik Girişine Bırakıldı',
        Colors.white70,
        size: 13,
      );
    }

    // 3. Oyuncu bir çiftlik alanının İÇİNDEYSE ve doğru ekipmanı (Süt Kovası / Tırpan / Yumurta Kovası) tutuyorsa:
    for (final farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if (!farm.rect.inflate(15).contains(playerPos)) continue;
      if (playerTool != farm.requiredTool) continue;

      if (carriedBox != null) {
        if (!_isProductFromFarm(carriedBox!.productType, farm)) continue;
        if (carriedBox!.currentCount >= carriedBox!.maxCount) continue;
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

          final SimProductType harvestedProd = farm.primaryProduct;
          final def = productCatalog[harvestedProd]!;
          final int gain = (def.boxSize / 2).ceil(); // 2 nokta = 1 tam dolu kova / sepet!

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

            String msg = '${def.emoji} ${def.name} Toplandı! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            if (farm.zoneType == FarmZoneType.barn) {
              msg = '🥛 Süt Sağıldı, Kova Bırakıldı! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            } else if (farm.primaryProduct == SimProductType.flour) {
              msg = '🌾 Tırpan Bırakıldı, Buğdaylar Elde! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
            } else if (farm.zoneType == FarmZoneType.coop) {
              msg = '🥚 Yumurtalar Toplandı, Kova Bırakıldı! (${carriedBox!.currentCount}/${carriedBox!.maxCount})';
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
  void _updateCourier(double dt) {
    switch (courierState) {
      case CourierState.away:
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
            '⏰ Kurye Süresi Doldu!',
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

    final onlineNames = ['GetirYemek #402', 'HızlıMarket #108', 'Bölge Kurye #85', 'Acil Paket #219', 'VIP Sipariş #77'];
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
      '🛵 Yeni Kurye Siparişi: ${qty}x ${def.emoji} (Dolaptan Tek Tek Al & 📦 Paketle!)',
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
              '⚠️ Bu fazla! Kurye $needed ${def.emoji} istiyor ($excess fazla)!',
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
            '❌ Yanlış Ürün! Kurye ${order.requiredQty}x ${def.emoji} ${def.name} istiyor!',
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
            '📦 ${def.emoji} Kurye Paketi Hazır! Motora Götür! ($packedQty/${order.requiredQty})',
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
      if (cash >= shelf.unlockCost) {
        return unlockShelf(shelf);
      }
      final def = productCatalog[shelf.assignedProduct]!;
      spawnParticle(
        shelf.rect.center.dx,
        shelf.rect.top - 14,
        '🔒 Kilitli (${def.emoji} ₺${shelf.unlockCost.toStringAsFixed(0)})',
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
          '🛵 Önce elindeki Kurye Paketini motora teslim et!',
          Colors.orangeAccent,
          size: 14,
        );
        return false;
      }
      if (carriedBox!.productType != shelf.assignedProduct) {
        spawnParticle(
          playerX,
          playerY - 32,
          '⚠️ Elinde başka ürün var! Önce bırak veya paketle.',
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
          '⚠️ Ellerin dolu! (En fazla ${carriedBox!.maxCount} adet)',
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
        '❌ ${def.emoji} ${def.name} Dolapta Kalmamış!',
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

    String msg = '+1 ${def.emoji} Alındı (Elinde: ${carriedBox!.currentCount})';
    if (courierState == CourierState.waitingForOrder &&
        activeCourierOrder != null &&
        activeCourierOrder!.productType == shelf.assignedProduct) {
      final needed = activeCourierOrder!.remainingQty;
      final total = courierStagedCount + carriedBox!.currentCount;
      if (total > needed) {
        msg = '+1 ${def.emoji} (Elinde: ${carriedBox!.currentCount} • ⚠️ Kurye için ${total - needed} fazla!)';
      } else {
        msg = '+1 ${def.emoji} Alındı ($total/$needed kurye için)';
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

  /// Raf/dolap tıklaması: elinde çiftlik/kamyon kolisi varsa dizer; yoksa her basışta 1 adet alır
  void handleShelfClick(StoreShelf shelf) {
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
          ? '📦 +$take ${def.emoji} Masaya Konuldu ($courierStagedCount/${order.requiredQty}) — $remAfter adet daha getir!'
          : '📦 +$take ${def.emoji} Tamamlandı! Paket Bantlanıyor...',
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
        '↩️ $excessReturned fazla ${def.emoji} rafa geri konuldu',
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
      '📦 ${def.emoji} Kurye Paketi Hazır! ($packCount/${order.requiredQty}) Motora Götür!',
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
        '📦 Masada $stageCount/${order.remainingQty} ${def.emoji} bekliyor!',
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
        '📦 Şu an aktif kurye siparişi bekleniyor...',
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
        '🛵 Hazır Kurye Paketi Motora Götürülüyor!',
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
          '❌ Yanlış Ürün! Kurye ${order.requiredQty}x ${def.emoji} ${def.name} istiyor!',
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
            '⚠️ Bu fazla! Kurye ${order.remainingQty} ${def.emoji} istiyor ($excess fazla)!',
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
        '📦 Kurye Paketleme İstasyonuna Gidiliyor...',
        Colors.amberAccent,
        size: 15,
      );
    } else {
      spawnParticle(
        courierPackingDesk.center.dx,
        courierPackingDesk.top - 16,
        '📦 Önce Dolaptan Tek Tek ${order.requiredQty}x ${def.emoji} Al & Buraya Getir!',
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
            ? '⚠️ Kurye Açık Almıyor & Elindeki Fazla! Paketleme İstasyonunda Ayarla!'
            : '⚠️ Kurye Açık Ürün Almıyor! Önce Paketleme İstasyonunda 📦 Paketle!';
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
          '❌ Kurye ${def.emoji} ${def.name} Paketi Bekliyor!',
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
          '🛵 Kurye Paketi Motora Götürülüyor...',
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
        totalRevenue += order.rewardAmount;
        completedCourierOrders++;
        spawnParticle(
          courierStation.center.dx,
          courierStation.top - 25,
          '🛵 KURYE PAKETİ TESLİM! +₺${order.rewardAmount.toStringAsFixed(0)} 🌟',
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
          '📦 +$take ${def.emoji} Paketi Kuryeye Yüklendi (${order.deliveredQty}/${order.requiredQty})',
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
          restocker.statusText = '🥛 Sütü Peynir Makinesine Götürüyor';
          return;
        }
      }

      final mx = cheeseMachineRect.center.dx;
      final my = cheeseMachineRect.bottom + 18;
      _moveWorkerTowards(mx, my, workerSpeed, dt);
      restocker.statusText = '🥛➔🧀 Sütü Peynir Makinesine Döküyor';

      if ((restocker.x - mx).abs() < 26 && (restocker.y - my).abs() < 26) {
        restocker.carriedBox = null;
        cheeseMachineMilkInput++;
        spawnParticle(mx, cheeseMachineRect.top - 14, '👷 🥛➔🧀 Süt Makineye Eklendi', Colors.cyanAccent, size: 13);
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
          restocker.statusText = '${box.containerEmoji} Çiftlikten Çıkıyor';
          return;
        }
      }

      // 2. sıradaki meyve/sebze tarlalarından (y > 1460) üst bahçeye çıkarken 1. sıra çiftliklerin arasındaki koridordan geç!
      if (restocker.y > 1460) {
        final corridorX = (restocker.x - 680).abs() < (restocker.x - 1320).abs() ? 680.0 : 1320.0;
        if ((restocker.x - corridorX).abs() > 45) {
          _moveWorkerTowards(corridorX, 1505, workerSpeed, dt);
          restocker.statusText = '${box.containerEmoji} Bahçe Koridoruna Yürüyor';
          return;
        }
        _moveWorkerTowards(corridorX, 1100, workerSpeed, dt);
        restocker.statusText = '${box.containerEmoji} Markete Çıkıyor';
        return;
      }

      if (restocker.y > 995 && (restocker.x - doorCenter).abs() > 90) {
        _moveWorkerTowards(doorCenter, 975, workerSpeed, dt);
        restocker.statusText = '${box.containerEmoji} Markete Götürüyor';
        return;
      }

      final tx = targetShelf.rect.center.dx;
      final ty = targetShelf.rect.bottom + 24;
      _moveWorkerTowards(tx, ty, workerSpeed, dt);
      final def = productCatalog[box.productType]!;
      restocker.statusText = '${box.containerEmoji} ${def.emoji} ${def.name} Tek Tek Diziyor';

      if ((restocker.x - tx).abs() < 24 && (restocker.y - ty).abs() < 24) {
        final space = targetShelf.maxCapacity - targetShelf.currentStock;
        if (space <= 0) {
          restocker.carriedBox = null;
          restocker.statusText = '✅ Raf Dolduruldu';
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
            restocker.statusText = '✅ Raf Dolduruldu';
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
      restocker.statusText = '👍 Tüm Raflar Dolu';
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
        if (restocker.y > 240 && (restocker.x - doorCenter).abs() > 110) {
          _moveWorkerTowards(doorCenter, 225, workerSpeed, dt);
          return;
        }
        _moveWorkerTowards(matchingBox.x, matchingBox.y, workerSpeed, dt);
        restocker.statusText = '📦 ${def.emoji} Koli Almaya Gidiyor';
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
        restocker.statusText = '🧀 Peynir Makinesinden Peynir Alıyor';
        if ((restocker.x - mx).abs() < 26 && (restocker.y - my).abs() < 26) {
          cheeseMachineReadyBoxes--;
          restocker.carriedBox = CarriedBox(
            productType: SimProductType.cheese,
            currentCount: def.boxSize,
            maxCount: def.boxSize,
            isFromFarm: true,
          );
          spawnParticle(mx, cheeseMachineRect.top - 14, '👷 +${def.boxSize} 🧀 Aldı', Colors.amberAccent, size: 13);
        }
        return;
      } else if (cheeseMachineMilkInput > 0 && restocker.carriedBox == null) {
        restocker.equippedTool = null;
        final mx = cheeseMachineRect.center.dx;
        final my = cheeseMachineRect.bottom + 18;
        _moveWorkerTowards(mx, my, workerSpeed * 0.7, dt);
        restocker.statusText = '⏳ Peynirin Hazırlanmasını Bekliyor';
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
      restocker.statusText = '⏳ Mahsul Yetişmesi Bekleniyor';
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
      restocker.statusText = '🚜 Çiftliğe İniyor';
      return;
    }

    // Hedef tarla 2. sıradaysa (y > 1500) ve Ali henüz 1. sıra çiftliklerin üstündeyse koridordan aşağı insin
    if (targetFarm.rect.top > 1500 && restocker.y < 1465) {
      final corridorX = (targetFarm.gateCenter.dx - 680).abs() < (targetFarm.gateCenter.dx - 1320).abs()
          ? 680.0
          : 1320.0;
      if (restocker.y < 1150 && (restocker.x - corridorX).abs() > 45) {
        _moveWorkerTowards(corridorX, 1110, workerSpeed, dt);
        restocker.statusText = '🚜 ${targetFarm.name} Yolunda';
        return;
      }
      _moveWorkerTowards(corridorX, 1500, workerSpeed, dt);
      restocker.statusText = '🚜 ${targetFarm.name} Koridorundan İniyor';
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
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${targetFarm.requiredTool.name} Alıyor';
      if ((restocker.x - stand.dx).abs() < 26 && (restocker.y - (stand.dy + 10)).abs() < 26) {
        restocker.equippedTool = targetFarm.requiredTool;
        spawnParticle(
          stand.dx,
          stand.dy - 18,
          '👷 ${targetFarm.requiredTool.emoji} ${targetFarm.requiredTool.name} Aldı',
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
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${targetFarm.name} İçine Giriyor';
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
      restocker.statusText = '${targetFarm.requiredTool.emoji} ${def.emoji} Toplamaya Yürüyor';
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
            String popText = '✨ +1 ${def.emoji} Hazır!';
            if (farm.zoneType == FarmZoneType.coop) {
              popText = '🐔 Yumurtladı! +1 🥚';
            } else if (farm.zoneType == FarmZoneType.barn) {
              popText = '🐄 Süt Doldu! +1 🥛';
            } else {
              popText = '🌱 ${def.emoji} Yetişti!';
            }
            spawnParticle(spot.x, spot.y - 22, popText, Colors.amberAccent, size: 13);
          }
        }
      }

      farm.readyBoxes = farm.readySpotCount;
    }
  }

  bool _canMoveTo(double nx, double ny) {
    if (nx < 90 || nx > (worldWidth - 90) || ny < 60 || ny > (worldHeight - 40)) {
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
    if (playerY <= 990 && ny > 990) {
      if (nx < doorCenter - 140 || nx > doorCenter + 140) return false;
    } else if (playerY > 990 && ny <= 990) {
      if (nx < doorCenter - 140 || nx > doorCenter + 140) return false;
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
      return Offset(doorCenter, 1015);
    }
    if (playerY > 995 && destY < 985 && (playerX - doorCenter).abs() > 115) {
      return Offset(doorCenter, 965);
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
  List<Rect> _getStoreObstacleRects() {
    final List<Rect> obstacles = [
      // Sağ üst Kurye Paketleme İstasyonu (kasalardan ayrı özel paketleme bölgesi)
      Rect.fromLTRB(
        courierPackingDesk.left - 12,
        courierPackingDesk.top - 12,
        courierPackingDesk.right + 12,
        courierPackingDesk.bottom + 14,
      ),
      // Sağ üst bilgisayar masası
      const Rect.fromLTRB(1620, 248, 1915, 398),
      // Sağ alt çöp kutusu
      const Rect.fromLTRB(1776, 862, 1915, 952),
    ];

    // Sadece seviyesi açılmış kasalar fiziksel engel oluşturur (kilitli kasa alanları boş kalır!)
    for (int i = 0; i < unlockedCheckouts.length; i++) {
      final cRect = unlockedCheckouts[i];
      obstacles.add(
        Rect.fromLTRB(
          i == 0 ? 85.0 : cRect.left - 24.0,
          248.0,
          cRect.right + 20.0,
          410.0,
        ),
      );
    }

    for (final shelf in shelves) {
      if (!shelf.isUnlocked) continue;
      // Duvara yakın reyonların duvar tarafını kapatarak karakterlerin dar duvar arasına sıkışmasını önle
      final double left = shelf.rect.left < 180 ? 85.0 : shelf.rect.left - 22.0;
      final double right = shelf.rect.right > 1750 ? 1915.0 : shelf.rect.right + 32.0;
      final double top = shelf.rect.top - 46.0;
      final double bottom = shelf.rect.bottom + 18.0;
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

    double minD = dBottom;
    Offset out = Offset(p.dx, r.bottom + 7);

    if (r.left > 105 && dLeft < minD) {
      minD = dLeft;
      out = Offset(r.left - 7, p.dy);
    }
    if (r.right < worldWidth - 105 && dRight < minD) {
      minD = dRight;
      out = Offset(r.right + 7, p.dy);
    }
    if (r.top > 250 && dTop < minD) {
      minD = dTop;
      out = Offset(p.dx, r.top - 7);
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

    // 1. Eğer karakter şu an bir reyonun / engelin sınırının içindeyse, önce en yakın koridor kenarına çıkar!
    for (final obs in obstacles) {
      if (obs.deflate(1.5).contains(start)) {
        return _pushOutOfRect(start, obs);
      }
    }

    // 2. Eğer hedef nokta yanlışlıkla bir engelin içindeyse, hedefi engelin dışına çek
    Offset safeGoal = effectiveGoal;
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
    const double cornerOffset = 7.0;
    const double minNodeDist = 7.0;

    final List<Offset> nodes = [start, safeGoal];

    bool isPointValid(Offset pt) {
      if (pt.dx < 102 || pt.dx > worldWidth - 102 || pt.dy < 238 || pt.dy > 978) {
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
        if ((existing - pt).distance < 5.0) return;
      }
      nodes.add(pt);
    }

    for (final obs in obstacles) {
      tryAddWaypoint(Offset(obs.left - cornerOffset, obs.top - cornerOffset));
      tryAddWaypoint(Offset(obs.right + cornerOffset, obs.top - cornerOffset));
      tryAddWaypoint(Offset(obs.left - cornerOffset, obs.bottom + cornerOffset));
      tryAddWaypoint(Offset(obs.right + cornerOffset, obs.bottom + cornerOffset));
    }

    // Ana market koridor kavşak noktaları
    const aisleHubs = [
      Offset(1000, 290), // Ön giriş koridoru
      Offset(1000, 488), // Orta koridor - Kasa koridoru kavşağı
      Offset(840, 488),  // Kasa koridoru doğu ucu
      Offset(600, 488),  // Kasa koridoru orta
      Offset(380, 488),  // Sol reyon koridoru üst kavşağı
      Offset(380, 722),  // Sol reyon koridoru orta kavşağı
      Offset(380, 948),  // Sol reyon koridoru alt kavşağı
      Offset(780, 722),  // Orta-sol koridor
      Offset(1000, 722), // Orta ana koridor
      Offset(1000, 955), // Arka kapı iç kavşağı
      Offset(1395, 275), // Kurye paketleme üst geçişi
      Offset(1505, 412), // Kurye paketleme istasyonu önü
      Offset(1475, 488), // Sağ reyon koridoru üst
      Offset(1475, 665), // Sağ reyon koridoru orta
      Offset(1475, 920), // Sağ reyon koridoru alt
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
        final wp = _getSmartWaypoint(targetMoveX!, targetMoveY!);
        double tdx = wp.dx - playerX;
        double tdy = wp.dy - playerY;
        double dist = sqrt(tdx * tdx + tdy * tdy);
        if (dist > 2.0) {
          dx = tdx / dist;
          dy = tdy / dist;
        }
      }
    }

    if (dx == 0 && dy == 0) return;

    walkAnimTime += dt * 11;
    playerAngle = atan2(dy, dx);

    double stepX = dx * playerSpeed * dt;
    double stepY = dy * playerSpeed * dt;

    bool moved = false;

    if (_canMoveTo(playerX + stepX, playerY)) {
      playerX += stepX;
      moved = true;
    }
    if (_canMoveTo(playerX, playerY + stepY)) {
      playerY += stepY;
      moved = true;
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
        spawnParticle(truckX - 10, 80, '💨', Colors.white54, size: 12);
      }
    } else {
      for (int i = 0; i < incomingShipment.length; i++) {
        final pType = incomingShipment[i];
        final def = productCatalog[pType]!;
        final boxX = 240.0 + (i * 58.0);
        deliveryBoxes.add(
          DeliveryBox(
            id: 'box_${DateTime.now().microsecondsSinceEpoch}_$i',
            productType: pType,
            currentCount: def.boxSize,
            maxCount: def.boxSize,
            x: boxX,
            y: 165,
          ),
        );
        spawnParticle(boxX, 165, '📦', Colors.amberAccent, size: 16);
      }
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
    if (customerSpawnTimer <= 0 && customers.length < (5 + storeLevel)) {
      _spawnCustomer();
      customerSpawnTimer = 3.5 + Random().nextInt(3);
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
      const vipNames = ['👑 Gurme Vedat', '👑 VIP Elif', '👑 İş İnsanı Bora', '👑 Koleksiyoner Selim'];
      name = vipNames[random.nextInt(vipNames.length)];
      avatar = '👑';
      desiredCount = 3;
    } else if (roll < 0.30) {
      archetype = CustomerArchetype.chef;
      const chefNames = ['👨‍🍳 Şef Danilo', '👩‍🍳 Pasta Şefi Seda', '👨‍🍳 Aşçı Murat Usta', '👩‍🍳 Gurme Şef Zeynep'];
      name = chefNames[random.nextInt(chefNames.length)];
      avatar = '👨‍🍳';
      desiredCount = 3;
    } else if (roll < 0.46) {
      archetype = CustomerArchetype.grandma;
      const elderNames = ['👵 Tonton Hayriye Nine', '👴 Emekli İhsan Dede', '👵 Şefkatli Fatma Nine', '👴 Rıza Amca'];
      name = elderNames[random.nextInt(elderNames.length)];
      avatar = name.startsWith('👴') ? '👴' : '👵';
      desiredCount = 2;
    } else if (roll < 0.62) {
      archetype = CustomerArchetype.athlete;
      const athleteNames = ['🏃 Sporcu Berk', '🏃‍♀️ Koşucu Pelin', '🏋️‍♂️ Antrenör Kaan', '🚴‍♀️ Tenisçi Ece'];
      name = athleteNames[random.nextInt(athleteNames.length)];
      avatar = '🏃';
      desiredCount = 2;
    } else if (roll < 0.78) {
      archetype = CustomerArchetype.student;
      const studentNames = ['🎒 Öğrenci Emre', '🎧 Üniversiteli Doğa', '📚 Stajyer Mert', '🎒 Öğrenci Sıla'];
      name = studentNames[random.nextInt(studentNames.length)];
      avatar = '🎒';
      desiredCount = 1 + random.nextInt(2);
    } else if (roll < 0.90) {
      archetype = CustomerArchetype.family;
      const familyNames = ['👩‍👧 Ayşe Anne & Efe', '👨‍👩‍👧 Yılmaz Ailesi', '👩‍👦 Sevgi Hanım', '👨‍👧 Kemal Bey & Kızı'];
      name = familyNames[random.nextInt(familyNames.length)];
      avatar = '👩‍👧';
      desiredCount = 3;
    } else {
      archetype = CustomerArchetype.regular;
      const regNames = ['👩 Selin Hanım', '👨 Mehmet Bey', '🧔 Ali Dayı', '👩‍🦰 Zeynep Hoca'];
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

    customers.add(
      SimCustomer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        avatar: avatar,
        archetype: archetype,
        x: worldWidth / 2,
        y: 25,
        shoppingList: shoppingList,
        isVip: isVip,
        checkoutIndex: bestCheckout,
      ),
    );
  }

  void _processCustomerAI(SimCustomer c, double dt) {
    final double speed = 135.0 * c.speedMultiplier;
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

        double targetX = shelf.rect.center.dx;
        double targetY = shelf.rect.bottom + 28;

        _moveCustomerTowards(c, targetX, targetY, speed, dt);

        if ((c.x - targetX).abs() < 18 && (c.y - targetY).abs() < 18) {
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
                spawnParticle(targetX, targetY - 25, '❌ Kalmamış', Colors.redAccent);
              }
            }

            if (c.shelfGrabTimer >= 0.48) {
              c.shelfGrabTimer = 0.0;
              c.currentShoppingIndex++;
            }
          } else {
            c.shelfGrabTimer = 0.0;
            spawnParticle(targetX, targetY - 25, '❌ Kalmamış', Colors.redAccent);
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
        }
        break;

      case CustomerState.waitingAtCheckout:
        if (c.basket.isEmpty) {
          c.state = CustomerState.leavingSad;
          break;
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
    final wp = _getStoreSmartWaypoint(c.x, c.y, targetX, targetY);
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
              '🛵 📦 Kurye Paketini Teslim Et: ${order.deliveredQty}/${order.requiredQty} ${def.emoji} (+₺${order.rewardAmount.toStringAsFixed(0)}) [E / Tıkla]';
        } else if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          activeInteractionText =
              '⚠️ Kurye Açık Ürün Almıyor! Önce Paketleme Masasında 📦 Kurye Paketi Yap! [E / Tıkla]';
        } else {
          activeInteractionText =
              '🛵 Kurye Siparişi: ${order.requiredQty}x ${def.emoji} ${def.name} (Önce 📦 Paketle & Getir! Ödül: +₺${order.rewardAmount.toStringAsFixed(0)}) [E / Tıkla]';
        }
        activeInteractionAction = () {
          deliverToCourier();
        };
      } else {
        activeInteractionText = '🛵 Hızlı Kurye Durağı (Yeni Sipariş Yolda...)';
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
              '✅ 📦 Kurye Paketi Elinde! Motora Götürüp Teslim Et! [E / Tıkla]';
          activeInteractionAction = () {
            deliverToCourier();
          };
        } else if (carriedBox != null && !carriedBox!.isCourierPackage && carriedBox!.productType == order.productType) {
          final total = courierStagedCount + carriedBox!.currentCount;
          if (total > order.remainingQty) {
            final excess = total - order.remainingQty;
            activeInteractionText =
                '⚠️ Bu fazla! Kurye ${order.remainingQty} ${def.emoji} istiyor ($excess fazla!) — Paketlemeyi Aç [E / Tıkla]';
          } else {
            activeInteractionText =
                '📦 ${def.emoji} ${def.name} Paketleme ($total/${order.remainingQty}) [E / Tıkla]';
          }
          activeInteractionAction = () {
            handleCourierPackingDeskClick();
          };
        } else if (courierStagedCount > 0) {
          if (courierStagedCount >= order.remainingQty) {
            final pct = (courierPackingProgress * 100).toInt().clamp(0, 100);
            activeInteractionText =
                '📦 ${def.emoji} ${def.name} Kurye Paketi Bantlanıyor... %$pct ($courierStagedCount/${order.requiredQty})';
          } else {
            final rem = order.remainingQty - courierStagedCount;
            activeInteractionText =
                '📦 Masada $courierStagedCount/${order.remainingQty} ${def.emoji} Hazır ($rem adet daha getir!) [E / Tıkla]';
            activeInteractionAction = () {
              handleCourierPackingDeskClick();
            };
          }
        } else {
          activeInteractionText =
              '📦 Kurye Paketleme İstasyonu: ${order.requiredQty}x ${def.emoji} ${def.name} Dolaptan Al & Paketle [E / Tıkla]';
          activeInteractionAction = () {
            handleCourierPackingDeskClick();
          };
        }
      } else {
        activeInteractionText = '📦 Kurye Paketleme İstasyonu (Kurye Siparişi Geldiğinde Burada Paketle)';
      }
      return;
    }

    if ((playerPos - computerDesk.center).distance < 110) {
      activeInteractionText = '💻 Sipariş & Yeni Ürün Kilit Açma Bilgisayarı';
      activeInteractionAction = () {};
      return;
    }

    // 🛎️ Açık Kasa Tezgahları Etkileşimi (Sadece Müşteri Ödemesi! Kasada kurye paketi YAPILMAZ!)
    for (int i = 0; i < checkoutCounters.length; i++) {
      final cRect = checkoutCounters[i];
      if ((playerPos - cRect.center).distance < 125) {
        if (i >= unlockedCheckoutCount) {
          activeInteractionText = '🔒 🛎️ Kasa ${i + 1} Kilitli (Mağaza Seviye ${i + 1} Olunca Açılır)';
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
                '🔊 Kasa ${i + 1}: ${nextProd.emoji} ${nextProd.name} Barkodu Okut & Poşetle (${cust.packedCount}/${cust.basket.length}) [E / Tıkla]';
          } else {
            activeInteractionText =
                '💵 Kasa ${i + 1}: Paketi Ver & Ödeme Al (${cust.name}) [E / Tıkla]';
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
              '🚫 Kasa ${i + 1}: Kasada kurye paketi yapılmaz! Sağdaki 📦 Kurye Paketleme İstasyonuna git!';
          activeInteractionAction = null;
        } else {
          activeInteractionText = hasAutoCashier
              ? '🛎️ Kasa ${i + 1} Tezgahı (Kasiyer Görevde - $unlockedCheckoutCount/3 Kasa Açık)'
              : '🛎️ Kasa ${i + 1} Tezgahı (Müşteri Geldiğinde Ürünleri Barkoddan Okut)';
          activeInteractionAction = null;
        }
        return;
      }
    }

    if ((playerPos - trashCan.center).distance < 80 && (carriedBox != null || playerTool != null)) {
      activeInteractionText = carriedBox != null ? '🗑️ Eldeki Ürünü Boşalt / Bırak' : '🗑️ Eldeki Ekipmanı Bırak';
      activeInteractionAction = () {
        spawnParticle(trashCan.center.dx, trashCan.center.dy, '🗑️ Bırakıldı', Colors.grey);
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
        activeInteractionText = '⏳ Peynir Yapma Makinesi Çalışıyor... %$pct';
      } else {
        activeInteractionText = '🧀 Peynir Makinesi: Ahırdan Süt Getir!';
        activeInteractionAction = () {
          interactWithCheeseMachine();
        };
      }
      return;
    }

    // 🪣🌾 Çiftlik Alet Standları (Yaklaşınca Süt Kovası, Tırpan veya Yumurta Kovasını Otomatik Alır!)
    for (var farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if ((playerPos - farm.toolStandPos).distance < 58) {
        if (playerTool != farm.requiredTool && carriedBox == null) {
          equipToolFromStand(farm);
        }
        activeInteractionText =
            '✅ ${farm.requiredTool.emoji} ${farm.requiredTool.name} Elinde! İçeri Girip Topla';
        activeInteractionAction = () {
          startAutoFarmHarvest(farm);
        };
        return;
      }
    }

    // 🐄🌾🐔🍎🍅🫑🥖 Çiftlik Alanları Etkileşimi
    for (var farm in farmProducers) {
      if (!farm.isUnlocked) continue;
      if (farm.rect.inflate(45).contains(playerPos)) {
        if (carriedBox != null &&
            (!_isProductFromFarm(carriedBox!.productType, farm) ||
                carriedBox!.currentCount >= carriedBox!.maxCount ||
                carriedBox!.isCourierPackage)) {
          activeInteractionText = '⚠️ Elindekiler Tamam! Market Rafına (veya Paketleme Masasına) Götür!';
          return;
        }

        if (playerTool != farm.requiredTool) {
          activeInteractionText =
              '${farm.requiredTool.emoji} Önce Girişten ${farm.requiredTool.name} Al! (Tıkla / [E])';
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
          String actionDesc = 'İçeri Gir & İnekten Süt Sağ';
          if (farm.zoneType == FarmZoneType.field) {
            actionDesc = 'İçeri Gir & ${def.emoji} ${def.name} Hasat Et';
          } else if (farm.zoneType == FarmZoneType.coop) {
            actionDesc = 'Kümesin İçine Gir & Kovaya Yumurta Topla';
          }
          activeInteractionText =
              '${farm.requiredTool.emoji} $actionDesc (${farm.readySpotCount} Hazır Nokta)';
          activeInteractionAction = () {
            startAutoFarmHarvest(farm);
          };
        } else {
          activeInteractionText = '⏳ ${farm.name}: Yeniden Yetişiyor...';
        }
        return;
      }
    }

    for (var shelf in shelves) {
      if (shelf.rect.inflate(48).contains(playerPos)) {
        final def = productCatalog[shelf.assignedProduct]!;

        if (!shelf.isUnlocked) {
          if (cash >= shelf.unlockCost) {
            activeInteractionText = '🔓 ${def.emoji} ${shelf.name} Kilidini Aç (₺${shelf.unlockCost.toStringAsFixed(0)})';
            activeInteractionAction = () {
              unlockShelf(shelf);
            };
          } else {
            activeInteractionText = '🔒 ${def.emoji} ${shelf.name} Kilitli (Gereken: ₺${shelf.unlockCost.toStringAsFixed(0)})';
          }
          return;
        }

        if (carriedBox != null) {
          if (carriedBox!.isCourierPackage) {
            activeInteractionText = '🛵 Elindeki Kurye Paketini Motora Teslim Et!';
          } else if (carriedBox!.productType == shelf.assignedProduct) {
            if (carriedBox!.isPickedFromShelf) {
              if (shelf.currentStock > 0 && carriedBox!.currentCount < carriedBox!.maxCount) {
                activeInteractionText =
                    '🖐️ +1 ${def.emoji} ${def.name} Al (Elinde: ${carriedBox!.currentCount}/${carriedBox!.maxCount}) • Stok: ${shelf.currentStock} [E / Tıkla]';
                activeInteractionAction = () {
                  takeOneFromShelf(shelf);
                };
              } else {
                activeInteractionText =
                    '🖐️ Elinde ${carriedBox!.currentCount}x ${def.emoji} ${def.name} Var';
              }
            } else if (shelf.currentStock < shelf.maxCapacity) {
              activeInteractionText =
                  '✨ ${def.emoji} ${def.name} Tek Tek Rafa Diziliyor... (${shelf.currentStock}/${shelf.maxCapacity})';
              activeInteractionAction = () {
                _stockShelf(shelf);
              };
            } else {
              activeInteractionText = '✅ ${def.name} Rafı Tamamen Dolu!';
            }
          } else {
            activeInteractionText = '❌ Yanlış Reyon! Bu Raf: ${def.emoji} ${def.name}';
          }
        } else {
          if (shelf.currentStock > 0) {
            activeInteractionText =
                '🖐️ ${def.emoji} ${shelf.name} (1 Adet Al) • Stok: ${shelf.currentStock}/${shelf.maxCapacity} [E / Tıkla]';
            activeInteractionAction = () {
              takeOneFromShelf(shelf);
            };
          } else {
            activeInteractionText = '❌ ${def.emoji} ${shelf.name}: Stokta Yok (0/${shelf.maxCapacity})';
          }
        }
        return;
      }
    }

    if (carriedBox == null) {
      for (var box in deliveryBoxes) {
        if ((playerPos - Offset(box.x, box.y)).distance < 58) {
          carriedBox = CarriedBox(
            productType: box.productType,
            currentCount: box.currentCount,
            maxCount: box.maxCount,
          );
          spawnParticle(playerX, playerY - 35, '📦 Koli Alındı', Colors.amberAccent);
          deliveryBoxes.remove(box);
          return;
        }
      }
    } else if (!carriedBox!.isCourierPackage) {
      if (playerY < 230) {
        activeInteractionText = '⬇️ Koliyi Kaldırıma Bırak';
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
          spawnParticle(playerX, playerY, '⬇️ Bırakıldı', Colors.amberAccent);
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
      spawnParticle(playerX, playerY - 28, '✅ Tek Tek Rafa Dizildi!', Colors.orangeAccent, size: 15);
      carriedBox = null;
    } else if (shelf.currentStock >= shelf.maxCapacity) {
      spawnParticle(shelf.rect.center.dx, shelf.rect.top - 16, '✅ Raf Tamamen Doldu!', Colors.greenAccent, size: 15);
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
        totalCost += def.boxCost * boxQty;
        for (int i = 0; i < boxQty; i++) {
          items.add(type);
        }
      }
    });

    if (totalCost == 0 || cash < totalCost) return false;

    cash -= totalCost;
    spawnParticle(computerDesk.center.dx, computerDesk.center.dy - 35, '-₺${totalCost.toStringAsFixed(0)} 🚚', Colors.redAccent);
    incomingShipment.addAll(items);
    isTruckArriving = true;
    truckX = -260;
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
    customer.state = CustomerState.leavingHappy;

    String paymentText = '🛍️ PAKET TESLİM! +₺${total.toStringAsFixed(0)} 💵';
    if (customer.isVip) {
      paymentText = '👑 VIP PAKET & BAHŞİŞ! +₺${total.toStringAsFixed(0)} 🌟';
    } else if (customer.archetype == CustomerArchetype.chef) {
      paymentText = '👨‍🍳 ŞEF BAHŞİŞİ! +₺${total.toStringAsFixed(0)} 🛍️';
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
      playerActionAnimTimer += 2.2;
      if ((Offset(playerX, playerY) - counterRect.center).distance < 145) {
        playerAngle = pi / 2;
      }

      spawnParticle(
        counterRect.center.dx,
        counterRect.top - 22,
        '🔊 BİİP! ${def.emoji} ${def.name} Okutuldu • ₺${def.retailPrice.toStringAsFixed(0)} (${cust.packedCount}/${cust.basket.length})',
        const Color(0xFF4ADE80),
        size: 15,
      );
      if (cust.packedCount >= cust.basket.length) {
        spawnParticle(
          counterRect.center.dx,
          counterRect.top - 42,
          '✅ Tüm Ürünler Okutuldu! Paketi Teslim Et!',
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
