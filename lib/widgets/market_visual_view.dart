import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class MarketVisualView extends StatelessWidget {
  const MarketVisualView({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    // Yolda olan tedarikçiler
    final deliveringSuppliers = game.suppliers.where((s) => s.isDelivering).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade50,
            Colors.orange.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.12),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.orange.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve İtibar Barı
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('🏪', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.marketTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      Text(
                        'Seviye ${game.marketLevel} • %${game.marketReputation.toStringAsFixed(0)} Memnuniyet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Canlı müşteri sayısı rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: game.customers.isNotEmpty ? Colors.green.shade600 : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${game.customers.length} Müşteri',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Canlı Kasa Tezgahı ve Bekleyen Müşteriler Kuyruğu
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Text('🛎️ Kasa & Siparişler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    if (game.customers.isNotEmpty)
                      Text(
                        'Sıradaki: ${game.customers.first.name}',
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Kuyruk Görünümü
                if (game.customers.isEmpty)
                  Container(
                    height: 75,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🛒', style: TextStyle(fontSize: 24)),
                        const SizedBox(height: 4),
                        Text(
                          'Müşteriler reyonları inceliyor, birazdan kasaya gelirler...',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: game.customers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final customer = entry.value;
                        final prod = game.products.firstWhere(
                          (p) => p.id == customer.wantedProductId,
                          orElse: () => game.products.first,
                        );

                        return Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: index == 0 ? Colors.orange.shade50 : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: index == 0 ? Colors.orange.shade400 : Colors.grey.shade300,
                              width: index == 0 ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              // İstek Baloncuğu
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4),
                                  ],
                                ),
                                child: Text(
                                  '${prod.emoji} x${customer.wantedAmount}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Müşteri Avatarı
                              Text(customer.avatar, style: const TextStyle(fontSize: 26)),
                              const SizedBox(height: 2),
                              Text(
                                customer.name.split(' ').first,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                              // Bekleme Çubuğu
                              const SizedBox(height: 3),
                              SizedBox(
                                width: 50,
                                height: 3,
                                child: LinearProgressIndicator(
                                  value: 1.0 - customer.waitProgress,
                                  backgroundColor: Colors.red.shade200,
                                  valueColor: AlwaysStoppedAnimation(
                                    customer.waitProgress > 0.7 ? Colors.red : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 10),

                // Büyük Hızlı Satış Butonu
                ElevatedButton(
                  onPressed: game.customers.isEmpty
                      ? null
                      : () {
                          game.checkoutNextCustomer();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      Text(
                        game.customers.isEmpty
                            ? 'Müşteri Bekleniyor...'
                            : 'KASADAN GEÇİR & SAT (+₺${_calculateFirstCustomerTotal(game).toStringAsFixed(1)})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tedarikçi Sevkiyat Bildirimi (Kamyon Yolda)
          if (deliveringSuppliers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: deliveringSuppliers.map((supplier) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        const Text('🚚💨', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${supplier.name} yolda... (${supplier.deliveryRemainingSeconds} sn)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          height: 4,
                          child: LinearProgressIndicator(
                            value: 1.0 - (supplier.deliveryRemainingSeconds / supplier.deliveryTimeSeconds),
                            backgroundColor: Colors.blue.shade100,
                            valueColor: AlwaysStoppedAnimation(Colors.blue.shade600),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Son Olay Bildirimleri (Floating Akış)
          if (game.recentEvents.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    game.recentEvents.first.isPositive ? Icons.check_circle_outline : Icons.info_outline,
                    size: 14,
                    color: game.recentEvents.first.isPositive ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      game.recentEvents.first.text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: game.recentEvents.first.isPositive ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _calculateFirstCustomerTotal(GameProvider game) {
    if (game.customers.isEmpty) return 0.0;
    final c = game.customers.first;
    final prod = game.products.firstWhere((p) => p.id == c.wantedProductId, orElse: () => game.products.first);
    return c.wantedAmount * prod.sellPrice;
  }
}
