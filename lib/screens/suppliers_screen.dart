import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../providers/game_provider.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Bilgilendirme Kartı
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              const Text('🚛', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tedarik Zinciri & Toptancılar',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tedarikçilerle sözleşme imzalayarak ürünleri indirimli ve kamyonla toptan getirtin!',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Tedarikçi Kartları
        ...game.suppliers.map((supplier) => _buildSupplierCard(context, game, supplier)),
      ],
    );
  }

  Widget _buildSupplierCard(BuildContext context, GameProvider game, Supplier supplier) {
    final canContract = game.cash >= supplier.contractCost;
    final canUpgrade = game.cash >= supplier.upgradeCost;

    // Tedarikçinin getirdiği ürünlerin emojilerini bul
    final productEmojis = supplier.supportedProductIds.map((pid) {
      final p = game.products.firstWhere((prod) => prod.id == pid, orElse: () => game.products.first);
      return p.emoji;
    }).join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: supplier.isContracted ? Colors.green.shade200 : Colors.grey.shade300,
          width: supplier.isContracted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(supplier.avatar, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              // İsim ve Unvan
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          supplier.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (supplier.isContracted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Sözleşmeli',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      supplier.title,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              // Geliştir Butonu (Eğer sözleşmeli ise)
              if (supplier.isContracted)
                OutlinedButton(
                  onPressed: canUpgrade ? () => game.upgradeSupplier(supplier) : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: canUpgrade ? Colors.orange.shade600 : Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Seviye ${supplier.level + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(
                        '₺${supplier.upgradeCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: canUpgrade ? Colors.orange.shade800 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            supplier.description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),

          // Tedarik Ürünleri ve İndirim / Hız Bilgisi
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Ürünler: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(productEmojis, style: const TextStyle(fontSize: 14)),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'İndirim: %${(supplier.discountRate * 100).toInt()}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '⏱️ ${supplier.deliveryTimeSeconds}sn',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Aksiyon Butonu: Sözleşme İmzala VEYA Sevkiyat Başlat
          if (!supplier.isContracted)
            ElevatedButton(
              onPressed: canContract ? () => game.signSupplierContract(supplier) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Sözleşme İmzala (₺${supplier.contractCost.toStringAsFixed(0)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          else ...[
            if (supplier.isDelivering)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '🚚 Kamyon Yolda! Kalan: ${supplier.deliveryRemainingSeconds} saniye',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 1.0 - (supplier.deliveryRemainingSeconds / supplier.deliveryTimeSeconds),
                          minHeight: 6,
                          backgroundColor: Colors.blue.shade200,
                          valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () => game.orderFromSupplier(supplier),
                icon: const Icon(Icons.local_shipping, size: 18),
                label: const Text('Toplu Kamyon Sevkiyatı Başlat 🚛', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
