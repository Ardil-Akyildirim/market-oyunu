import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../../widgets/pixel_ui.dart';
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
      sum += widget.engine.boxPrice(productCatalog[type]!) * qty;
    });
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final canAfford = widget.engine.cash >= _totalCost && _totalCost > 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: Container(
        width: min(580.0, MediaQuery.of(context).size.width - 24),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - 16),
        decoration: pixelDeco(kParchment, bw: 4, shadow: 6),
        padding: EdgeInsets.all(MediaQuery.of(context).size.height < 500 ? 12 : 20),
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
                    borderRadius: BorderRadius.zero,
                  ),
                  child: const Text('{computer}', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Management Computer',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Order wholesale boxes: they are delivered to the front door.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: PixelIcon('x', size: 24, dark: true),
                ),
              ],
            ),

            const Divider(height: 20),

            // Bilgi Notu (hidden on short screens so the list + confirm button stay visible)
            if (MediaQuery.of(context).size.height >= 500) Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Text('{box}', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: new products open as the days pass. Pick up delivered boxes at the door and tap a shelf to restock it.',
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
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: isUnlocked ? Colors.grey.shade200 : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(def.ico, style: const TextStyle(fontSize: 26)),
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
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: Text(
                                        isUnlocked ? 'OPEN' : 'LOCKED SHELF',
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
                                      ? 'Box: ${def.boxSize} pcs • Box Price: \$${widget.engine.boxPrice(def).toStringAsFixed(0)} • Sale: \$${def.retailPrice.toStringAsFixed(0)}'
                                      : '${widget.engine.shelfLockReason(shelf)} (Sale: \$${def.retailPrice.toStringAsFixed(0)})',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),

                          if (isUnlocked)
                            Row(
                              children: [
                                IconButton(
                                  icon: PixelIcon('minus', size: 20, dark: true),
                                  onPressed: qty > 0
                                      ? () {
                                          widget.engine.playSfx('click');
                                          setState(() {
                                            _cart[def.type] = qty - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text('$qty Box', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                IconButton(
                                  icon: PixelIcon('plus', size: 20, dark: true),
                                  onPressed: () {
                                    widget.engine.playSfx('click');
                                    setState(() {
                                      _cart[def.type] = qty + 1;
                                    });
                                  },
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                '{lock} ${widget.engine.shelfLockReason(shelf)}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
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
                    Text('Current Cash: \$${widget.engine.cash.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      'Total Order: \$${_totalCost.toStringAsFixed(0)}',
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
                          showTopToast(context, '{truck} Order placed! The truck is on its way.', color: const Color(0xFF7CC4FF));
                        }
                      : null,
                  icon: PixelIcon('truck', size: 18),
                  label: const Text('CALL THE TRUCK {truck}', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
                  ),
                ),
              ],
            ),
          ],
        ),
      )),
    );
  }
}
