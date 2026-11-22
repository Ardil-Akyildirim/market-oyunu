import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/game_provider.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  ProductCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final products = _selectedCategory == null
        ? game.products
        : game.products.where((p) => p.category == _selectedCategory).toList();

    return Column(
      children: [
        // Kategori Filtre Butonları
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildCategoryChip('Tümü 🛒', null),
              _buildCategoryChip('Tarla & Bahçe 🌾', ProductCategory.farm),
              _buildCategoryChip('Süt & Mandıra 🥛', ProductCategory.dairy),
              _buildCategoryChip('Fırın & Ekmek 🥖', ProductCategory.bakery),
              _buildCategoryChip('Bakkaliye 🥫', ProductCategory.grocery),
              _buildCategoryChip('Kasap & Şarküteri 🥩', ProductCategory.butcher),
              _buildCategoryChip('Gurme & İthal ✨', ProductCategory.gourmet),
            ],
          ),
        ),

        // Ürün Listesi
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _buildProductCard(context, game, product);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String label, ProductCategory? category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
        selected: isSelected,
        selectedColor: Colors.orange.shade600,
        backgroundColor: Colors.white,
        side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        showCheckmark: false,
        onSelected: (val) {
          setState(() {
            _selectedCategory = category;
          });
        },
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, GameProvider game, Product product) {
    if (!product.isUnlocked) {
      // Kilitli Ürün Kartı
      final canUnlock = game.cash >= product.unlockCost && game.marketLevel >= product.unlockLevel;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('🔒', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    game.marketLevel < product.unlockLevel
                        ? 'Gereken: Seviye ${product.unlockLevel} Market'
                        : 'Açılış Maliyeti: ₺${product.unlockCost.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: game.marketLevel < product.unlockLevel ? Colors.red.shade600 : Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: canUnlock ? () => game.unlockProduct(product) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Kilidi Aç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // Açık Ürün Kartı
    final fillRatio = (product.stock / product.maxStock).clamp(0.0, 1.0);
    final isLow = product.stock <= (product.maxStock * 0.25);
    final restockCost = (product.maxStock - product.stock) * product.buyPrice;
    final canRestock = game.cash >= restockCost && product.stock < product.maxStock;
    final canUpgrade = game.cash >= product.upgradeCost;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
          color: isLow ? Colors.red.shade300 : Colors.grey.shade200,
          width: isLow ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Ürün Emojisi & Seviyesi
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(product.emoji, style: const TextStyle(fontSize: 28)),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Lv.${product.level}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Ürün İsmi & Fiyatlar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Satış: ₺${product.sellPrice.toStringAsFixed(1)} • Kâr: +₺${product.profit.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Alış Maliyeti: ₺${product.buyPrice.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // Kalite Geliştir Butonu
              OutlinedButton(
                onPressed: canUpgrade ? () => game.upgradeProduct(product) : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: canUpgrade ? Colors.orange.shade600 : Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Yükselt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(
                      '₺${product.upgradeCost.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: canUpgrade ? Colors.orange.shade800 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Stok Çubuğu ve Doldurma Butonu
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Reyon Stoğu: ${product.stock} / ${product.maxStock}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isLow ? Colors.red.shade700 : Colors.grey.shade700,
                          ),
                        ),
                        if (isLow)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'AZALDI!',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: fillRatio,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          fillRatio < 0.2
                              ? Colors.red
                              : fillRatio < 0.5
                                  ? Colors.orange
                                  : Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Reyona Raf Doldur Butonu
              ElevatedButton.icon(
                onPressed: canRestock
                    ? () {
                        int amount = (product.maxStock - product.stock);
                        game.restockProduct(product, amount: amount);
                      }
                    : null,
                icon: const Icon(Icons.add_shopping_cart, size: 14),
                label: Text(
                  product.stock >= product.maxStock
                      ? 'Dolu'
                      : 'Doldur (₺${restockCost.toStringAsFixed(0)})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
