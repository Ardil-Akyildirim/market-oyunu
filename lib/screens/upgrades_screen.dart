import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../models/upgrade.dart';
import '../providers/game_provider.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final canLevelUp = game.nextLevelCost > 0 && game.cash >= game.nextLevelCost;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Market Seviyesi ve Büyütme Vitrini
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.deepOrange.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'MARKET DURUMU',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Seviye ${game.marketLevel} / 5',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                game.marketTitle,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                game.nextLevelCost > 0
                    ? 'Dükkanı büyütüp yeni reyonlar ve toptancı sözleşmeleri açın!'
                    : 'Tebrikler! En büyük Hipermarket seviyesine ulaştınız!',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 14),

              if (game.nextLevelCost > 0)
                ElevatedButton(
                  onPressed: canLevelUp ? () => game.levelUpMarket() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepOrange.shade800,
                    disabledBackgroundColor: Colors.white38,
                    disabledForegroundColor: Colors.white60,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    canLevelUp
                        ? 'DÜKKANI BÜYÜT 🎉 (₺${game.nextLevelCost.toStringAsFixed(0)})'
                        : 'Büyütmek İçin: ₺${game.nextLevelCost.toStringAsFixed(0)} Gerekli',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          '🏪 Mağaza İnovasyonları & Yatırımlar',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        // Yükseltme Kartları
        ...game.upgrades.map((upgrade) => _buildUpgradeCard(context, game, upgrade)),
      ],
    );
  }

  Widget _buildUpgradeCard(BuildContext context, GameProvider game, Upgrade upgrade) {
    final canBuy = game.cash >= upgrade.cost && !upgrade.isPurchased;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: upgrade.isPurchased ? Colors.green.shade300 : Colors.grey.shade200,
          width: upgrade.isPurchased ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: upgrade.isPurchased ? Colors.green.shade50 : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(upgrade.icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upgrade.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  upgrade.description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          if (upgrade.isPurchased)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Kuruldu ✅',
                style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          else
            ElevatedButton(
              onPressed: canBuy ? () => game.purchaseUpgrade(upgrade) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                '₺${upgrade.cost.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
