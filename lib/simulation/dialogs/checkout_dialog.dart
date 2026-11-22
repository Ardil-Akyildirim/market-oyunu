import 'dart:math';
import 'package:material_ui/material_ui.dart';
import '../simulation_engine.dart';
import '../simulation_models.dart';

class CheckoutRegisterDialog extends StatelessWidget {
  final SimulationEngine engine;
  final SimCustomer customer;

  const CheckoutRegisterDialog({
    super.key,
    required this.engine,
    required this.customer,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogW = min(980.0, size.width * 0.94);
    final dialogH = min(650.0, size.height * 0.90);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogW,
        height: dialogH,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.45), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: CashierFirstPersonView(
          engine: engine,
          customer: customer,
          onClose: () => Navigator.pop(context),
          onPaymentCollected: (earned) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🛍️ Paket teslim edildi ve +₺${earned.toStringAsFixed(0)} tahsil edildi! 😊'),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}

class CashierFirstPersonView extends StatefulWidget {
  final SimulationEngine engine;
  final SimCustomer? customer;
  final int counterIndex;
  final VoidCallback onClose;
  final void Function(double earned) onPaymentCollected;

  const CashierFirstPersonView({
    super.key,
    required this.engine,
    this.customer,
    this.counterIndex = 0,
    required this.onClose,
    required this.onPaymentCollected,
  });

  @override
  State<CashierFirstPersonView> createState() => _CashierFirstPersonViewState();
}

class _CashierFirstPersonViewState extends State<CashierFirstPersonView>
    with TickerProviderStateMixin {
  late final AnimationController _bagDropController;
  late final AnimationController _ambientController;
  SimProductType? _droppingItem;

  // Sürükle-Bırak ile barkoddan geçirme desteği
  Offset? _dragOffset;
  int? _draggingIndex;
  bool _laserTriggeredDuringDrag = false;

  @override
  void initState() {
    super.initState();
    _bagDropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _bagDropController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final cust = widget.customer;
    if (cust == null) return 0.0;
    double total = 0.0;
    for (final pType in cust.basket) {
      total += productCatalog[pType]!.retailPrice;
    }
    if (cust.bonusMultiplier > 1.0) {
      total = (total * cust.bonusMultiplier).roundToDouble();
    }
    return total;
  }

  double get _scannedAmount {
    final cust = widget.customer;
    if (cust == null) return 0.0;
    double total = 0.0;
    final count = cust.packedCount.clamp(0, cust.basket.length);
    for (int i = 0; i < count; i++) {
      total += productCatalog[cust.basket[i]]!.retailPrice;
    }
    if (cust.bonusMultiplier > 1.0 && count == cust.basket.length) {
      total = (total * cust.bonusMultiplier).roundToDouble();
    }
    return total;
  }

  void _scanNextItem() {
    final cust = widget.customer;
    if (cust == null || cust.isFullyPacked || _bagDropController.isAnimating) return;
    final idx = cust.packedCount.clamp(0, cust.basket.length - 1);
    final itemToPack = cust.basket[idx];
    setState(() {
      _droppingItem = itemToPack;
      widget.engine.packNextItemOrCheckout(cust);
    });
    _bagDropController.forward(from: 0.0);
  }

  void _handPackageAndCollect() {
    final cust = widget.customer;
    if (cust == null) return;
    final earned = widget.engine.checkoutCurrentCustomer(cust);
    widget.onPaymentCollected(earned);
  }

  @override
  Widget build(BuildContext context) {
    final cust = widget.customer;
    final packedCount = cust == null ? 0 : cust.packedCount.clamp(0, cust.basket.length);
    final isAllPacked = cust != null && cust.isFullyPacked;

    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
            // 1. ÜST KAMERA & KASİYER MODU ÇUBUĞU
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF090D16),
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF38BDF8)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🎥', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 6),
                        Text(
                          '1. ŞAHIS KASİYER KAMERASI',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(cust?.avatar ?? '🛎️', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              cust?.name ?? 'Kasa ${widget.counterIndex + 1} • Müşteri Bekleniyor',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                            if (cust != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cust.isVip ? Colors.amber.shade900 : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: cust.isVip ? Colors.amber : Colors.white24),
                                ),
                                child: Text(
                                  cust.archetypeBadge,
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          cust == null
                              ? '⏳ Müşteriler alışverişini bitirip kasaya gelince burada görünecek...'
                              : (isAllPacked
                                  ? '✅ Tüm ürünler okutuldu! Poşeti müşteriye teslim edip ödemeyi alın.'
                                  : '🖱️ Banttaki ürüne TIKLAYIN veya LAZER TARAYICIYA SÜRÜKLEYİP okutun ($packedCount/${cust.basket.length})'),
                          style: TextStyle(
                            color: cust == null
                                ? Colors.amberAccent
                                : (isAllPacked ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8)),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
                    label: const Text('Markete Dön [ESC / Tab]', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // 2. ANA 1. ŞAHIS 3D KASA TEZGAHI & MÜŞTERİ SAHNESİ
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sceneSize = Size(constraints.maxWidth, constraints.maxHeight);
                  final laserCenter = Offset(sceneSize.width * 0.50, sceneSize.height * 0.67);

                  return AnimatedBuilder(
                    animation: Listenable.merge([_bagDropController, _ambientController]),
                    builder: (context, _) {
                      final scanT = _bagDropController.value;
                      final isScanning = _bagDropController.isAnimating && _droppingItem != null;
                      final inLaserPhase = isScanning && scanT <= 0.58;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // A) 3D Perspektifli Market İçi, Müşteri, Kasa Tezgahı, Bant, Lazer & Poşet Çizimi
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CashierFirstPersonPainter(
                                customer: cust,
                                packedCount: packedCount,
                                totalScannedAmount: _scannedAmount,
                                totalAmount: _totalAmount,
                                droppingItem: _droppingItem,
                                scanProgress: scanT,
                                isScanning: isScanning,
                                ambientTime: _ambientController.value * 2 * pi,
                              ),
                            ),
                          ),

                          // B) Sağ Üstte Canlı POS Fiş Ekranı Overlay
                          Positioned(
                            top: 14,
                            right: 14,
                            child: _buildPosReceiptCard(cust, packedCount, isAllPacked, inLaserPhase),
                          ),

                          // C) Sol Altta Banttaki Okutulacak Ürünler (Tıkla veya Lazerin Üstüne Sürükle!)
                          if (cust != null && !isAllPacked)
                            Positioned(
                              left: 18,
                              bottom: 16,
                              right: sceneSize.width * 0.38,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
                                    ),
                                    child: const Text(
                                      '🔴 Banttaki Ürünler (Okutmak için Tıkla veya Lazer Camına Sürükle)',
                                      style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 92,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: cust.basket.length - packedCount,
                                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                                      itemBuilder: (context, offset) {
                                        final actualIndex = packedCount + offset;
                                        final pType = cust.basket[actualIndex];
                                        final def = productCatalog[pType]!;
                                        final isNext = offset == 0;
                                        final isDraggingThis = _draggingIndex == actualIndex;

                                        return GestureDetector(
                                          onTap: _scanNextItem,
                                          onPanStart: (details) {
                                            setState(() {
                                              _draggingIndex = actualIndex;
                                              _dragOffset = details.globalPosition;
                                              _laserTriggeredDuringDrag = false;
                                            });
                                          },
                                          onPanUpdate: (details) {
                                            setState(() {
                                              _dragOffset = details.globalPosition;
                                            });
                                            final box = context.findRenderObject() as RenderBox?;
                                            if (box != null && !_laserTriggeredDuringDrag) {
                                              final local = box.globalToLocal(details.globalPosition);
                                              if ((local - laserCenter).distance < 95) {
                                                _laserTriggeredDuringDrag = true;
                                                _scanNextItem();
                                              }
                                            }
                                          },
                                          onPanEnd: (_) {
                                            setState(() {
                                              _draggingIndex = null;
                                              _dragOffset = null;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 160),
                                            width: 84,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: isNext
                                                    ? [const Color(0xFFFFFFFF), const Color(0xFFFEF3C7)]
                                                    : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isNext ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                                                width: isNext ? 2.6 : 1.4,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isNext
                                                      ? Colors.amber.withValues(alpha: 0.45)
                                                      : Colors.black.withValues(alpha: 0.35),
                                                  blurRadius: isNext ? 12 : 6,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Opacity(
                                              opacity: isDraggingThis ? 0.35 : 1.0,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(def.emoji, style: const TextStyle(fontSize: 30)),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    def.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF0F172A),
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                  Text(
                                                    '₺${def.retailPrice.toStringAsFixed(0)}',
                                                    style: TextStyle(
                                                      color: Colors.green.shade800,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // D) Sürüklenen Ürünün Parmağı/Mouse'u Takip Etmesi
                          if (cust != null && _draggingIndex != null && _dragOffset != null && _draggingIndex! < cust.basket.length)
                            Builder(builder: (context) {
                              final box = context.findRenderObject() as RenderBox?;
                              if (box == null) return const SizedBox.shrink();
                              final local = box.globalToLocal(_dragOffset!);
                              final pType = cust.basket[_draggingIndex!];
                              final def = productCatalog[pType]!;
                              return Positioned(
                                left: local.dx - 34,
                                top: local.dy - 34,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.redAccent, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12),
                                      ],
                                    ),
                                    child: Center(child: Text(def.emoji, style: const TextStyle(fontSize: 34))),
                                  ),
                                ),
                              );
                            }),

                          // E) Tüm Ürünler Okutulduysa Alt Orta: Poşeti Teslim Et & Ödeme Al Butonu
                          if (cust != null && isAllPacked && !isScanning)
                            Positioned(
                              bottom: 20,
                              left: 24,
                              right: 24,
                              child: Center(
                                child: ElevatedButton.icon(
                                  onPressed: _handPackageAndCollect,
                                  icon: const Text('💳', style: TextStyle(fontSize: 22)),
                                  label: Text(
                                    'POŞETİ TESLİM ET & ÖDEMEYİ AL (+₺${_totalAmount.toStringAsFixed(0)})',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 10,
                                  ),
                                ),
                              ),
                            ),

                          // F) Kasada henüz müşteri yoksa bekleme bilgisi
                          if (cust == null)
                            Positioned(
                              top: sceneSize.height * 0.24,
                              left: 24,
                              right: 260,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.65), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14),
                                    ],
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '⏳ Kasada Müşteri Bekleniyor...',
                                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Market arka planda çalışmaya devam ediyor. Müşteri kasaya geldiğinde otomatik burada belirecek!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildPosReceiptCard(SimCustomer? cust, int packedCount, bool isAllPacked, bool inLaserPhase) {
    return Container(
      width: 225,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inLaserPhase ? const Color(0xFF4ADE80) : const Color(0xFF334155),
          width: inLaserPhase ? 2.0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🖥️ KASA POS FİŞİ',
                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w900),
              ),
              Text(
                cust == null ? '0/0' : '$packedCount/${cust.basket.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 135),
            child: cust == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Müşteri bekleniyor...',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  )
                : packedCount == 0
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Henüz ürün okutulmadı...',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: packedCount,
                        itemBuilder: (context, i) {
                          final def = productCatalog[cust.basket[i]]!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                '${def.emoji} ${def.name}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                            Text(
                              '₺${def.retailPrice.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(color: Color(0xFF334155), height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOPLAM:', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
              Text(
                '₺${_scannedAmount.toStringAsFixed(0)} / ₺${_totalAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  color: isAllPacked ? const Color(0xFF4ADE80) : Colors.amberAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1. Şahıs Kasiyer Kamerası (Kasanın önünü, karşıdaki müşteriyi, 3D perspektif bandı, lazer tarayıcıyı ve poşeti çizer)
class _CashierFirstPersonPainter extends CustomPainter {
  final SimCustomer? customer;
  final int packedCount;
  final double totalScannedAmount;
  final double totalAmount;
  final SimProductType? droppingItem;
  final double scanProgress;
  final bool isScanning;
  final double ambientTime;

  _CashierFirstPersonPainter({
    required this.customer,
    required this.packedCount,
    required this.totalScannedAmount,
    required this.totalAmount,
    required this.droppingItem,
    required this.scanProgress,
    required this.isScanning,
    required this.ambientTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = h * 0.44;

    // 1. ARKA PLAN: MARKET İÇİ PERSPEKTİFİ (Tavan, Duvarlar, Uzaktaki Raflar ve Giriş Camı)
    final ceilingRect = Rect.fromLTWH(0, 0, w, horizonY);
    canvas.drawRect(
      ceilingRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF475569)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(ceilingRect),
    );

    // Tavan Perspektif LED Panelleri
    for (final tx in [w * 0.22, w * 0.50, w * 0.78]) {
      final led = Path()
        ..moveTo(tx - 26, 8)
        ..lineTo(tx + 26, 8)
        ..lineTo(tx + 14, horizonY * 0.45)
        ..lineTo(tx - 14, horizonY * 0.45)
        ..close();
      canvas.drawPath(led, Paint()..color = const Color(0xFFFEF9C3).withValues(alpha: 0.75));
    }

    // Uzaktaki 3D Market Reyonları Silüeti (Derinlik hissi)
    for (final rx in [w * 0.14, w * 0.84]) {
      final shelfRect = Rect.fromCenter(center: Offset(rx, horizonY - 26), width: 110, height: 82);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shelfRect, const Radius.circular(6)),
        Paint()..color = const Color(0xFF1E293B),
      );
      for (int row = 0; row < 3; row++) {
        final ry = shelfRect.top + 18 + row * 22;
        canvas.drawLine(Offset(shelfRect.left + 8, ry), Offset(shelfRect.right - 8, ry), Paint()..color = const Color(0xFF64748B)..strokeWidth = 3);
        for (double px = shelfRect.left + 16; px < shelfRect.right - 14; px += 18) {
          canvas.drawCircle(Offset(px, ry - 6), 5, Paint()..color = [Colors.redAccent, Colors.amber, Colors.lightBlueAccent, Colors.greenAccent][(px.toInt() + row) % 4]);
        }
      }
    }

    // 2. KARŞIDA DURAN 3D MÜŞTERİ (Kasanın Önünde Bekleyen Müşteri)
    if (customer != null) {
      _drawCustomerFacingCashier(canvas, w * 0.46, horizonY + 12, customer!);
    }

    // 3. ÖNÜMÜZDEKİ 3D PERSPEKTİF KASA TEZGAHI
    final counterPath = Path()
      ..moveTo(0, horizonY + 8)
      ..lineTo(w, horizonY + 8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      counterPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF334155), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, horizonY, w, h - horizonY)),
    );
    // Tezgah Ön Parlak Krom Kenar Şeridi
    canvas.drawLine(
      Offset(0, horizonY + 8),
      Offset(w, horizonY + 8),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 4.0,
    );

    // 4. 3D PERSPEKTİFLİ HAREKETLİ KONVEYÖR BANT (Soldan merkeze doğru uzanır)
    final beltPath = Path()
      ..moveTo(w * 0.04, horizonY + 26)
      ..lineTo(w * 0.44, horizonY + 26)
      ..lineTo(w * 0.44, h * 0.88)
      ..lineTo(w * 0.02, h * 0.88)
      ..close();
    canvas.drawPath(
      beltPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF090D16), Color(0xFF111827), Color(0xFF1F2937)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, horizonY + 26, w * 0.45, h * 0.5)),
    );
    // Hareketli Bant Çizgileri
    final beltScroll = (ambientTime * 18) % 28;
    for (double bx = w * 0.05 + beltScroll; bx < w * 0.42; bx += 28) {
      canvas.drawLine(
        Offset(bx, horizonY + 30),
        Offset(bx - 10, h * 0.86),
        Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 2.0,
      );
    }

    // 5. ORTADA KIRMIZI LAZER BARKOD OKUYUCU CAM TABLA
    final scannerRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.67), width: 118, height: 118);
    final inLaserPhase = isScanning && scanProgress <= 0.58;
    canvas.drawRRect(
      RRect.fromRectAndRadius(scannerRect.inflate(6), const Radius.circular(14)),
      Paint()..color = const Color(0xFF475569),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scannerRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFF020617),
    );
    // Kırmızı Optik Lazer Çizgileri
    final laserColor = inLaserPhase ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final laserPaint = Paint()
      ..color = laserColor
      ..strokeWidth = inLaserPhase ? 4.2 : 2.2;
    canvas.drawLine(Offset(scannerRect.left + 12, scannerRect.center.dy), Offset(scannerRect.right - 12, scannerRect.center.dy), laserPaint);
    canvas.drawLine(Offset(scannerRect.center.dx, scannerRect.top + 12), Offset(scannerRect.center.dx, scannerRect.bottom - 12), laserPaint);
    canvas.drawLine(Offset(scannerRect.left + 18, scannerRect.top + 18), Offset(scannerRect.right - 18, scannerRect.bottom - 18), laserPaint..strokeWidth = 1.4);

    if (inLaserPhase) {
      canvas.drawCircle(
        scannerRect.center,
        46,
        Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.28),
      );
      _drawText(canvas, '🔊 BİİP!', scannerRect.center.dx, scannerRect.top - 18, fontSize: 15, color: const Color(0xFF4ADE80), bold: true);
    } else {
      _drawText(canvas, 'LAZER OKUYUCU', scannerRect.center.dx, scannerRect.bottom + 16, fontSize: 10, color: const Color(0xFF94A3B8), bold: true);
    }

    // 6. SAĞ TARAFTA AÇIK DURAN 3D MARKET POŞETİ
    final bagCenter = Offset(w * 0.78, h * 0.69);
    final bagBounce = isScanning && scanProgress > 0.58 ? sin(((scanProgress - 0.58) / 0.42) * pi) * 10.0 : 0.0;
    final bagRect = Rect.fromCenter(
      center: Offset(bagCenter.dx, bagCenter.dy - bagBounce * 0.4),
      width: 125 + packedCount * 3.0,
      height: 118 + bagBounce,
    );
    // Poşet gölgesi
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bagCenter.dx + 6, bagRect.bottom + 4), width: bagRect.width, height: 22),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    // Poşet gövdesi
    final isFullyPacked = customer?.isFullyPacked ?? false;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bagRect, const Radius.circular(14)),
      Paint()
        ..shader = LinearGradient(
          colors: isFullyPacked
              ? const [Color(0xFF22C55E), Color(0xFF15803D)]
              : const [Color(0xFFF59E0B), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bagRect),
    );
    // Poşet ağzı (iç derinlik)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bagRect.center.dx, bagRect.top + 14), width: bagRect.width - 20, height: 22),
      Paint()..color = const Color(0xFF0F172A),
    );
    // Poşetin içindeki ürünler
    if (customer != null) {
      for (int i = 0; i < min(packedCount, 6); i++) {
        final def = productCatalog[customer!.basket[i]]!;
        _drawText(canvas, def.emoji, bagRect.center.dx - 32 + (i % 3) * 32, bagRect.top + 16 + (i ~/ 3) * 14, fontSize: 20);
      }
    }
    _drawText(
      canvas,
      customer == null
          ? '🛍️ MARKET POŞETİ'
          : (isFullyPacked ? '✅ POŞET HAZIR' : '🛍️ MARKET POŞETİ ($packedCount/${customer!.basket.length})'),
      bagCenter.dx,
      bagRect.bottom + 18,
      fontSize: 11,
      color: isFullyPacked ? const Color(0xFF4ADE80) : Colors.white,
      bold: true,
    );

    // 7. OKUTULAN ÜRÜNÜN KASİYER ELİYLE LAZERDEN GEÇİP POŞETE UÇMASI ANİMASYONU
    if (isScanning && droppingItem != null) {
      final def = productCatalog[droppingItem!]!;
      final start = Offset(w * 0.25, h * 0.65);
      final mid = scannerRect.center;
      final end = Offset(bagCenter.dx, bagRect.top + 10);

      late final Offset cur;
      if (scanProgress <= 0.58) {
        final t = scanProgress / 0.58;
        cur = Offset.lerp(start, mid, t)! - Offset(0, sin(t * pi) * 28);
      } else {
        final t = (scanProgress - 0.58) / 0.42;
        cur = Offset.lerp(mid, end, t)! - Offset(0, sin(t * pi) * 48);
      }

      // Kasiyerin sağ alt köşeden uzanan 3D kolu/eli
      canvas.drawLine(
        Offset(w * 0.58, h + 10),
        cur + const Offset(10, 14),
        Paint()
          ..color = const Color(0xFFC2410C)
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(cur + const Offset(8, 12), 13, Paint()..color = const Color(0xFFFBCFE8));

      // Ürün kartı
      final itemRect = Rect.fromCenter(center: cur, width: 64, height: 64);
      canvas.drawRRect(
        RRect.fromRectAndRadius(itemRect, const Radius.circular(14)),
        Paint()..color = Colors.white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(itemRect, const Radius.circular(14)),
        Paint()
          ..color = inLaserPhase ? Colors.redAccent : def.primaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
      _drawText(canvas, def.emoji, cur.dx, cur.dy - 2, fontSize: 32);
    }
  }

  void _drawCustomerFacingCashier(Canvas canvas, double cx, double cy, SimCustomer customer) {
    final breathe = sin(ambientTime * 1.5) * 2.5;
    Color shirt = const Color(0xFF0D9488);
    if (customer.isVip) shirt = const Color(0xFFCA8A04);
    if (customer.archetype == CustomerArchetype.chef) shirt = const Color(0xFFF8FAFC);
    if (customer.archetype == CustomerArchetype.grandma) shirt = const Color(0xFF9333EA);
    if (customer.archetype == CustomerArchetype.athlete) shirt = const Color(0xFFEF4444);
    if (customer.archetype == CustomerArchetype.student) shirt = const Color(0xFF2563EB);

    final torsoRect = Rect.fromCenter(center: Offset(cx, cy - 22 + breathe * 0.4), width: 112, height: 76);
    canvas.drawRRect(
      RRect.fromRectAndCorners(torsoRect, topLeft: const Radius.circular(36), topRight: const Radius.circular(36)),
      Paint()
        ..shader = LinearGradient(
          colors: [shirt, Color.lerp(shirt, Colors.black, 0.35)!],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(torsoRect),
    );

    final headCenter = Offset(cx, cy - 86 + breathe);
    canvas.drawCircle(headCenter, 34, Paint()..color = const Color(0xFFFBCFE8));
    canvas.drawArc(
      Rect.fromCircle(center: headCenter, radius: 36),
      pi,
      pi,
      true,
      Paint()..color = customer.archetype == CustomerArchetype.grandma ? const Color(0xFFE2E8F0) : const Color(0xFF3F2A1D),
    );
    canvas.drawCircle(Offset(headCenter.dx - 11, headCenter.dy - 2), 4.0, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(Offset(headCenter.dx + 11, headCenter.dy - 2), 4.0, Paint()..color = const Color(0xFF0F172A));
    canvas.drawArc(
      Rect.fromCenter(center: Offset(headCenter.dx, headCenter.dy + 10), width: 18, height: 10),
      0.1,
      pi - 0.2,
      false,
      Paint()
        ..color = const Color(0xFF881337)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );

    final msg = customer.isFullyPacked
        ? '🛍️ Harika, teşekkürler! İşte ödemeniz.'
        : '🙂 Kolay gelsin! (${customer.basket.length - packedCount} ürün kaldı)';
    final bubble = Rect.fromCenter(center: Offset(cx + 150, headCenter.dy - 12), width: 220, height: 34);
    canvas.drawRRect(RRect.fromRectAndRadius(bubble, const Radius.circular(14)), Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubble, const Radius.circular(14)),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawText(canvas, msg, bubble.center.dx, bubble.center.dy, fontSize: 11, color: const Color(0xFF0F172A), bold: true);
  }

  static final Map<String, TextPainter> _fpTextCache = {};

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, Color color = Colors.white, bool bold = false}) {
    final key = '$text|$fontSize|${color.toARGB32()}|$bold';
    var tp = _fpTextCache[key];
    if (tp == null) {
      if (_fpTextCache.length > 250) _fpTextCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      _fpTextCache[key] = tp;
    }
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CashierFirstPersonPainter oldDelegate) => true;
}
