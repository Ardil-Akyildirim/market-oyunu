import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/staff.dart';
import '../models/upgrade.dart';

class CustomerInStore {
  final String id;
  final String name;
  final String avatar;
  final String wantedProductId;
  final int wantedAmount;
  double waitProgress; // 0.0 - 1.0

  CustomerInStore({
    required this.id,
    required this.name,
    required this.avatar,
    required this.wantedProductId,
    required this.wantedAmount,
    this.waitProgress = 0.0,
  });
}

class FloatingNotice {
  final String id;
  final String text;
  final bool isPositive;

  FloatingNotice(this.text, {this.isPositive = true})
      : id = DateTime.now().microsecondsSinceEpoch.toString();
}

class GameProvider with ChangeNotifier {
  double _cash = 100.0; // Başlangıç parası
  double _totalEarned = 100.0;
  int _totalItemsSold = 0;
  int _marketLevel = 1;
  Timer? _gameLoopTimer;

  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  List<Staff> _staffList = [];
  List<Upgrade> _upgrades = [];
  
  // Canlı Simülasyon Verileri
  final List<CustomerInStore> _customers = [];
  final List<FloatingNotice> _recentEvents = [];
  int _customerSpawnCountdown = 2;
  double _marketReputation = 100.0; // %

  double get cash => _cash;
  double get totalEarned => _totalEarned;
  int get totalItemsSold => _totalItemsSold;
  int get marketLevel => _marketLevel;
  List<Product> get products => _products;
  List<Supplier> get suppliers => _suppliers;
  List<Staff> get staffList => _staffList;
  List<Upgrade> get upgrades => _upgrades;
  List<CustomerInStore> get customers => _customers;
  List<FloatingNotice> get recentEvents => _recentEvents;
  double get marketReputation => _marketReputation;

  String get marketTitle {
    switch (_marketLevel) {
      case 1:
        return 'Köy Bakkalı 🏡';
      case 2:
        return 'Mahalle Manavı 🍎';
      case 3:
        return 'Semt Marketi 🛒';
      case 4:
        return 'Büyük Süpermarket 🏬';
      case 5:
        return 'Mega Hipermarket 🏢✨';
      default:
        return 'Mega Market';
    }
  }

  double get nextLevelCost {
    switch (_marketLevel) {
      case 1:
        return 1200.0;
      case 2:
        return 7500.0;
      case 3:
        return 35000.0;
      case 4:
        return 150000.0;
      default:
        return 0.0;
    }
  }

  GameProvider() {
    _initData();
    _loadFromStorage().then((_) {
      _startGameLoop();
    });
  }

  void _initData() {
    _products = [
      // Seviye 1 Ürünler (Köy bakkalı)
      Product(
        id: 'milk',
        name: 'Taze Köy Sütü',
        emoji: '🥛',
        category: ProductCategory.dairy,
        description: 'Sabah sağılmış sıcacık doğal inek sütü.',
        stock: 20,
        maxStock: 30,
        buyPrice: 8.0,
        sellPrice: 15.0,
        isUnlocked: true,
        unlockCost: 0,
        unlockLevel: 1,
      ),
      Product(
        id: 'egg',
        name: 'Serbest Gezen Yumurta',
        emoji: '🥚',
        category: ProductCategory.farm,
        description: 'Çiftlik tavuklarından taptaze sarı yumurtalar.',
        stock: 25,
        maxStock: 40,
        buyPrice: 3.0,
        sellPrice: 6.5,
        isUnlocked: true,
        unlockCost: 0,
        unlockLevel: 1,
      ),
      Product(
        id: 'tomato',
        name: 'Tarla Domatesi',
        emoji: '🍅',
        category: ProductCategory.farm,
        description: 'Mis kokulu Çanakkale tarla domatesi.',
        stock: 15,
        maxStock: 30,
        buyPrice: 10.0,
        sellPrice: 20.0,
        isUnlocked: true,
        unlockCost: 0,
        unlockLevel: 1,
      ),
      Product(
        id: 'cheese',
        name: 'Tulum Peyniri',
        emoji: '🧀',
        category: ProductCategory.dairy,
        description: 'Geleneksel lezzet, olgunlaştırılmış tulum peyniri.',
        stock: 0,
        maxStock: 25,
        buyPrice: 35.0,
        sellPrice: 65.0,
        isUnlocked: false,
        unlockCost: 150,
        unlockLevel: 1,
      ),
      Product(
        id: 'apple',
        name: 'Amasya Elması',
        emoji: '🍎',
        category: ProductCategory.farm,
        description: 'Kıtır kıtır, sulu tatlı bahçe elmaları.',
        stock: 0,
        maxStock: 35,
        buyPrice: 12.0,
        sellPrice: 24.0,
        isUnlocked: false,
        unlockCost: 350,
        unlockLevel: 1,
      ),
      Product(
        id: 'carrot',
        name: 'Çıtır Havuç',
        emoji: '🥕',
        category: ProductCategory.farm,
        description: 'Tarladan yeni sökülmüş vitamin deposu havuç.',
        stock: 0,
        maxStock: 30,
        buyPrice: 9.0,
        sellPrice: 18.0,
        isUnlocked: false,
        unlockCost: 600,
        unlockLevel: 2,
      ),
      Product(
        id: 'bread',
        name: 'Köy Ekmeği',
        emoji: '🥖',
        category: ProductCategory.bakery,
        description: 'Taş fırında odun ateşinde pişmiş sıcacık ekmek.',
        stock: 0,
        maxStock: 50,
        buyPrice: 8.0,
        sellPrice: 16.0,
        isUnlocked: false,
        unlockCost: 1200,
        unlockLevel: 2,
      ),
      Product(
        id: 'honey',
        name: 'Çiçek Balı',
        emoji: '🍯',
        category: ProductCategory.farm,
        description: 'Toros yaylalarından süzme doğal bal.',
        stock: 0,
        maxStock: 20,
        buyPrice: 80.0,
        sellPrice: 160.0,
        isUnlocked: false,
        unlockCost: 2800,
        unlockLevel: 2,
      ),
      Product(
        id: 'butter',
        name: 'Yayık Tereyağı',
        emoji: '🧈',
        category: ProductCategory.dairy,
        description: 'Karadeniz yaylalarından mis kokulu sarı tereyağ.',
        stock: 0,
        maxStock: 25,
        buyPrice: 95.0,
        sellPrice: 190.0,
        isUnlocked: false,
        unlockCost: 5500,
        unlockLevel: 3,
      ),
      Product(
        id: 'olive',
        name: 'Ege Zeytini',
        emoji: '🫒',
        category: ProductCategory.grocery,
        description: 'Edremit yağlı salamura siyah sele zeytini.',
        stock: 0,
        maxStock: 40,
        buyPrice: 45.0,
        sellPrice: 90.0,
        isUnlocked: false,
        unlockCost: 9000,
        unlockLevel: 3,
      ),
      Product(
        id: 'meat',
        name: 'Dana Kıyma & Antrikot',
        emoji: '🥩',
        category: ProductCategory.butcher,
        description: 'Taze yerli besi kaliteli et çeşitleri.',
        stock: 0,
        maxStock: 30,
        buyPrice: 220.0,
        sellPrice: 390.0,
        isUnlocked: false,
        unlockCost: 20000,
        unlockLevel: 4,
      ),
      Product(
        id: 'coffee',
        name: 'Gurme Kahve Çekirdeği',
        emoji: '☕',
        category: ProductCategory.gourmet,
        description: 'Özel kavrulmuş aromatik çekirdek kahve.',
        stock: 0,
        maxStock: 35,
        buyPrice: 140.0,
        sellPrice: 280.0,
        isUnlocked: false,
        unlockCost: 45000,
        unlockLevel: 4,
      ),
      Product(
        id: 'lux_cheese',
        name: 'İthal Fransız Peynirleri',
        emoji: '✨🧀',
        category: ProductCategory.gourmet,
        description: 'Brie, Roquefort ve Gravyer özel seçkisi.',
        stock: 0,
        maxStock: 20,
        buyPrice: 380.0,
        sellPrice: 750.0,
        isUnlocked: false,
        unlockCost: 100000,
        unlockLevel: 5,
      ),
    ];

    _suppliers = [
      Supplier(
        id: 'riza',
        name: 'Çiftçi Rıza Dayı',
        title: 'Tarla & Sebze Bahçesi',
        avatar: '🚜',
        description: 'Tarladan taze domates, elma ve havuç getirir. Hızlı ve güvenilirdir.',
        supportedProductIds: ['tomato', 'apple', 'carrot'],
        contractCost: 250,
        discountRate: 0.15,
        deliveryTimeSeconds: 6,
      ),
      Supplier(
        id: 'nuri',
        name: 'Mandıracı Nuri Usta',
        title: 'Doğal Mandıra Üreticisi',
        avatar: '🐄',
        description: 'Taze süt, yumurta, tulum peyniri ve tereyağı sevkiyatı yapar.',
        supportedProductIds: ['milk', 'egg', 'cheese', 'butter'],
        contractCost: 500,
        discountRate: 0.15,
        deliveryTimeSeconds: 8,
      ),
      Supplier(
        id: 'mustafa',
        name: 'Fırıncı Mustafa Usta',
        title: 'Taş Fırın Unlu Mamuller',
        avatar: '👨‍🍳',
        description: 'Her sabah çıtır çıtır köy ekmeği ve unlu mamul tedarik eder.',
        supportedProductIds: ['bread'],
        contractCost: 1000,
        discountRate: 0.20,
        deliveryTimeSeconds: 5,
      ),
      Supplier(
        id: 'halil',
        name: 'Toptancı Halil Kaptan',
        title: 'Bölge Toptancı Hali Lojistik',
        avatar: '🚛',
        description: 'Kamyon dolusu zeytin, bal ve genel bakkaliye getirir.',
        supportedProductIds: ['olive', 'honey', 'milk', 'egg', 'tomato', 'cheese'],
        contractCost: 3500,
        discountRate: 0.25,
        deliveryTimeSeconds: 12,
      ),
      Supplier(
        id: 'mahmut',
        name: 'Kasap Mahmut',
        title: 'Yerli Çiftlik Kasabı',
        avatar: '🥩',
        description: 'Günlük taze antrikot, kıyma ve şarküteri ürünleri sağlar.',
        supportedProductIds: ['meat'],
        contractCost: 12000,
        discountRate: 0.20,
        deliveryTimeSeconds: 10,
      ),
      Supplier(
        id: 'elena',
        name: 'Global İthalat Lojistik',
        title: 'Uluslararası Gurme Tedarikçisi',
        avatar: '✈️',
        description: 'Özel gurme kahveler ve lüks Fransız peynirleri ulaştırır.',
        supportedProductIds: ['coffee', 'lux_cheese'],
        contractCost: 40000,
        discountRate: 0.25,
        deliveryTimeSeconds: 15,
      ),
    ];

    _staffList = [
      Staff(
        id: 'stocker',
        name: 'Çırak Ahmet',
        roleName: 'Reyon Görevlisi',
        avatar: '👦',
        type: StaffType.shelfStocker,
        description: 'Raflarda azalan ürünleri otomatik olarak depodan yerleştirir.',
        hireCost: 200,
        salaryPerMinute: 20,
        efficiency: 1.0,
      ),
      Staff(
        id: 'cashier',
        name: 'Kasiyer Ayşe',
        roleName: 'Hızlı Kasiyer',
        avatar: '👩‍💼',
        type: StaffType.cashier,
        description: 'Müşterileri sırayla otomatik olarak kasadan geçirip ödemeyi alır.',
        hireCost: 450,
        salaryPerMinute: 40,
        efficiency: 1.0,
      ),
      Staff(
        id: 'logistics_boy',
        name: 'Sevkiyatçı Cemal',
        roleName: 'Lojistik Elemanı',
        avatar: '🚚',
        type: StaffType.logistics,
        description: 'Tedarikçilerin teslimat süresini %30 hızlandırır ve otomatik sipariş verir.',
        hireCost: 1500,
        salaryPerMinute: 80,
        efficiency: 1.0,
      ),
      Staff(
        id: 'marketer',
        name: 'Pazarlamacı Canan',
        roleName: 'Halkla İlişkiler',
        avatar: '📢',
        type: StaffType.marketer,
        description: 'Markete gelen müşteri akışını ve bahşiş oranını önemli ölçüde artırır.',
        hireCost: 4500,
        salaryPerMinute: 150,
        efficiency: 1.0,
      ),
      Staff(
        id: 'store_manager',
        name: 'Müdür Selim Bey',
        roleName: 'Mağaza Müdürü',
        avatar: '👔',
        type: StaffType.manager,
        description: 'Tüm mağaza cirosuna ve satış fiyatlarına %20 net bonus sağlar.',
        hireCost: 15000,
        salaryPerMinute: 350,
        efficiency: 1.2,
      ),
    ];

    _upgrades = [
      Upgrade(
        id: 'wooden_shelves',
        title: 'Ahşap Reyon Rafı',
        description: 'Tüm ürünlerin maksimum raf kapasitesini %30 artırır.',
        icon: '🪵',
        cost: 300,
        multiplier: 1.3,
      ),
      Upgrade(
        id: 'neon_sign',
        title: 'Işıklı Neon Tabela',
        description: 'Müşteri ziyaret sıklığını ve dükkan prestijini yükseltir.',
        icon: '💡',
        cost: 850,
        multiplier: 1.25,
      ),
      Upgrade(
        id: 'pos_machine',
        title: 'Temassız POS Cihazı',
        description: 'Kasa satış hızını iki katına çıkarır, müşteriler sıra beklemez.',
        icon: '💳',
        cost: 2000,
        multiplier: 1.5,
      ),
      Upgrade(
        id: 'fridge_cooling',
        title: 'Geniş Sütlük & Şarküteri Dolabı',
        description: 'Süt, peynir ve et satış gelirlerini %35 artırır.',
        icon: '🧊',
        cost: 5000,
        multiplier: 1.35,
      ),
      Upgrade(
        id: 'sound_system',
        title: 'Neşeli Mağaza Müzik Sistemi',
        description: 'Müşteriler keyifle alışveriş yapar, ortalama sepet büyüklüğü artar.',
        icon: '🎵',
        cost: 12000,
        multiplier: 1.2,
      ),
      Upgrade(
        id: 'solar_energy',
        title: 'Çatı Güneş Panelleri',
        description: 'Personel giderlerini %40 azaltır, çevre dostu yeşil market!',
        icon: '☀️',
        cost: 30000,
        multiplier: 1.4,
      ),
    ];
  }

  void _startGameLoop() {
    _gameLoopTimer?.cancel();
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  void _tick() {
    bool stateChanged = false;

    // 1. Tedarikçilerin sevkiyat sürelerini güncelle
    for (var supplier in _suppliers) {
      if (supplier.isDelivering) {
        supplier.deliveryRemainingSeconds--;
        if (supplier.deliveryRemainingSeconds <= 0) {
          _completeDelivery(supplier);
        }
        stateChanged = true;
      }
    }

    // 2. Müşteri spawn döngüsü
    _customerSpawnCountdown--;
    if (_customerSpawnCountdown <= 0) {
      _spawnCustomer();
      // Pazarlamacı varsa daha sık müşteri gelir
      final marketer = _staffList.firstWhere((s) => s.type == StaffType.marketer);
      int interval = marketer.isHired ? 2 : 4;
      _customerSpawnCountdown = max(1, interval);
      stateChanged = true;
    }

    // 3. Müşteri sabır süresi
    for (int i = _customers.length - 1; i >= 0; i--) {
      _customers[i].waitProgress += 0.05;
      if (_customers[i].waitProgress >= 1.0) {
        // Müşteri sıkıldı ve gitti
        _addNotice('${_customers[i].name} sıra beklemekten sıkılıp ayrıldı!', isPositive: false);
        _customers.removeAt(i);
        _marketReputation = max(50.0, _marketReputation - 1.5);
        stateChanged = true;
      }
    }

    // 4. Kasiyer Otomasyonu (Personel)
    final cashier = _staffList.firstWhere((s) => s.type == StaffType.cashier);
    if (cashier.isHired && _customers.isNotEmpty) {
      // Kasiyer hızına göre müşteriyi kasadan geçir
      _checkoutCustomer(_customers.first, isAuto: true);
      stateChanged = true;
    }

    // 5. Reyon Elemanı Otomasyonu (Azalan stokları doldur)
    final stocker = _staffList.firstWhere((s) => s.type == StaffType.shelfStocker);
    if (stocker.isHired) {
      for (var product in _products.where((p) => p.isUnlocked)) {
        if (product.stock < product.maxStock * 0.3) {
          // Otomatik sipariş ver
          int needed = (product.maxStock * 0.4).round();
          double cost = needed * product.buyPrice;
          if (_cash >= cost) {
            _cash -= cost;
            product.stock += needed;
            stateChanged = true;
          }
        }
      }
    }

    // 6. Lojistikçi Otomasyonu (Tedarikçileri boşta bırakmaz)
    final logistics = _staffList.firstWhere((s) => s.type == StaffType.logistics);
    if (logistics.isHired) {
      for (var supplier in _suppliers.where((s) => s.isContracted && !s.isDelivering)) {
        // İlgili ürünlerin stoğu az mı?
        bool needsSupply = supplier.supportedProductIds.any((pid) {
          final prod = _products.firstWhere((p) => p.id == pid, orElse: () => _products.first);
          return prod.isUnlocked && prod.stock < prod.maxStock * 0.4;
        });
        if (needsSupply) {
          orderFromSupplier(supplier, silent: true);
          stateChanged = true;
        }
      }
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  void _spawnCustomer() {
    if (_customers.length >= 6) return; // Maksimum kasa kuyruğu

    final unlocked = _products.where((p) => p.isUnlocked).toList();
    if (unlocked.isEmpty) return;

    final random = Random();
    final chosenProduct = unlocked[random.nextInt(unlocked.length)];
    final customerAvatars = ['👩', '👨', '👵', '👴', '🧒', '🧔', '👱‍♀️', '👩‍🦰', '🧑‍🌾'];
    final customerNames = [
      'Fatma Teyze', 'Mehmet Bey', 'Zeynep Hanım', 'Ali Usta', 'Ayten Anne', 
      'Emre Kardeş', 'Selin Öğretmen', 'Muhtar Hasan', 'Ece Hanım', 'Caner Bey'
    ];

    int amount = random.nextInt(3) + 1;
    final customer = CustomerInStore(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: customerNames[random.nextInt(customerNames.length)],
      avatar: customerAvatars[random.nextInt(customerAvatars.length)],
      wantedProductId: chosenProduct.id,
      wantedAmount: amount,
    );

    _customers.add(customer);
  }

  // Müşteriye satış yap (Manuel tıklandığında veya Kasiyer tarafından)
  bool checkoutNextCustomer() {
    if (_customers.isEmpty) {
      _addNotice('Kasada bekleyen müşteri yok!', isPositive: false);
      notifyListeners();
      return false;
    }
    return _checkoutCustomer(_customers.first, isAuto: false);
  }

  bool _checkoutCustomer(CustomerInStore customer, {required bool isAuto}) {
    final prod = _products.firstWhere((p) => p.id == customer.wantedProductId, orElse: () => _products.first);

    if (prod.stock < customer.wantedAmount) {
      // Stok yetersiz!
      if (!isAuto) {
        _addNotice('Yetersiz stok! ${prod.name} kalmadı!', isPositive: false);
      }
      _customers.remove(customer);
      _marketReputation = max(40.0, _marketReputation - 2.0);
      notifyListeners();
      return false;
    }

    // Satış gerçekleşir
    prod.stock -= customer.wantedAmount;
    double earning = customer.wantedAmount * prod.sellPrice;

    // Bonus çarpanları (Müdür, Yükseltmeler)
    final manager = _staffList.firstWhere((s) => s.type == StaffType.manager);
    if (manager.isHired) {
      earning *= manager.efficiency;
    }
    for (var up in _upgrades.where((u) => u.isPurchased)) {
      if (up.id == 'pos_machine') earning *= 1.05;
      if (up.id == 'sound_system') earning *= 1.08;
    }

    _cash += earning;
    _totalEarned += earning;
    _totalItemsSold += customer.wantedAmount;
    _marketReputation = min(100.0, _marketReputation + 0.5);

    _customers.remove(customer);
    _addNotice('+₺${earning.toStringAsFixed(1)} (${customer.name}: ${customer.wantedAmount}x ${prod.emoji})', isPositive: true);

    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Manuel Raf Doldurma / Satın Alma (Toptan değil tek tek reyoncu gibi)
  bool restockProduct(Product product, {int amount = 10}) {
    int toAdd = min(amount, product.maxStock - product.stock);
    if (toAdd <= 0) {
      _addNotice('${product.name} reyonu zaten dolu!', isPositive: false);
      notifyListeners();
      return false;
    }

    double cost = toAdd * product.buyPrice;
    if (_cash < cost) {
      _addNotice('Yetersiz bakiye! ₺${cost.toStringAsFixed(1)} gerekli.', isPositive: false);
      notifyListeners();
      return false;
    }

    _cash -= cost;
    product.stock += toAdd;
    _addNotice('${toAdd}x ${product.name} raflara dizildi! (-₺${cost.toStringAsFixed(1)})', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Yeni Ürün Kilidini Açma
  bool unlockProduct(Product product) {
    if (_cash < product.unlockCost) {
      _addNotice('Kilidi açmak için ₺${product.unlockCost} gerekli!', isPositive: false);
      return false;
    }

    _cash -= product.unlockCost;
    product.isUnlocked = true;
    product.stock = product.maxStock ~/ 2; // Başlangıç hediye stoğu
    _addNotice('Tebrikler! ${product.emoji} ${product.name} reyonda yerini aldı!', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Ürünü Yükseltme (Kalite, Kapasite ve Fiyat Artışı)
  bool upgradeProduct(Product product) {
    double cost = product.upgradeCost;
    if (_cash < cost) {
      _addNotice('Yükseltme için ₺${cost.toStringAsFixed(0)} gerekli!', isPositive: false);
      return false;
    }

    _cash -= cost;
    product.upgrade();
    _addNotice('${product.name} Seviye ${product.level} oldu! Fiyat ve kâr arttı.', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Tedarikçiyle Anlaşma İmzala
  bool signSupplierContract(Supplier supplier) {
    if (_cash < supplier.contractCost) {
      _addNotice('Sözleşme bedeli ₺${supplier.contractCost}!', isPositive: false);
      return false;
    }

    _cash -= supplier.contractCost;
    supplier.isContracted = true;
    _addNotice('${supplier.name} ile tedarik anlaşması imzalandı! 🤝', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Tedarikçiden Toplu Sipariş Ver (Kamyon Yola Çıkar!)
  bool orderFromSupplier(Supplier supplier, {bool silent = false}) {
    if (!supplier.isContracted) {
      if (!silent) _addNotice('Önce bu tedarikçiyle anlaşma yapmalısın!', isPositive: false);
      return false;
    }

    if (supplier.isDelivering) {
      if (!silent) _addNotice('${supplier.name} zaten yolda! (${supplier.deliveryRemainingSeconds} sn kaldı)', isPositive: false);
      return false;
    }

    // İlgili açık ürünleri bul ve maliyeti hesapla
    final supportedUnlocked = _products.where((p) => p.isUnlocked && supplier.supportedProductIds.contains(p.id)).toList();
    if (supportedUnlocked.isEmpty) {
      if (!silent) _addNotice('Bu tedarikçinin getirebileceği açık ürünün yok!', isPositive: false);
      return false;
    }

    // Her ürün için reyon kapasitesine göre toptan sipariş
    double totalCost = 0.0;
    for (var prod in supportedUnlocked) {
      int needed = (prod.maxStock * 0.6).round();
      double itemPrice = prod.buyPrice * (1.0 - supplier.discountRate);
      totalCost += needed * itemPrice;
    }

    if (_cash < totalCost) {
      if (!silent) _addNotice('Sevkiyat için bakiye yetersiz! (Gereken: ₺${totalCost.toStringAsFixed(1)})', isPositive: false);
      return false;
    }

    _cash -= totalCost;
    supplier.isDelivering = true;
    supplier.deliveryRemainingSeconds = supplier.deliveryTimeSeconds;
    if (!silent) {
      _addNotice('${supplier.name} kamyonu yola çıktı! 🚛 (${supplier.deliveryTimeSeconds} sn)', isPositive: true);
    }
    notifyListeners();
    return true;
  }

  void _completeDelivery(Supplier supplier) {
    supplier.isDelivering = false;
    int totalDelivered = 0;
    final supportedUnlocked = _products.where((p) => p.isUnlocked && supplier.supportedProductIds.contains(p.id)).toList();

    for (var prod in supportedUnlocked) {
      int amount = (prod.maxStock * 0.6).round();
      prod.stock = min(prod.maxStock, prod.stock + amount);
      totalDelivered += amount;
    }

    supplier.lastDeliveredAmount = totalDelivered;
    _addNotice('🚚 ${supplier.name} sevkiyatı markete ulaştı! ($totalDelivered adet taze ürün)', isPositive: true);
    _saveToStorage();
  }

  // Tedarikçiyi Yükselt (Hız ve İndirim artar)
  bool upgradeSupplier(Supplier supplier) {
    double cost = supplier.upgradeCost;
    if (_cash < cost) {
      _addNotice('Geliştirme için ₺${cost.toStringAsFixed(0)} gerekli!', isPositive: false);
      return false;
    }

    _cash -= cost;
    supplier.upgrade();
    _addNotice('${supplier.name} filosu güçlendirildi! İndirim %${(supplier.discountRate * 100).toInt()}', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Personel İşe Al
  bool hireStaff(Staff staff) {
    if (_cash < staff.hireCost) {
      _addNotice('İşe alım için ₺${staff.hireCost} gerekli!', isPositive: false);
      return false;
    }

    _cash -= staff.hireCost;
    staff.isHired = true;
    _addNotice('${staff.name} (${staff.roleName}) işe başladı! 💼', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Personel Eğit / Yükselt
  bool upgradeStaff(Staff staff) {
    double cost = staff.upgradeCost;
    if (_cash < cost) {
      _addNotice('Eğitim için ₺${cost.toStringAsFixed(0)} gerekli!', isPositive: false);
      return false;
    }

    _cash -= cost;
    staff.upgrade();
    _addNotice('${staff.name} terfi aldı! Seviye ${staff.level} verimlilik arttı.', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Mağaza Yükseltmesi Satın Al
  bool purchaseUpgrade(Upgrade upgrade) {
    if (_cash < upgrade.cost) {
      _addNotice('Yükseltme için ₺${upgrade.cost} gerekli!', isPositive: false);
      return false;
    }

    _cash -= upgrade.cost;
    upgrade.isPurchased = true;
    if (upgrade.id == 'wooden_shelves') {
      for (var prod in _products) {
        prod.maxStock = (prod.maxStock * upgrade.multiplier).round();
      }
    }
    _addNotice('${upgrade.title} kuruldu! ${upgrade.description}', isPositive: true);
    _saveToStorage();
    notifyListeners();
    return true;
  }

  // Market Seviyesini Büyüt (Köy Bakkalı -> Süpermarket)
  bool levelUpMarket() {
    double cost = nextLevelCost;
    if (cost == 0) return false;

    if (_cash < cost) {
      _addNotice('Market büyütmek için ₺${cost.toStringAsFixed(0)} gerekli!', isPositive: false);
      return false;
    }

    _cash -= cost;
    _marketLevel++;
    _addNotice('🎉 TEBRİKLER! Artık bir "$marketTitle" sahibisiniz!', isPositive: true);

    // Yeni seviye ile yeni ürünleri açılabilir hale getir
    for (var prod in _products) {
      if (prod.unlockLevel <= _marketLevel && !prod.isUnlocked && prod.unlockCost == 0) {
        prod.isUnlocked = true;
      }
    }

    _saveToStorage();
    notifyListeners();
    return true;
  }

  void _addNotice(String text, {bool isPositive = true}) {
    _recentEvents.insert(0, FloatingNotice(text, isPositive: isPositive));
    if (_recentEvents.length > 5) {
      _recentEvents.removeLast();
    }
  }

  // Depolama (Save / Load)
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cash', _cash);
      await prefs.setDouble('totalEarned', _totalEarned);
      await prefs.setInt('totalItemsSold', _totalItemsSold);
      await prefs.setInt('marketLevel', _marketLevel);

      final productsData = _products.map((p) => p.toJson()).toList();
      await prefs.setString('products', jsonEncode(productsData));

      final suppliersData = _suppliers.map((s) => s.toJson()).toList();
      await prefs.setString('suppliers', jsonEncode(suppliersData));

      final staffData = _staffList.map((s) => s.toJson()).toList();
      await prefs.setString('staff', jsonEncode(staffData));

      final upgradesData = _upgrades.map((u) => u.toJson()).toList();
      await prefs.setString('upgrades', jsonEncode(upgradesData));
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cash = prefs.getDouble('cash') ?? _cash;
      _totalEarned = prefs.getDouble('totalEarned') ?? _totalEarned;
      _totalItemsSold = prefs.getInt('totalItemsSold') ?? _totalItemsSold;
      _marketLevel = prefs.getInt('marketLevel') ?? _marketLevel;

      final productsStr = prefs.getString('products');
      if (productsStr != null) {
        final List list = jsonDecode(productsStr);
        for (var item in list) {
          final prod = _products.firstWhere((p) => p.id == item['id'], orElse: () => _products.first);
          prod.loadJson(item);
        }
      }

      final suppliersStr = prefs.getString('suppliers');
      if (suppliersStr != null) {
        final List list = jsonDecode(suppliersStr);
        for (var item in list) {
          final s = _suppliers.firstWhere((sup) => sup.id == item['id'], orElse: () => _suppliers.first);
          s.loadJson(item);
        }
      }

      final staffStr = prefs.getString('staff');
      if (staffStr != null) {
        final List list = jsonDecode(staffStr);
        for (var item in list) {
          final st = _staffList.firstWhere((stf) => stf.id == item['id'], orElse: () => _staffList.first);
          st.loadJson(item);
        }
      }

      final upgradesStr = prefs.getString('upgrades');
      if (upgradesStr != null) {
        final List list = jsonDecode(upgradesStr);
        for (var item in list) {
          final u = _upgrades.firstWhere((upg) => upg.id == item['id'], orElse: () => _upgrades.first);
          u.loadJson(item);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  // Oyunu Sıfırla (Reset)
  void resetGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _cash = 100.0;
    _totalEarned = 100.0;
    _totalItemsSold = 0;
    _marketLevel = 1;
    _customers.clear();
    _recentEvents.clear();
    _initData();
    notifyListeners();
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    super.dispose();
  }
}
