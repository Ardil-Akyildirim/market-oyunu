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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
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
                        'Market Yönetimi & Personel (Seviye ${engine.storeLevel})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Text(
                        'Seviye atlayarak Kasiyer ve Stokçu kilidini açın!',
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
                borderRadius: BorderRadius.circular(14),
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
                          'Market Seviyesini Yükselt (Seviye ${engine.storeLevel} ➔ ${engine.storeLevel + 1})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          engine.storeLevel == 1
                              ? '🔓 Seviye 2\'de 2. Kasa Tezgahı ve Otomatik Kasiyer (Ayşe) açılır!'
                              : (engine.storeLevel == 2
                                  ? '🔓 Seviye 3\'te 3. Kasa Tezgahı ve Stokçu Ali kilidi açılır!'
                                  : 'Müşteri kapasitesini ve gelir hızını artırır (3/3 Kasa Açık).'),
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
                              engine.spawnParticle(
                                engine.playerX,
                                engine.playerY - 40,
                                '🎉 Market Seviye ${engine.storeLevel} Oldu!',
                                Colors.amberAccent,
                                size: 18,
                              );
                              if (engine.storeLevel <= 3) {
                                final newCounter = engine.checkoutCounters[engine.storeLevel - 1];
                                engine.spawnParticle(
                                  newCounter.center.dx,
                                  newCounter.top - 16,
                                  '🔓 🛎️ Kasa ${engine.storeLevel} Hizmete Açıldı!',
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
                      'Seviye Atla (₺${upgradeCost.toStringAsFixed(0)})',
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
                borderRadius: BorderRadius.circular(14),
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
                            const Text('Otomatik Kasiyer (Ayşe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCashierUnlocked ? Colors.purple.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Seviye 2',
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
                              ? '🔒 Kasiyer işe almak için önce marketi Seviye 2\'ye yükseltin.'
                              : (engine.hasAutoCashier
                                  ? 'Kasiyer kasada çalışıyor, müşterileri otomatik geçiriyor!'
                                  : 'Sen çiftlikteyken müşterilerin ödemesini kasada otomatik alır.'),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('🔒 Seviye 2 Gerekli', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                                  '👩‍💼 Kasiyer Ayşe İşe Başladı!',
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
                      child: const Text('İşe Al (₺250)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Çalışıyor ✅', style: TextStyle(color: Colors.green.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
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
                borderRadius: BorderRadius.circular(14),
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
                            const Text('Çiftlik & Reyon Görevlisi (Stokçu Ali)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isRestockerUnlocked ? Colors.cyan.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Seviye 3',
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
                              ? '🔒 Stokçu Ali\'yi işe almak için marketi Seviye 3\'e yükseltin.'
                              : (engine.isRestockerHired
                                  ? 'Tırpanla buğday biçiyor, süt sağıyor, peynir yapıyor ve rafları dolduruyor!'
                                  : 'Çiftlikte tırpan/kova ile hasat yapıp rafları otomatik doldurur.'),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('🔒 Seviye 3 Gerekli', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                                  '👷 Stokçu Ali İşe Başladı!',
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
                      child: const Text('İşe Al (₺350)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
