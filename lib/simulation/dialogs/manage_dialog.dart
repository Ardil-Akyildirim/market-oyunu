import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../../widgets/pixel_ui.dart';
import '../game_rules.dart';
import '../simulation_engine.dart';
import '../simulation_models.dart';

class ManageStoreDialog extends StatefulWidget {
  final SimulationEngine engine;
  final int initialTab;

  const ManageStoreDialog({super.key, required this.engine, this.initialTab = 0});

  @override
  State<ManageStoreDialog> createState() => _ManageStoreDialogState();
}

class _ManageStoreDialogState extends State<ManageStoreDialog> {
  late int _tab = widget.initialTab;

  SimulationEngine get engine => widget.engine;
  GameRules get rules => engine.rules;

  static String _m(double v) => '\$${v.toStringAsFixed(0)}';

  Widget _card({
    required String icon,
    required String title,
    required String desc,
    required Color color,
    required Color border,
    Widget? action,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color, border: Border.all(color: border, width: 1.5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: Colors.amber.shade100,
                        child: Text(badge,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF3B2F28))),
                if (action != null) ...[const SizedBox(height: 6), action],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onTap, {Color color = const Color(0xFF2F8A3C)}) {
    return ElevatedButton(
      onPressed: onTap == null
          ? null
          : () {
              setState(onTap);
            },
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: bg,
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  // ------------------------------------------------------------------ tabs
  Widget _tabBar() {
    const names = ['Store', 'Staff', 'Upgrades', 'Furniture', 'Mega Mart'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 0; i < names.length; i++)
          PixelPress(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _tab == i ? const Color(0xFFB4442F) : const Color(0xFFE3D3B0),
                border: Border.all(color: const Color(0xFF14100E), width: 2),
              ),
              child: Text(names[i],
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: _tab == i ? Colors.white : const Color(0xFF3B2F28))),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- store tab
  List<Widget> _storeTab() {
    final upgradeCost = engine.nextLevelUpgradeCost;
    return [
      _card(
        icon: '{shop}',
        title: 'Store Level ${engine.storeLevel}',
        desc: engine.storeLevel == 1
            ? 'Level 2: bigger store, 2nd register, Stocker, more upgrades.'
            : (engine.storeLevel == 2
                ? 'Level 3: even bigger, 3rd register, and the Cashier can be hired.'
                : 'More customers at once and more income.'),
        color: Colors.orange.shade50,
        border: Colors.orange.shade300,
        action: _btn('Level Up (${_m(upgradeCost)})', engine.cash >= upgradeCost
            ? () {
                engine.cash -= upgradeCost;
                engine.storeLevel++;
                final opened = engine.refreshShelfUnlocks();
                for (final name in opened) {
                  engine.spawnParticle(engine.playerX, engine.playerY - 64, '{star} $name is now on sale!', Colors.lightGreenAccent, size: 16);
                }
                engine.spawnParticle(engine.playerX, engine.playerY - 40, '{star} Store Reached Level ${engine.storeLevel}!', Colors.amberAccent, size: 18);
                if (engine.storeLevel <= 3) {
                  final newCounter = engine.checkoutCounters[engine.storeLevel - 1];
                  engine.spawnParticle(newCounter.center.dx, newCounter.top - 16, '{unlock} {bell} Register ${engine.storeLevel} Is Now Open!', Colors.greenAccent, size: 18);
                }
              }
            : null, color: Colors.orange.shade600),
      ),
      const SizedBox(height: 4),
      const Text('New Fields & Shelves', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      const SizedBox(height: 8),
      ...engine.shelves.where((s) => s.unlockCost > 0).map((shelf) {
        final def = productCatalog[shelf.assignedProduct]!;
        final farm = engine.farmForProduct(shelf.assignedProduct);
        final levelMet = engine.storeLevel >= shelf.zoneLevel;
        final canBuy = !shelf.isUnlocked && levelMet && engine.cash >= shelf.unlockCost;
        return _card(
          icon: def.ico,
          title: '${farm?.name ?? def.name} & ${shelf.name}',
          desc: shelf.isUnlocked
              ? 'Open! Harvest it with the tool at the farm.'
              : 'Needs level ${shelf.zoneLevel} - sells for ${_m(def.retailPrice)}',
          color: shelf.isUnlocked ? Colors.green.shade50 : (levelMet ? Colors.amber.shade50 : Colors.grey.shade100),
          border: shelf.isUnlocked ? Colors.green.shade300 : (levelMet ? Colors.amber.shade400 : Colors.grey.shade300),
          action: shelf.isUnlocked
              ? _tag('Open {check}', Colors.green.shade100, Colors.green.shade900)
              : (!levelMet
                  ? _tag('{lock} Level ${shelf.zoneLevel}', Colors.grey.shade300, Colors.black87)
                  : _btn('Unlock (${_m(shelf.unlockCost)})', canBuy ? () => engine.tryUnlockShelfOrFarm(shelf) : null)),
        );
      }),
      const SizedBox(height: 6),
      const Text('Farms (bought separately)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      const SizedBox(height: 4),
      const Text('A farm needs its product shelf first. Harvest by hand or hire a Farmer.',
          style: TextStyle(fontSize: 12, color: Color(0xFF3B2F28))),
      const SizedBox(height: 8),
      ...engine.farmProducers.map((farm) {
        final owned = farm.isUnlocked;
        final shelfOk = rules.farmShelfOpen(farm);
        final cost = rules.farmCost(farm);
        return _card(
          icon: productCatalog[farm.primaryProduct]!.ico,
          title: farm.name,
          desc: owned ? 'Yours! Harvest with the tool at the farm.' : (shelfOk ? 'Ready to buy.' : 'Unlock its shelf first.'),
          color: owned ? Colors.green.shade50 : (shelfOk ? Colors.amber.shade50 : Colors.grey.shade100),
          border: owned ? Colors.green.shade300 : (shelfOk ? Colors.amber.shade400 : Colors.grey.shade300),
          action: owned
              ? _tag('Owned {check}', Colors.green.shade100, Colors.green.shade900)
              : (!shelfOk
                  ? _tag('{lock} Shelf locked', Colors.grey.shade300, Colors.black87)
                  : _btn('Buy farm (${_m(cost)})', engine.cash >= cost ? () => rules.tryBuyFarm(farm) : null)),
        );
      }),
    ];
  }

  // ------------------------------------------------------------- staff tab
  Widget _hireCard({
    required String icon,
    required String title,
    required String desc,
    required bool unlocked,
    required String lockText,
    required bool hired,
    required double cost,
    required String wageText,
    required VoidCallback onHire,
    Widget? hiredExtra,
    Color tint = const Color(0xFFE8F4FF),
  }) {
    return _card(
      icon: icon,
      title: title,
      desc: unlocked ? '$desc $wageText' : lockText,
      color: unlocked ? tint : Colors.grey.shade100,
      border: unlocked ? Colors.blueGrey.shade300 : Colors.grey.shade300,
      action: !unlocked
          ? _tag('{lock} Locked', Colors.grey.shade300, Colors.black87)
          : (hired
              ? (hiredExtra ?? _tag('Working {check}', Colors.green.shade100, Colors.green.shade900))
              : _btn('Hire (${_m(cost)})', engine.cash >= cost ? onHire : null, color: Colors.blueGrey.shade700)),
    );
  }

  List<Widget> _staffTab() {
    final stockerOk = engine.storeLevel >= GameRules.stockerMinLevel;
    final n = engine.cashierCount;
    final nextCashierOk = n < 3 && engine.storeLevel >= GameRules.cashierMinLevel && n < engine.unlockedCheckoutCount;
    final cashierCost = n < 3 ? GameRules.cashierCosts[n] : 0.0;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          '{coin} Wages and rent are paid every dawn: ${_m(engine.dailyWages)} per day right now. Rent grows every day.',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7A3E12)),
        ),
      ),
      _card(
        icon: '{face}',
        title: 'Cashiers ($n/3)',
        badge: 'Level ${GameRules.cashierMinLevel}',
        desc: engine.storeLevel < GameRules.cashierMinLevel
            ? '{lock} Reach store level ${GameRules.cashierMinLevel}. One cashier per register, ${_m(SimulationEngine.wageCashier)}/day each.'
            : 'One cashier per register: each rings up the first customer in their own queue. ${_m(SimulationEngine.wageCashier)}/day each.',
        color: Colors.purple.shade50,
        border: Colors.purple.shade200,
        action: n >= 3
            ? _tag('All registers staffed {check}', Colors.green.shade100, Colors.green.shade900)
            : (!nextCashierOk
                ? _tag(engine.storeLevel < GameRules.cashierMinLevel ? '{lock} Level ${GameRules.cashierMinLevel}' : '{lock} Open register ${n + 1} first', Colors.grey.shade300, Colors.black87)
                : _btn('Hire cashier for register ${n + 1} (${_m(cashierCost)})', engine.cash >= cashierCost
                    ? () {
                        engine.cash -= cashierCost;
                        engine.cashierCount++;
                        engine.spawnParticle(engine.checkoutCounters[n].center.dx, engine.checkoutCounters[n].top - 20, '{face} Cashier ${n + 1} started working!', Colors.greenAccent, size: 16);
                      }
                    : null, color: Colors.purple.shade600)),
      ),
      _card(
        icon: '{hardhat}',
        title: 'Stocker',
        badge: 'Level ${GameRules.stockerMinLevel}',
        desc: !stockerOk
            ? '{lock} Reach store level ${GameRules.stockerMinLevel} to hire.'
            : 'Carries boxes from the floor to the shelves. Does NOT work the farm. Wage ${_m(SimulationEngine.wageRestocker)}/day.',
        color: stockerOk ? Colors.cyan.shade50 : Colors.grey.shade100,
        border: stockerOk ? Colors.cyan.shade200 : Colors.grey.shade300,
        action: !stockerOk
            ? null
            : (engine.isRestockerHired
                ? SizedBox(
                    width: 150,
                    child: PixelToggle(
                      label: 'On duty',
                      value: engine.hasRestocker,
                      onChanged: (v) => setState(() => engine.hasRestocker = v),
                    ),
                  )
                : _btn('Hire (${_m(GameRules.stockerHireCost)})', engine.cash >= GameRules.stockerHireCost
                    ? () {
                        engine.cash -= GameRules.stockerHireCost;
                        engine.isRestockerHired = true;
                        engine.hasRestocker = true;
                        engine.spawnParticle(engine.restocker.x, engine.restocker.y - 30, '{hardhat} Stocker started working!', Colors.cyanAccent, size: 16);
                      }
                    : null, color: Colors.cyan.shade700)),
      ),
      _hireCard(
        icon: '{hardhat}',
        title: 'Farmer',
        desc: 'Harvests your farms and leaves the boxes at the back door; the stocker stacks them.',
        unlocked: engine.farmProducers.any((f) => f.isUnlocked) && engine.storeLevel >= 2,
        lockText: '{lock} Buy a farm and reach store level 2.',
        hired: rules.farmerHired,
        cost: GameRules.farmerCost,
        wageText: 'Wage ${_m(GameRules.farmerWage)}/day.',
        onHire: () => rules.farmerHired = true,
        tint: Colors.lightGreen.shade50,
      ),
      _hireCard(
        icon: '{thief}',
        title: 'Night Guard',
        desc: 'Patrols at night and beats thieves with a baton.',
        unlocked: engine.day >= 4,
        lockText: '{lock} Available from day 4.',
        hired: rules.guardHired,
        cost: GameRules.guardCost,
        wageText: 'Wage ${_m(GameRules.guardWage)}/day.',
        onHire: () => rules.guardHired = true,
        tint: Colors.indigo.shade50,
      ),
      _hireCard(
        icon: '{bike}',
        title: 'Courier Rider',
        desc: 'Delivers courier orders from the shelf stock automatically (65% of the reward).',
        unlocked: rules.courierService,
        lockText: '{lock} Buy the Courier Service upgrade first.',
        hired: rules.riderHired,
        cost: GameRules.riderCost,
        wageText: 'Wage ${_m(GameRules.riderWage)}/day.',
        onHire: () => rules.riderHired = true,
        tint: Colors.amber.shade50,
      ),
    ];
  }

  // -------------------------------------------------------- upgrades tab
  List<Widget> _upgradesTab() {
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('Permanent upgrades. Some need a bigger store or a later day.',
            style: TextStyle(fontSize: 12, color: Color(0xFF7A3E12), fontWeight: FontWeight.bold)),
      ),
      for (final u in kUpgrades) _upgradeCard(u),
    ];
  }

  Widget _upgradeCard(UpgradeDef u) {
    final l = rules.lvl(u.id);
    final maxed = u.id != 'ads' && l >= u.maxLevel;
    final needLevel = engine.storeLevel < u.minStoreLevel;
    final needDay = engine.day < u.minDay;
    final needCashier = u.id == 'training' && !engine.hasAutoCashier;
    String desc = maxed ? u.descs.last : u.descs[l];
    String? lockMsg;
    if (needLevel) {
      lockMsg = '{lock} Store level ${u.minStoreLevel} needed';
    } else if (needDay) {
      lockMsg = '{lock} Available from day ${u.minDay}';
    } else if (needCashier) {
      lockMsg = '{lock} Hire the cashier first';
    }
    return _card(
      icon: '{star}',
      title: u.name,
      badge: u.id == 'ads' ? (rules.adDays > 0 ? 'Running' : 'Repeatable') : 'Lv $l/${u.maxLevel}',
      desc: desc,
      color: maxed ? Colors.green.shade50 : Colors.amber.shade50,
      border: maxed ? Colors.green.shade300 : Colors.amber.shade400,
      action: maxed
          ? _tag('Maxed {check}', Colors.green.shade100, Colors.green.shade900)
          : (lockMsg != null
              ? _tag(lockMsg, Colors.grey.shade300, Colors.black87)
              : _btn('Buy (${_m(u.costs[l])})', rules.canBuyUpgrade(u) ? () => rules.buyUpgrade(u) : null)),
    );
  }

  // -------------------------------------------------------- furniture tab
  List<Widget> _furnitureTab() {
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('Call the furniture shop: the van delivers right away and the piece appears in your store (along the walls).',
            style: TextStyle(fontSize: 12, color: Color(0xFF7A3E12), fontWeight: FontWeight.bold)),
      ),
      for (final f in kFurniture)
        _card(
          icon: '{box}',
          title: f.name,
          desc: f.perk,
          color: rules.furniture.contains(f.id) ? Colors.green.shade50 : Colors.amber.shade50,
          border: rules.furniture.contains(f.id) ? Colors.green.shade300 : Colors.amber.shade400,
          action: rules.furniture.contains(f.id)
              ? _tag('In your store {check}', Colors.green.shade100, Colors.green.shade900)
              : _btn('Order (${_m(f.cost)})', engine.cash >= f.cost ? () => rules.buyFurniture(f) : null),
        ),
    ];
  }

  // ------------------------------------------------------- mega mart tab
  List<Widget> _megaTab() {
    final remaining = rules.deedRemaining;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFE3D0), border: Border.all(color: const Color(0xFFB4442F), width: 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The Mega Mart is coming!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'They will demolish your store after day ${GameRules.deadlineDay}. Buy the Land Deed before then to save it.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('{coin} Land Deed: ${_m(rules.deedPrice)}  (paid ${_m(rules.deedPaid)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              height: 14,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF14100E), width: 2)),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: rules.deedProgress.clamp(0.0, 1.0).toDouble(),
                  child: Container(color: const Color(0xFF2F8A3C)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('{star} Reputation ${rules.reputation.toStringAsFixed(0)}/100. Higher reputation makes the deed cheaper (up to -25%).',
                style: const TextStyle(fontSize: 12)),
            Text('Days left: ${rules.daysLeft}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final amount in const [250.0, 500.0, 1000.0])
            _btn('Pay ${_m(amount)}', engine.cash >= amount && remaining > 0 ? () => rules.payDeed(amount) : null,
                color: const Color(0xFFB4442F)),
          _btn('Pay all you can', engine.cash > 0 && remaining > 0 ? () => rules.payDeed(engine.cash) : null,
              color: const Color(0xFF7A3E12)),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'You can pay in installments at any time. You lose if the deadline passes, if you go too deep into debt, or if your reputation hits zero.',
        style: TextStyle(fontSize: 12, color: Color(0xFF3B2F28)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      1 => _staffTab(),
      2 => _upgradesTab(),
      3 => _furnitureTab(),
      4 => _megaTab(),
      _ => _storeTab(),
    };
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        width: min(500.0, MediaQuery.of(context).size.width - 24),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - 16),
        decoration: pixelDeco(kParchment, bw: 4, shadow: 6),
        padding: EdgeInsets.all(MediaQuery.of(context).size.height < 500 ? 10 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('{gear}', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Manager  -  Cash ${_m(engine.cash)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: PixelIcon('x', size: 24, dark: true),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _tabBar(),
            const Divider(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
