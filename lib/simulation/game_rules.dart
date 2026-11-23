import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'simulation_engine.dart';
import 'simulation_models.dart';

/// All the "campaign" rules live here: reputation, the Mega Mart countdown,
/// win/lose, random day/night events, boss nights, upgrades and furniture.
/// Every number is a constant on purpose: tweak the balance right here.

enum GameOutcome { playing, won, lost }

class GameEvent {
  final String id;
  final String name;
  final String desc;
  final bool night;
  final double intervalMul; // customer spawn interval (lower = busier)
  final double patienceMul;
  final double salesMul;
  final double wholesaleMul;
  final double thiefSpeedMul;
  final double bountyMul;
  final int thiefAdd;
  final int hpAdd;
  final bool dark; // spooky: darker music
  final int kind; // thief kind for the night (0 thief, 1 horror, 2 ghost, 3 cultist)

  const GameEvent(
    this.id,
    this.name,
    this.desc, {
    this.night = false,
    this.intervalMul = 1.0,
    this.patienceMul = 1.0,
    this.salesMul = 1.0,
    this.wholesaleMul = 1.0,
    this.thiefSpeedMul = 1.0,
    this.bountyMul = 1.0,
    this.thiefAdd = 0,
    this.hpAdd = 0,
    this.dark = false,
    this.kind = 0,
  });
}

const List<GameEvent> kDayEvents = [
  GameEvent('festival', 'Town Festival', 'Crowds everywhere! Customers come much more often.', intervalMul: 0.65),
  GameEvent('rain', 'Rainy Day', 'Fewer people outside, but they buy more and wait longer.',
      intervalMul: 1.35, patienceMul: 1.25, salesMul: 1.15),
  GameEvent('heat', 'Heatwave', 'Customers are cranky: patience is much shorter.', patienceMul: 0.7, salesMul: 1.1),
  GameEvent('inspector', 'Health Inspector', 'Keep EVERY open shelf stocked until dusk: +6 / -6 reputation.'),
  GameEvent('blogger', 'Food Blogger', 'Happy customers give double reputation today.'),
  GameEvent('shortage', 'Supply Shortage', 'Wholesale boxes cost 30% more today.', wholesaleMul: 1.3),
  GameEvent('sale', 'Supplier Sale', 'Wholesale boxes are 25% cheaper today!', wholesaleMul: 0.75),
  GameEvent('lucky', 'Lucky Day', 'Everybody tips: sales are worth 25% more.', salesMul: 1.25),
  GameEvent('megaflyer', 'Mega Mart Flyers', 'Mega Mart flooded the town with coupons: fewer customers.',
      intervalMul: 1.5),
  GameEvent('goldencow', 'Golden Cow Day', 'A golden cow wanders the Cow Farm. It pays out golden milk now and then! (Needs the Cow Farm)'),
  GameEvent('omen', 'Ominous Omen', 'The sky is the wrong color. Customers are jumpy and impatient.',
      dark: true, patienceMul: 0.8, intervalMul: 1.15),
  GameEvent('fog', 'Unnatural Fog', 'Whispers in the fog. Few customers dare to come, but they pay more.',
      dark: true, intervalMul: 1.4, salesMul: 1.2),
  GameEvent('cursedgold', 'Cursed Gold', 'Sales are worth 40% more today... but the town whispers: -4 reputation at dawn.',
      dark: true, salesMul: 1.4),
];

const List<GameEvent> kNightEvents = [
  GameEvent('fullmoon', 'Full Moon', 'More and faster thieves, but the bounty is bigger.',
      night: true, thiefAdd: 2, thiefSpeedMul: 1.15, bountyMul: 1.6),
  GameEvent('gang', 'Gang Night', 'A big gang of weak thieves: every thief has only 1 HP.',
      night: true, thiefAdd: 4, hpAdd: -9),
  GameEvent('quiet', 'Quiet Night', 'The streets are calm. Fewer thieves tonight.', night: true, thiefAdd: -2),
  GameEvent('raccoons', 'Raccoon Rampage', 'Raccoons raid the store! Tiny, FAST and very greedy.',
      night: true, thiefAdd: 4, hpAdd: -9, thiefSpeedMul: 1.5, kind: 4),
  GameEvent('bounty', 'Wanted Posters', 'The sheriff doubled the bounty on thieves tonight.', night: true, bountyMul: 2.0),
  GameEvent('ufo', 'UFO Night', 'A UFO hovers over the farm. Aliens pay well for a cow... (Needs the Cow Farm)', night: true),
  GameEvent('eldritch', 'Eldritch Rift', 'The sky tears open. Horrors crawl in: tougher, slower, and they grab more.',
      night: true, dark: true, kind: 1, hpAdd: 2, thiefSpeedMul: 0.8, bountyMul: 1.8),
  GameEvent('poltergeist', 'Poltergeist Night', 'Angry ghosts: very fast, but one hit sends them back.',
      night: true, dark: true, kind: 2, thiefAdd: 3, hpAdd: -9, thiefSpeedMul: 1.35, bountyMul: 1.2),
  GameEvent('cult', 'Midnight Ritual', 'A hooded cult is after your stock. A big crowd of them.',
      night: true, dark: true, kind: 3, thiefAdd: 3, bountyMul: 1.3),
  GameEvent('bloodmoon', 'Blood Moon', 'A red moon rises. Everything is stronger, and so is the bounty.',
      night: true, dark: true, thiefAdd: 2, hpAdd: 1, thiefSpeedMul: 1.2, bountyMul: 1.5),
];

class UpgradeDef {
  final String id;
  final String name;
  final List<String> descs; // description of each level
  final List<double> costs;
  final int minStoreLevel;
  final int minDay;
  const UpgradeDef(this.id, this.name, this.descs, this.costs, {this.minStoreLevel = 1, this.minDay = 1});
  int get maxLevel => costs.length;
}

const List<UpgradeDef> kUpgrades = [
  UpgradeDef('stick', 'Reinforced Stick', ['Hits stun thieves longer.', 'Hits deal DOUBLE damage.'], [350, 900]),
  UpgradeDef('locks', 'Padlocks', ['Thieves grab 30% slower and carry only 2.', 'Thieves grab 60% slower.'], [450, 1000],
      minDay: 2),
  UpgradeDef('shelves', 'Wider Shelves', ['Shelves hold 20 items.', 'Shelves hold 24 items.'], [600, 1200],
      minStoreLevel: 2),
  UpgradeDef('waiting', 'Waiting Area', ['+1 customer at a time, +20% patience.'], [500], minStoreLevel: 2),
  UpgradeDef('loyalty', 'Loyalty Cards', ['Happy customers give 50% more reputation.'], [700], minStoreLevel: 2),
  UpgradeDef('bulk', 'Bulk Contracts', ['Wholesale boxes 8% cheaper.', 'Wholesale boxes 16% cheaper.'], [600, 1300],
      minStoreLevel: 2, minDay: 4),
  UpgradeDef('insurance', 'Night Insurance', ['Get 50% of the stolen value back at dawn.'], [800], minDay: 5),
  UpgradeDef('courier', 'Courier Service', ['Courier bike visits daily with big package orders.'], [500], minStoreLevel: 2),
  UpgradeDef('coffee', 'Coffee Machine', ['You walk 10% faster.', 'You walk 20% faster.'], [400, 900], minStoreLevel: 2),
  UpgradeDef('alarm', 'Alarm Bell', ['Thieves move 15% slower inside the store.', 'Thieves move 25% slower.'], [650, 1400],
      minDay: 3),
  UpgradeDef('salt', 'Salt Lines', ['Eldritch horrors, ghosts and bosses take +1 damage from your stick.'], [1100], minDay: 6),
  UpgradeDef('ads', 'Ad Campaign', ['Customers come 25% more often until the end of tomorrow. Buy again any day.'], [300], minDay: 2),
  UpgradeDef('training', 'Cashier Training', ['Cashier rings up faster.', 'Cashier is lightning fast.'], [500, 1000],
      minStoreLevel: 3),
];

class FurnitureDef {
  final String id;
  final String name;
  final String perk;
  final double cost;
  final double repPerDay;
  final int slot; // where it is drawn (see PixelPainter)
  const FurnitureDef(this.id, this.name, this.perk, this.cost, this.repPerDay, this.slot);
}

const List<FurnitureDef> kFurniture = [
  FurnitureDef('plant', 'Potted Plant', '+0.6 reputation per day', 120, 0.6, 0),
  FurnitureDef('mat', 'Welcome Mat', 'Customers are 6% more patient', 150, 0.0, 1),
  FurnitureDef('bench', 'Waiting Bench', 'Customers are 8% more patient', 250, 0.0, 2),
  FurnitureDef('cat', 'Lucky Cat', 'Sales are worth 4% more', 500, 0.3, 3),
  FurnitureDef('neon', 'Neon OPEN Sign', 'Customers arrive 8% faster', 400, 0.0, 4),
  FurnitureDef('tank', 'Fish Tank', '+1.5 reputation per day', 600, 1.5, 5),
  FurnitureDef('disco', 'Disco Ball', 'Thieves get dizzy: stun lasts longer', 800, 0.0, 6),
  FurnitureDef('cowstatue', 'Golden Cow Statue', '+2 reputation per day (very eccentric)', 1500, 2.0, 7),
];

class GameRules {
  final SimulationEngine e;
  GameRules(this.e);

  // ---- Balance knobs -------------------------------------------------
  static const int deadlineDay = 20; // the store is demolished after day 20
  static const double deedBase = 6500.0; // Land Deed price (reputation gives a discount)
  static const double debtLimit = -250.0; // below this you are bankrupt
  static const double startReputation = 40.0;
  static const double cashierHireCost = 1000.0;
  static const double stockerHireCost = 600.0;
  static const List<double> cashierCosts = [1000.0, 1500.0, 2000.0];
  static const double farmerCost = 700.0;
  static const double guardCost = 900.0;
  static const double riderCost = 800.0;
  static const double farmerWage = 55.0;
  static const double guardWage = 65.0;
  static const double riderWage = 45.0;
  static const int cashierMinLevel = 3;
  static const int stockerMinLevel = 2;

  // ---- State ---------------------------------------------------------
  double reputation = startReputation;
  double deedPaid = 0.0;
  GameOutcome outcome = GameOutcome.playing;
  bool outcomePending = false;
  bool endless = false;
  String loseReason = '';
  int bossesDefeated = 0;
  int customersServed = 0;
  int customersLost = 0;
  final Map<String, int> upgrades = {};
  final Set<String> furniture = {};
  final Set<String> farmsOwned = {};
  bool farmerHired = false;
  bool guardHired = false;
  bool riderHired = false;
  int adDays = 0;
  bool introShown = false;
  GameEvent? dayEvent;
  GameEvent? nightEvent;
  bool bossPending = false;
  bool bossAlive = false;
  double dawnRepChange = 0.0;
  final List<String> dawnNotes = [];

  // eccentric farm stuff
  double _goldenTimer = 8.0;
  FarmHarvestSpot? goldenSpot;
  double goldenGlow = 0.0;
  bool ufoActive = false;
  double ufoTimer = 0.0;
  bool _ufoAbducted = false;
  Offset ufoPos = const Offset(330, 1180);

  // ---- Derived numbers -----------------------------------------------
  int lvl(String id) => upgrades[id] ?? 0;
  GameEvent? get activeEvent => e.isNight ? nightEvent : dayEvent;
  double _ev(double Function(GameEvent) f) => activeEvent == null ? 1.0 : f(activeEvent!);

  int get daysLeft => max(0, deadlineDay + 1 - e.day);
  bool get isBossNight => e.day % 5 == 0;
  double get deedPrice => (deedBase * (1.0 - reputation / 400.0)).roundToDouble();
  double get deedRemaining => max(0.0, deedPrice - deedPaid);
  double get deedProgress => deedPrice <= 0 ? 1.0 : (deedPaid / deedPrice).clamp(0.0, 1.0).toDouble();

  double get patienceMul {
    double m = _ev((x) => x.patienceMul);
    if (lvl('waiting') > 0) m *= 1.2;
    if (furniture.contains('mat')) m *= 1.06;
    if (furniture.contains('bench')) m *= 1.08;
    return m;
  }

  double get intervalMul {
    double m = _ev((x) => x.intervalMul) * (1.25 - reputation / 200.0);
    if (furniture.contains('neon')) m *= 0.92;
    if (adDays > 0) m *= 0.75;
    return m;
  }

  double get salesMul {
    double m = _ev((x) => x.salesMul);
    if (furniture.contains('cat')) m *= 1.04;
    return m;
  }

  double get wholesaleMul => _ev((x) => x.wholesaleMul) * (1.0 - 0.08 * lvl('bulk'));
  double get bountyMul => _ev((x) => x.bountyMul);
  int get extraCustomerCap => lvl('waiting') > 0 ? 1 : 0;
  double get repGainMul =>
      (activeEvent?.id == 'blogger' ? 2.0 : 1.0) * (lvl('loyalty') > 0 ? 1.5 : 1.0);

  // cashier speed (seconds per item)
  double get cashierInterval => const [1.1, 0.8, 0.55][lvl('training').clamp(0, 2).toInt()];

  // night fighting
  bool get courierService => lvl('courier') > 0;
  double get playerSpeedMul => 1.0 + 0.1 * lvl('coffee');
  double get alarmSlow => 1.0 - (lvl('alarm') == 0 ? 0.0 : (lvl('alarm') == 1 ? 0.15 : 0.25));
  int get upgradesBought => upgrades.entries.where((x) => x.key != 'ads').fold<int>(0, (a, x) => a + x.value);

  /// The more you upgrade, the more attention you attract (thieves and bosses scale up).
  double get threat => 1.0 + 0.045 * upgradesBought + 0.08 * (e.storeLevel - 1) + 0.03 * furniture.length;

  int stickDamageFor(Thief t) => stickDamage + ((lvl('salt') > 0 && (t.isBoss || t.kind != 0)) ? 1 : 0);
  int carryFor(Thief t) => (t.isBoss ? 6 : carryLimit) + (t.kind == 1 ? 1 : 0);
  int get stickDamage => lvl('stick') >= 2 ? 2 : 1;
  double get stunBonus => 0.25 * lvl('stick') + (furniture.contains('disco') ? 0.3 : 0.0);
  int get carryLimit => lvl('locks') >= 1 ? 2 : 3;
  double get stealSlow => 1.0 + 0.3 * lvl('locks');
  int get shelfCapacity => 16 + 4 * lvl('shelves');

  double get furnitureRepPerDay {
    double r = 0;
    for (final f in kFurniture) {
      if (furniture.contains(f.id)) r += f.repPerDay;
    }
    return r;
  }

  void applyShelfCaps() {
    for (final s in e.shelves) {
      s.maxCapacity = shelfCapacity;
    }
  }

  void addRep(double d) {
    reputation = (reputation + d).clamp(0.0, 100.0).toDouble();
  }

  // ---- Shop actions (used by the Manager screen) -------------------------
  bool canBuyUpgrade(UpgradeDef u) {
    final l = lvl(u.id);
    if (u.id == 'ads') return adDays <= 0 && e.cash >= u.costs[0] && e.day >= u.minDay && e.storeLevel >= u.minStoreLevel;
    return l < u.maxLevel &&
        e.storeLevel >= u.minStoreLevel &&
        e.day >= u.minDay &&
        e.cash >= u.costs[l] &&
        (u.id != 'training' || e.hasAutoCashier);
  }

  void buyUpgrade(UpgradeDef u) {
    if (!canBuyUpgrade(u)) return;
    e.cash -= u.costs[lvl(u.id)];
    if (u.id == 'ads') {
      adDays = 2;
      e.playSfx('cash');
      e.spawnParticle(e.playerX, e.playerY - 50, 'Ad campaign running!', Colors.lightGreenAccent, size: 16);
      return;
    }
    upgrades[u.id] = lvl(u.id) + 1;
    if (u.id == 'shelves') applyShelfCaps();
    e.playSfx('cash');
    e.spawnParticle(e.playerX, e.playerY - 50, '{star} ${u.name} bought!', Colors.lightGreenAccent, size: 16);
  }

  void buyFurniture(FurnitureDef f) {
    if (furniture.contains(f.id) || e.cash < f.cost) return;
    e.cash -= f.cost;
    furniture.add(f.id);
    e.playSfx('bell');
    e.spawnParticle(e.playerX, e.playerY - 50, 'The van delivered: ${f.name}!', Colors.amberAccent, size: 16);
  }

  void payDeed(double amount) {
    if (outcome != GameOutcome.playing && !endless) return;
    final pay = min(min(amount, e.cash), deedRemaining);
    if (pay <= 0) return;
    e.cash -= pay;
    deedPaid += pay;
    e.playSfx('cash');
    if (deedRemaining <= 0.5 && outcome == GameOutcome.playing) {
      outcome = GameOutcome.won;
      outcomePending = true;
    }
  }

  // ---- Lifecycle hooks (called by the engine) ------------------------------
  void reset() {
    reputation = startReputation;
    deedPaid = 0.0;
    outcome = GameOutcome.playing;
    outcomePending = false;
    endless = false;
    loseReason = '';
    bossesDefeated = 0;
    customersServed = 0;
    customersLost = 0;
    upgrades.clear();
    furniture.clear();
    crate.clear();
    _bossType = -1;
    _bossBag.clear();
    _lastDay = '';
    _lastNight = '';
    farmsOwned.clear();
    farmerHired = false;
    guardHired = false;
    riderHired = false;
    adDays = 0;
    introShown = false;
    dayEvent = null;
    nightEvent = null;
    bossPending = false;
    bossAlive = false;
    dawnNotes.clear();
    dawnRepChange = 0.0;
    ufoActive = false;
    goldenSpot = null;
    applyShelfCaps();
    applyFarmOwnership();
  }

  /// Dusk: the day event is over, tonight's event and boss are decided.
  void onNightStart() {
    // Health inspector verdict
    if (dayEvent?.id == 'inspector') {
      final empty = e.shelves.where((s) => s.isUnlocked && s.currentStock <= 0).length;
      if (empty == 0) {
        addRep(6);
        e.spawnParticle(e.playerX, e.playerY - 70, 'Inspector: spotless! +6 {star}', Colors.lightGreenAccent, size: 16);
      } else {
        addRep(-6);
        e.spawnParticle(e.playerX, e.playerY - 70, 'Inspector: empty shelves! -6 {star}', Colors.redAccent, size: 16);
      }
    }
    goldenSpot = null;

    nightEvent = null;
    bossPending = false;
    bossAlive = false;
    if (isBossNight) {
      bossPending = true;
      bossAlive = true;
      e.nightThievesPlanned = min(3 + e.day ~/ 3, 8);
      e.spawnParticle(e.playerX, e.playerY - 60, '{thief} BOSS NIGHT: ${bossName()} is coming!', Colors.redAccent, size: 18);
      e.showToast('BOSS NIGHT! ${bossName()} is coming!', kind: 1, seconds: 4);
    } else if (e.day >= 2 && Random().nextDouble() < 0.7) {
      final pool = kNightEvents.where((x) => x.id != _lastNight).toList();
      nightEvent = pool[Random().nextInt(pool.length)];
      final ev = nightEvent!;
      e.nightThievesPlanned = max(1, e.nightThievesPlanned + ev.thiefAdd);
      e.showToast('${ev.name}: ${ev.desc}', kind: 1, seconds: 4);
    }
    e.nightThievesPlanned = max(1, (e.nightThievesPlanned * (1.0 + (threat - 1.0) * 0.6)).round());
    _lastNight = nightEvent?.id ?? '';
    ufoActive = nightEvent?.id == 'ufo' && farmsOwned.contains('farm_barn');
    _ufoAbducted = false;
    ufoTimer = 0.0;
  }

  int _bossType = -1;
  final List<int> _bossBag = [];
  String _lastDay = '';
  String _lastNight = '';

  int _drawBoss() {
    if (_bossBag.isEmpty) _bossBag.addAll([0, 1, 2, 3]..shuffle());
    return _bossBag.removeLast();
  }

  int get bossType {
    if (_bossType < 0) _bossType = _drawBoss();
    return _bossType;
  }
  static const List<String> _bossNames = ['Sneaky Sam', 'Big Bruno', 'Madame Shadow', 'THE MEGA BOSS'];
  static const List<String> bossBlurbs = [
    'Fast and greedy. He blinks between shelves.',
    'A walking wall. His stomp throws you back.',
    'A ghost. She phases out and cannot be hit.',
    'The Mega Mart owner, reborn as a horror. He tears shelves apart and calls minions.',
  ];
  String bossName() => _bossNames[bossType];
  String get bossBlurb => bossBlurbs[bossType];

  int get bossHp {
    const mult = [1.0, 1.6, 1.3, 1.7];
    return ((10 + e.day * 1.1) * mult[bossType] * (1.0 + (threat - 1.0) * 0.5)).round();
  }

  double get bossSpeed => const [128.0, 78.0, 112.0, 96.0][bossType];

  /// Boss abilities: called every frame for every thief.
  void updateBoss(Thief t, double dt) {
    if (!t.isBoss || t.hp <= 0) return;
    t.abilityTimer += dt;
    if (t.phased > 0) t.phased = max(0.0, t.phased - dt);
    switch (t.bossType) {
      case 0: // blink to another stocked shelf
        if (t.abilityTimer > 7.0 && t.state != ThiefState.stunned) {
          t.abilityTimer = 0;
          final cands = e.shelves.where((s) => s.isUnlocked && s.currentStock > 0).toList();
          if (cands.isNotEmpty) {
            final s = cands[Random().nextInt(cands.length)];
            t.x = s.rect.center.dx;
            t.y = s.rect.bottom + 34;
            t.targetShelfId = s.id;
            t.loot = s.assignedProduct;
            t.wpCache = null;
            t.state = ThiefState.stealing;
            e.spawnParticle(t.x, t.y - 50, 'Sam blinks!', Colors.purpleAccent, size: 15);
          }
        }
        break;
      case 1: // stomp
        if (t.abilityTimer > 8.0) {
          t.abilityTimer = 0;
          final dx = e.playerX - t.x, dy = e.playerY - t.y;
          final d = sqrt(dx * dx + dy * dy);
          e.spawnParticle(t.x, t.y - 60, 'STOMP!', Colors.orangeAccent, size: 20);
          e.playSfx('hit');
          if (d < 190) {
            final n = max(1.0, d);
            e.playerX = (e.playerX + dx / n * 150).clamp(520.0, e.worldWidth - 520.0).toDouble();
            e.playerY = (e.playerY + dy / n * 150).clamp(300.0, 940.0).toDouble();
            e.spawnParticle(e.playerX, e.playerY - 40, 'Knocked back!', Colors.redAccent, size: 15);
          }
        }
        break;
      case 2: // phase
        if (t.abilityTimer > 6.0) {
          t.abilityTimer = 0;
          t.phased = 2.0;
          e.spawnParticle(t.x, t.y - 60, 'Madame fades away...', Colors.lightBlueAccent, size: 15);
        }
        break;
      case 3: // reality tear + minions
        if (t.abilityTimer > 9.0) {
          t.abilityTimer = 0;
          final cands = e.shelves.where((s) => s.isUnlocked && s.currentStock > 2).toList();
          if (cands.isNotEmpty) {
            final s = cands[Random().nextInt(cands.length)];
            s.currentStock = max(0, s.currentStock - 3);
            e.spawnParticle(s.rect.center.dx, s.rect.top - 20, 'Reality tears! -3 stock', Colors.purpleAccent, size: 16);
          }
        }
        if (!t.abilityDone && t.hp * 2 <= t.maxHp) {
          t.abilityDone = true;
          for (int i = 0; i < 3; i++) {
            e.spawnMinionThief(x: t.x + (i - 1) * 50.0, y: t.y + 20, hp: 2, kind: 1);
          }
          e.spawnParticle(t.x, t.y - 70, 'The Mega Boss summons horrors!', Colors.purpleAccent, size: 18);
        }
        break;
    }
  }

  /// While a boss is on the field nobody else (except its own minions) shows up.
  bool get bossBlocksSpawns => !bossPending && e.thieves.any((t) => t.isBoss && t.hp > 0);

  /// True once, for the first thief of a boss night.
  bool takeBoss() {
    if (!bossPending) return false;
    bossPending = false;
    return true;
  }

  int thiefHp(int base) {
    final add = nightEvent?.hpAdd ?? 0;
    final scaled = base + ((threat - 1.0) * 2.0).floor();
    return max(1, scaled + add);
  }

  double get thiefSpeedMul => (nightEvent?.thiefSpeedMul ?? 1.0) * alarmSlow;
  int get thiefKind => nightEvent?.kind ?? 0;

  void onThiefRepelled(Thief t) {
    addRep(t.isBoss ? 8.0 : 0.6);
    if (t.isBoss) {
      bossesDefeated++;
      bossAlive = false;
      final prize = 150.0 + e.day * 10.0;
      e.cash += prize;
      e.nightBounty += prize;
      e.spawnParticle(t.x, t.y - 70, '{thief} BOSS DEFEATED! +\$${prize.toStringAsFixed(0)}', Colors.amberAccent, size: 20);
    }
  }

  void onThiefEscaped(Thief t) {
    if (t.isBoss && t.hp > 0) {
      bossAlive = false;
      addRep(-8);
      e.spawnParticle(t.x, t.y - 60, 'The boss got away! -8 {star}', Colors.redAccent, size: 18);
    } else if (t.carried > 0 && t.hp > 0) {
      addRep(-1.0);
    }
  }

  void onCustomerServed() {
    customersServed++;
    addRep(0.35 * repGainMul);
  }

  void onCustomerLost() {
    customersLost++;
    addRep(-1.0);
  }

  /// Dawn: wages are paid; this checks the deadline, the debt and the reputation.
  void onDawn() {
    dawnNotes.clear();
    final before = reputation;

    if (dayEvent?.id == 'cursedgold') {
      addRep(-4);
      dawnNotes.add('The cursed gold took its toll: -4 reputation.');
    }
    if (adDays > 0) adDays--;
    addRep(furnitureRepPerDay);
    addRep(-(0.3 + e.day * 0.03)); // Mega Mart keeps stealing your regulars
    if (lvl('insurance') > 0 && e.nightStolenValue > 0) {
      final back = (e.nightStolenValue * 0.5).roundToDouble();
      e.cash += back;
      dawnNotes.add('Insurance paid back \$${back.toStringAsFixed(0)}.');
    }
    if (e.cash < 0) {
      addRep(-2);
      dawnNotes.add('Unpaid bills! -2 reputation.');
    }
    dawnRepChange = reputation - before;

    // pick today's event (never on day 1, so the tutorial stays calm)
    dayEvent = null;
    if (e.day >= 2 && Random().nextDouble() < 0.8) {
      final pool = kDayEvents.where((x) => x.id != _lastDay).toList();
      dayEvent = pool[Random().nextInt(pool.length)];
    }
    _lastDay = dayEvent?.id ?? '';
    _bossType = isBossNight ? _drawBoss() : -1;
    _goldenTimer = 6.0;

    if (endless || outcome == GameOutcome.won) return;

    if (e.cash < debtLimit) {
      _lose('You went bankrupt. The bank took the shop.');
    } else if (reputation <= 0.5) {
      _lose('Nobody in town trusts your store anymore.');
    } else if (e.day > deadlineDay) {
      _lose('The Mega Mart bulldozers arrived. You did not buy the Land Deed in time.');
    }
  }

  void _lose(String why) {
    outcome = GameOutcome.lost;
    loseReason = why;
    outcomePending = true;
  }

  // ---- Per-frame -----------------------------------------------------------
  void update(double dt) {
    _updateFarmer(dt);
    _updateGuard(dt);
    _updateRider(dt);
    final ev = dayEvent;
    if (!e.isNight && ev?.id == 'goldencow') {
      _goldenTimer -= dt;
      if (goldenGlow > 0) goldenGlow = max(0.0, goldenGlow - dt);
      if (_goldenTimer <= 0) {
        _goldenTimer = 16.0;
        FarmProducer? barn;
        for (final f in e.farmProducers) {
          if (f.zoneType == FarmZoneType.barn && f.isUnlocked) barn = f;
        }
        if (barn != null && barn.spots.isNotEmpty) {
          final spot = barn.spots[Random().nextInt(barn.spots.length)];
          goldenSpot = spot;
          goldenGlow = 3.0;
          final pay = 35.0 + e.day * 2.0;
          e.cash += pay;
          e.playSfx('cash');
          e.spawnParticle(spot.x, spot.y - 40, 'GOLDEN MILK! +\$${pay.toStringAsFixed(0)}', Colors.amberAccent, size: 17);
        }
      }
      if (goldenGlow <= 0) goldenSpot = null;
    }

    if (ufoActive && e.isNight) {
      ufoTimer += dt;
      FarmProducer? barn;
      for (final f in e.farmProducers) {
        if (f.zoneType == FarmZoneType.barn) barn = f;
      }
      if (barn != null && barn.spots.isNotEmpty) {
        final target = barn.spots[1 % barn.spots.length];
        ufoPos = Offset(target.x + sin(ufoTimer * 1.3) * 26, target.y - 90);
        if (!_ufoAbducted && ufoTimer > 12.0) {
          _ufoAbducted = true;
          target.isReady = false;
          target.regrowTimer = 0.0;
          const pay = 140.0;
          e.cash += pay;
          e.nightBounty += pay;
          e.playSfx('cash');
          e.spawnParticle(target.x, target.y - 50, 'The aliens took a cow and left \$140!', Colors.lightGreenAccent, size: 16);
        }
      }
    }
  }

  // ---- Farms (bought separately from the shelves) --------------------------
  double farmCost(FarmProducer f) {
    final i = e.farmProducers.indexOf(f);
    return 400.0 + 120.0 * max(0, i);
  }

  bool farmShelfOpen(FarmProducer f) {
    final sh = e.shelfForProduct(f.primaryProduct);
    return sh != null && sh.isUnlocked;
  }

  String farmLockReason(FarmProducer f) {
    if (!farmShelfOpen(f)) return 'Unlock the shelf first';
    return 'Buy the farm: \$${farmCost(f).toStringAsFixed(0)}';
  }

  bool tryBuyFarm(FarmProducer f) {
    if (farmsOwned.contains(f.id)) return true;
    if (!farmShelfOpen(f)) {
      e.playSfx('error');
      e.spawnParticle(f.rect.center.dx, f.rect.center.dy - 20, 'Unlock the shelf for this product first!', Colors.orangeAccent, size: 15);
      return false;
    }
    final c = farmCost(f);
    if (e.cash < c) {
      e.playSfx('error');
      e.spawnParticle(f.rect.center.dx, f.rect.center.dy - 20, '\$${c.toStringAsFixed(0)} needed for this farm!', Colors.redAccent, size: 15);
      return false;
    }
    e.cash -= c;
    farmsOwned.add(f.id);
    f.isUnlocked = true;
    e.playSfx('cash');
    e.spawnParticle(f.rect.center.dx, f.rect.center.dy - 20, '${f.name} is yours!', Colors.greenAccent, size: 19);
    return true;
  }

  void applyFarmOwnership() {
    for (final f in e.farmProducers) {
      f.isUnlocked = farmsOwned.contains(f.id);
    }
  }

  // ---- Staff -------------------------------------------------------------
  double get rent => 30.0 + 5.0 * e.day;

  List<MapEntry<String, double>> staffWages() {
    final l = <MapEntry<String, double>>[];
    if (farmerHired) l.add(const MapEntry('Farmer', farmerWage));
    if (guardHired) l.add(const MapEntry('Night guard', guardWage));
    if (riderHired) l.add(const MapEntry('Courier rider', riderWage));
    l.add(MapEntry('Rent', rent));
    return l;
  }

  // The farm crate next to the back door: the farmer fills it, you and the stocker empty it.
  static const int crateCap = 40;
  final Map<SimProductType, int> crate = {};
  Offset get crateSpot => Offset(e.worldWidth / 2 + 215, 955);
  int get crateTotal => crate.values.fold(0, (a, b) => a + b);
  bool get crateVisible => farmerHired || crateTotal > 0;
  int crateCount(SimProductType t) => crate[t] ?? 0;

  /// Removes up to [want] items of [t] from the crate and returns how many were taken.
  int crateTake(SimProductType t, int want) {
    final n = min(want, crateCount(t));
    if (n <= 0) return 0;
    crate[t] = crateCount(t) - n;
    if (crate[t] == 0) crate.remove(t);
    return n;
  }

  /// The player takes a load (one box worth) from the crate.
  bool takeFromCrate(SimProductType t) {
    if (e.carriedBox != null) {
      e.spawnParticle(e.playerX, e.playerY - 40, 'Your hands are full!', Colors.orangeAccent, size: 14);
      e.playSfx('error');
      return false;
    }
    final def = productCatalog[t]!;
    final n = crateTake(t, def.boxSize);
    if (n <= 0) return false;
    e.carriedBox = CarriedBox(productType: t, currentCount: n, maxCount: def.boxSize);
    e.playSfx('pickup');
    return true;
  }

  final StaffHelper farmer = StaffHelper();
  final StaffHelper guard = StaffHelper();
  double _riderTimer = 0.0;

  bool get farmerVisible => farmerHired && !e.isNight;
  bool get guardVisible => guardHired && e.isNight;

  void _walk(StaffHelper h, double tx, double ty, double speed, double dt) {
    final dx = tx - h.x, dy = ty - h.y;
    final d = sqrt(dx * dx + dy * dy);
    if (d < 3) return;
    final st = min(d, speed * dt);
    h.x += dx / d * st;
    h.y += dy / d * st;
    h.walk += dt * 9;
    h.facing = dx.abs() > dy.abs() ? (dx < 0 ? 1 : 2) : (dy > 0 ? 0 : 3);
    h.moving = true;
  }

  void _updateFarmer(double dt) {
    final h = farmer;
    if (!farmerHired || e.isNight) {
      h.state = 0;
      h.x = e.worldWidth / 2 + 130;
      h.y = 1015;
      return;
    }
    h.moving = false;
    final doorX = e.worldWidth / 2;
    switch (h.state) {
      case 0: // look for a farm with something ready
        h.timer -= dt;
        if (h.timer > 0) break;
        h.timer = 2.0;
        FarmProducer? best;
        for (final f in e.farmProducers) {
          if (!f.isUnlocked) continue;
          if (crateCount(f.primaryProduct) >= crateCap) continue;
          if (f.readySpotCount >= 2 && (best == null || f.readySpotCount > best.readySpotCount)) best = f;
        }
        if (best != null) {
          h.farm = best;
          h.state = 1;
        } else {
          _walk(h, doorX + 130, 1015, 90, dt);
        }
        break;
      case 1:
        final f = h.farm!;
        _walk(h, f.rect.center.dx, f.rect.center.dy - 10, 130, dt);
        if ((h.x - f.rect.center.dx).abs() < 20 && (h.y - (f.rect.center.dy - 10)).abs() < 20) {
          h.state = 2;
          h.timer = 3.5;
        }
        break;
      case 2:
        h.timer -= dt;
        h.work += dt * 12;
        if (h.timer <= 0) {
          final f = h.farm!;
          int count = 0;
          for (final sp in f.spots) {
            if (sp.isReady) {
              sp.isReady = false;
              sp.regrowTimer = 0.0;
              sp.harvestProgress = 0.0;
              count++;
            }
          }
          h.carryCount = count;
          h.state = 3;
        }
        break;
      case 3:
        final f = h.farm!;
        final cs = crateSpot;
        // walk out of the farm to the back door first, then to the crate
        if (h.y > 1040 && (h.x - doorX).abs() > 60) {
          _walk(h, doorX, 1030, 140, dt);
        } else {
          _walk(h, cs.dx, cs.dy + 20, 140, dt);
        }
        if ((h.x - cs.dx).abs() < 25 && (h.y - (cs.dy + 20)).abs() < 25) {
          if (h.carryCount > 0) {
            final def = productCatalog[f.primaryProduct]!;
            crate[f.primaryProduct] = min(crateCap, crateCount(f.primaryProduct) + h.carryCount);
            e.spawnParticle(cs.dx, cs.dy - 40, 'Farmer: +${h.carryCount} ${def.emoji} in the crate', Colors.lightGreenAccent, size: 13);
            e.playSfx('pickup');
          }
          h.carryCount = 0;
          h.state = 0;
          h.timer = 1.0;
        }
        break;
    }
  }

  void _updateGuard(double dt) {
    final h = guard;
    h.moving = false;
    if (!guardHired || !e.isNight) {
      h.state = 0;
      h.x = e.worldWidth / 2;
      h.y = 300;
      return;
    }
    if (h.hit > 0) h.hit -= dt;
    // pick the closest thief that is still in the game
    Thief? best;
    double bd = 1e9;
    for (final t in e.thieves) {
      if (t.hp <= 0 || t.state == ThiefState.fleeing && t.carried == 0) continue;
      final d = (t.x - h.x).abs() + (t.y - h.y).abs();
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    if (best == null) {
      _walk(h, e.worldWidth / 2, 420, 100, dt);
      return;
    }
    _walk(h, best.x, best.y + 22, 150, dt);
    if (bd < 70 && h.hit <= 0 && best.phased <= 0) {
      h.hit = 1.7;
      e.guardStrike(best, h.x, h.y);
    }
  }

  void _updateRider(double dt) {
    if (!riderHired || !courierService) return;
    if (e.activeCourierOrder == null) {
      _riderTimer = 0.0;
      return;
    }
    _riderTimer += dt;
    if (_riderTimer > 14.0) {
      _riderTimer = 0.0;
      e.courierRiderTry();
    }
  }

  // ---- Music ---------------------------------------------------------------
  static const Map<String, String> _eventMusic = {
    'festival': 'cheer', 'lucky': 'cheer', 'sale': 'cheer', 'blogger': 'cheer', 'goldencow': 'cheer',
    'rain': 'rain', 'heat': 'heat', 'fog': 'fog', 'omen': 'fog', 'cursedgold': 'dusk',
    'inspector': 'tense', 'shortage': 'tense', 'megaflyer': 'tense',
    'fullmoon': 'dread', 'gang': 'tense', 'quiet': 'night', 'raccoons': 'raccoon', 'bounty': 'tense',
    'ufo': 'ufo', 'eldritch': 'eldritch', 'poltergeist': 'poltergeist', 'cult': 'ritual', 'bloodmoon': 'bloodmoon',
  };

  String get musicTrack {
    if (e.isNight) {
      if (bossAlive) return const ['boss', 'boss1', 'boss2', 'boss3'][bossType];
      final ev = nightEvent;
      if (ev != null) return _eventMusic[ev.id] ?? 'night';
      return e.day >= 15 ? 'dread' : 'night';
    }
    final ev = dayEvent;
    if (ev != null) return _eventMusic[ev.id] ?? 'day';
    return e.day >= 12 ? 'dusk' : 'day';
  }

  // ---- Save / load -----------------------------------------------------------
  Map<String, dynamic> toJson() => {
        'rep': reputation,
        'deedPaid': deedPaid,
        'endless': endless,
        'bosses': bossesDefeated,
        'served': customersServed,
        'lost': customersLost,
        'upgrades': upgrades,
        'furniture': furniture.toList(),
        'farms': farmsOwned.toList(),
        'farmer': farmerHired,
        'guard': guardHired,
        'rider': riderHired,
        'adDays': adDays,
        'intro': introShown,
        'crate': {for (final en in crate.entries) en.key.name: en.value},
        'bossType': _bossType,
        'bossBag': _bossBag,
        'dayEvent': dayEvent?.id,
      };

  void fromJson(Map<String, dynamic> m) {
    reputation = (m['rep'] as num?)?.toDouble() ?? startReputation;
    deedPaid = (m['deedPaid'] as num?)?.toDouble() ?? 0.0;
    endless = m['endless'] == true;
    bossesDefeated = (m['bosses'] as num?)?.toInt() ?? 0;
    customersServed = (m['served'] as num?)?.toInt() ?? 0;
    customersLost = (m['lost'] as num?)?.toInt() ?? 0;
    upgrades.clear();
    final u = m['upgrades'];
    if (u is Map) {
      u.forEach((k, v) {
        if (v is num) upgrades['$k'] = v.toInt();
      });
    }
    furniture.clear();
    final f = m['furniture'];
    if (f is List) furniture.addAll(f.map((x) => '$x'));
    farmsOwned.clear();
    final fo = m['farms'];
    if (fo is List) farmsOwned.addAll(fo.map((x) => '$x'));
    farmerHired = m['farmer'] == true;
    guardHired = m['guard'] == true;
    riderHired = m['rider'] == true;
    adDays = (m['adDays'] as num?)?.toInt() ?? 0;
    introShown = m['intro'] == true;
    crate.clear();
    final cr = m['crate'];
    if (cr is Map) {
      for (final t in SimProductType.values) {
        final v = cr[t.name];
        if (v is num && v > 0) crate[t] = v.toInt();
      }
    }
    _bossType = (m['bossType'] as num?)?.toInt() ?? -1;
    _bossBag.clear();
    final bb = m['bossBag'];
    if (bb is List) _bossBag.addAll(bb.whereType<num>().map((x) => x.toInt()));
    applyFarmOwnership();
    final de = m['dayEvent'];
    dayEvent = null;
    for (final x in kDayEvents) {
      if (x.id == de) dayEvent = x;
    }
    outcome = GameOutcome.playing;
    outcomePending = false;
    applyShelfCaps();
  }
}

/// A walking helper (farmer / night guard) with a tiny state machine.
class StaffHelper {
  double x = 1130;
  double y = 1015;
  int facing = 0;
  double walk = 0.0;
  double work = 0.0;
  bool moving = false;
  int state = 0;
  double timer = 0.0;
  double hit = 0.0;
  int carryCount = 0;
  FarmProducer? farm;
}
