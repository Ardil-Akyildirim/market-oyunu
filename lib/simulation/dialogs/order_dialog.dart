import 'package:material_ui/material_ui.dart';
import '../simulation_engine.dart';
import '../simulation_models.dart';

class OrderComputerDialog extends StatefulWidget {
  final SimulationEngine engine;

  const OrderComputerDialog({super.key, required this.engine});

  @override
  State<OrderComputerDialog> createState() => _OrderComputerDialogState();
}

class _OrderComputerDialogState extends State<OrderComputerDialog> {
  late final Map<SimProductType, int> _cart;

  @override
  void initState() {
    super.initState();
    _cart = {
      for (var type in SimProductType.values) type: 0,
    };
  }

  double get _totalCost {
    double sum = 0;
    _cart.forEach((type, qty) {
      sum += productCatalog[type]!.boxCost * qty;
    });
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final canAfford = widget.engine.cash >= _totalCost && _totalCost > 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bilgisayar Başlığı
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('💻', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Çiftlik & Market Yönetim Bilgisayarı',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Yeni ürün kilitlerini açın veya kapıya toptan koli siparişi verin!',
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

            // Bilgi Notu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Text('🚜', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'İpucu: Marketin arkasındaki Ahır, Tarla ve Tavuk Çiftliğinden ücretsiz taze üretim kolilerini de toplayabilirsiniz!',
                      style: TextStyle(fontSize: 11, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            // Ürün Listesi
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.engine.shelves.map((shelf) {
                    final def = productCatalog[shelf.assignedProduct]!;
                    final qty = _cart[def.type] ?? 0;
                    final isUnlocked = shelf.isUnlocked;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isUnlocked ? Colors.grey.shade50 : Colors.amber.shade50.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isUnlocked ? Colors.grey.shade200 : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(def.emoji, style: const TextStyle(fontSize: 26)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      def.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isUnlocked ? Colors.green.shade100 : Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isUnlocked ? 'AÇIK' : 'KİLİTLİ REYON',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isUnlocked ? Colors.green.shade800 : Colors.orange.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  isUnlocked
                                      ? 'Koli: ${def.boxSize} adet • Koli Fiyatı: ₺${def.boxCost.toStringAsFixed(0)} • Satış: ₺${def.retailPrice.toStringAsFixed(0)}'
                                      : 'Bu ürünü satmaya başlamak için reyon kilidini açın (Satış: ₺${def.retailPrice.toStringAsFixed(0)})',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),

                          if (isUnlocked)
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: qty > 0
                                      ? () {
                                          setState(() {
                                            _cart[def.type] = qty - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text('$qty Koli', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                                  onPressed: () {
                                    setState(() {
                                      _cart[def.type] = qty + 1;
                                    });
                                  },
                                ),
                              ],
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: widget.engine.cash >= shelf.unlockCost
                                  ? () {
                                      setState(() {
                                        widget.engine.unlockShelf(shelf);
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.lock_open, size: 15),
                              label: Text('Aç (₺${shelf.unlockCost.toStringAsFixed(0)})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const Divider(height: 20),

            // Sipariş Özeti ve Buton
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mevcut Kasa: ₺${widget.engine.cash.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      'Toplam Sipariş: ₺${_totalCost.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: canAfford ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: canAfford
                      ? () {
                          widget.engine.orderProducts(_cart);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🚚 Kamyon siparişi aldı ve yola çıktı! Kapıya yanaşıyor...'),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('KAMYONU ÇAĞIR 🚛', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
