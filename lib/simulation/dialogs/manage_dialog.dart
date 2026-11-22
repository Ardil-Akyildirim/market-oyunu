import 'package:material_ui/material_ui.dart';
import '../simulation_engine.dart';

class ManageStoreDialog extends StatefulWidget {
  final SimulationEngine engine;

  const ManageStoreDialog({super.key, required this.engine});

  @override
  State<ManageStoreDialog> createState() => _ManageStoreDialogState();
}

class _ManageStoreDialogState extends State<ManageStoreDialog> {
  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final upgradeCost = engine.nextLevelUpgradeCost;
    final canUpgradeLevel = engine.cash >= upgradeCost;
    final isCashierUnlocked = engine.storeLevel >= 2;
    final isRestockerUnlocked = engine.storeLevel >= 3;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
      backgroundColor: const Color(0xFFE9DFC6),
      child: Container(
        width: 490,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('⚙️', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Management & Staff (Level ${engine.storeLevel})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Text(
                        'Level up to unlock the Cashier and the Stocker!',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 20),

            // 1. Dükkan Seviye Atlama Kartı
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.orange.shade300, width: 1.5),
              ),
              child: Row(
                children: [
                  const Text('🏬', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upgrade Store Level (Level ${engine.storeLevel} ➔ ${engine.storeLevel + 1})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          engine.storeLevel == 1
                              ? '🔓 Level 2 expands the store, opens the 2nd Checkout Counter and the Auto Cashier (Ayşe)!'
                              : (engine.storeLevel == 2
                                  ? '🔓 Level 3 expands the store again and opens the 3rd Checkout Counter and Stocker Ali!'
                                  : 'Increases customer capacity and income rate (3/3 Counters Open).'),
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: canUpgradeLevel
                        ? () {
                            setState(() {
                              engine.cash -= upgradeCost;
                              engine.storeLevel++;
                              final opened = engine.refreshShelfUnlocks();
                              for (final name in opened) {
                                engine.spawnParticle(engine.playerX, engine.playerY - 64, '🆕 $name is now on sale!', Colors.lightGreenAccent, size: 16);
                              }
                              engine.spawnParticle(
                                engine.playerX,
                                engine.playerY - 40,
                                '🎉 Store Reached Level ${engine.storeLevel}!',
                                Colors.amberAccent,
                                size: 18,
                              );
                              if (engine.storeLevel <= 3) {
                                final newCounter = engine.checkoutCounters[engine.storeLevel - 1];
                                engine.spawnParticle(
                                  newCounter.center.dx,
                                  newCounter.top - 16,
                                  '🔓 🛎️ Register ${engine.storeLevel} Is Now Open!',
                                  Colors.greenAccent,
                                  size: 18,
                                );
                              }
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Level Up (\$${upgradeCost.toStringAsFixed(0)})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 2. Otomatik Kasiyer Kartı (Seviye 2'de Açılır)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isCashierUnlocked ? Colors.purple.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: isCashierUnlocked ? Colors.purple.shade200 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Text('👩‍💼', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Auto Cashier (Ayşe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCashierUnlocked ? Colors.purple.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                'Level 2',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isCashierUnlocked ? Colors.purple.shade900 : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          !isCashierUnlocked
                              ? '🔒 Upgrade the store to Level 2 first to hire a cashier.'
                              : (engine.hasAutoCashier
                                  ? 'The cashier works the register and rings up customers automatically!'
                                  : 'They collect customer payments automatically while you restock and guard the shop.'),
                          style: TextStyle(fontSize: 11, color: isCashierUnlocked ? Colors.purple.shade900 : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  if (!isCashierUnlocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: const Text('🔒 Level 2 Required', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else if (!engine.hasAutoCashier)
                    ElevatedButton(
                      onPressed: engine.cash >= 250
                          ? () {
                              setState(() {
                                engine.cash -= 250;
                                engine.hasAutoCashier = true;
                                engine.spawnParticle(
                                  engine.checkoutCounter.center.dx,
                                  engine.checkoutCounter.top - 20,
                                  '👩‍💼 Cashier Ayşe Started Working!',
                                  Colors.greenAccent,
                                  size: 16,
                                );
                              });
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Hire (\$250)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Text('Working ✅', style: TextStyle(color: Colors.green.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3. Otomatik Reyon & Çiftlik Görevlisi (Stokçu Ali - Seviye 3'te Açılır)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isRestockerUnlocked ? Colors.cyan.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: isRestockerUnlocked ? Colors.cyan.shade200 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Text('👷', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Shelf Attendant (Stocker Ali)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isRestockerUnlocked ? Colors.cyan.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                'Level 3',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isRestockerUnlocked ? Colors.cyan.shade900 : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          !isRestockerUnlocked
                              ? '🔒 Upgrade the store to Level 3 first to hire Stocker Ali.'
                              : (engine.isRestockerHired
                                  ? 'Picks up delivered boxes and fills the shelves for you!'
                                  : 'Picks up delivered boxes and fills the shelves automatically.'),
                          style: TextStyle(fontSize: 11, color: isRestockerUnlocked ? Colors.cyan.shade900 : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  if (!isRestockerUnlocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: const Text('🔒 Level 3 Required', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else if (!engine.isRestockerHired)
                    ElevatedButton(
                      onPressed: engine.cash >= 350
                          ? () {
                              setState(() {
                                engine.cash -= 350;
                                engine.isRestockerHired = true;
                                engine.hasRestocker = true;
                                engine.spawnParticle(
                                  engine.restocker.x,
                                  engine.restocker.y - 30,
                                  '👷 Stocker Ali Started Working!',
                                  Colors.cyanAccent,
                                  size: 16,
                                );
                              });
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan.shade700,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Hire (\$350)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    Switch(
                      value: engine.hasRestocker,
                      activeThumbColor: Colors.cyan.shade700,
                      onChanged: (val) {
                        setState(() {
                          engine.hasRestocker = val;
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
