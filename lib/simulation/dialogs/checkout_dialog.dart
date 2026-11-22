import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../../widgets/pixel_ui.dart';
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
        decoration: pixelDeco(const Color(0xFF17120F), border: kInk, bw: 4, shadow: 6),
        clipBehavior: Clip.antiAlias,
        child: CashierFirstPersonView(
          engine: engine,
          customer: customer,
          onClose: () => Navigator.pop(context),
          onPaymentCollected: (earned) {
            Navigator.pop(context);
            showTopToast(context, '{bag} +\$${earned.toStringAsFixed(0)} collected!');
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
  final GlobalKey _sceneKey = GlobalKey();

  RenderBox? get _sceneBox => _sceneKey.currentContext?.findRenderObject() as RenderBox?;

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
    // Phones in landscape only give us ~300 px of height, so shrink every panel.
    final compact = MediaQuery.of(context).size.height < 520;

    return Container(
      color: const Color(0xFF17120F),
      child: Column(
        children: [
            // 1. ÜST KAMERA & KASİYER MODU ÇUBUĞU
            Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 18, vertical: compact ? 4 : 10),
              decoration: const BoxDecoration(
                color: Color(0xFF17120F),
                border: Border(bottom: BorderSide(color: Color(0xFF2A221C), width: 1.5)),
              ),
              child: Row(
                children: [
                                    Text(cust != null ? '{face}' : '{bell}', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              cust?.name ?? 'Register ${widget.counterIndex + 1}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                            if (cust != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cust.isVip ? Colors.amber.shade900 : const Color(0xFF2A221C),
                                  borderRadius: BorderRadius.zero,
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
                              ? 'Waiting for a customer'
                              : (isAllPacked ? 'Take payment' : 'Scan items  $packedCount/${cust.basket.length}'),
                          style: TextStyle(
                            color: cust == null
                                ? Colors.amberAccent
                                : (isAllPacked ? const Color(0xFF4ADE80) : const Color(0xFFB8A890)),
                            fontSize: compact ? 12 : 11.5,
                          ),
                          maxLines: compact ? 1 : null,
                          overflow: compact ? TextOverflow.ellipsis : null,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onClose,
                    icon: PixelIcon('back', size: 18),
                    label: Text('Back',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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

                  return SizedBox(
                    key: _sceneKey,
                    width: sceneSize.width,
                    height: sceneSize.height,
                    child: AnimatedBuilder(
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
                            child: _buildPosReceiptCard(cust, packedCount, isAllPacked, inLaserPhase, compact),
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
                                  SizedBox(
                                    height: compact ? 74 : 94,
                                    child: ListView.separated(
                scrollDirection: Axis.horizontal,
                                      physics: const NeverScrollableScrollPhysics(),
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
                                            final box = _sceneBox;
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
                                            width: compact ? 66 : 84,
                                            padding: EdgeInsets.all(compact ? 4 : 8),
                                            decoration: BoxDecoration(
                                              color: isNext ? const Color(0xFFFEF3C7) : const Color(0xFFE9DFC6),
                                              borderRadius: BorderRadius.zero,
                                              border: Border.all(
                                                color: isNext ? const Color(0xFFF59E0B) : const Color(0xFFB8A890),
                                                width: isNext ? 2.6 : 1.4,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isNext
                                                      ? Colors.amber.withValues(alpha: 0.45)
                                                      : Colors.black.withValues(alpha: 0.35),
                                                  blurRadius: 0,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Opacity(
                                              opacity: isDraggingThis ? 0.35 : 1.0,
                                              child: FittedBox(fit: BoxFit.scaleDown, child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(def.ico, style: TextStyle(fontSize: compact ? 22 : 30)),
                                                  const SizedBox(height: 3),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      def.short,
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                        color: Color(0xFF17120F),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '\$${def.retailPrice.toStringAsFixed(0)}',
                                                    style: TextStyle(
                                                      color: Colors.green.shade800,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ],
                                              )),
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
                              final box = _sceneBox;
                              if (box == null) return const SizedBox.shrink();
                              final local = box.globalToLocal(_dragOffset!);
                              final pType = cust.basket[_draggingIndex!];
                              final def = productCatalog[pType]!;
                              return Positioned(
                                left: local.dx - 38,
                                top: local.dy - 46,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.zero,
                                      border: Border.all(color: Colors.redAccent, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(3, 4), blurRadius: 0),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(def.ico, style: const TextStyle(fontSize: 28)),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(def.short,
                                              style: const TextStyle(
                                                  color: Color(0xFF17120F), fontSize: 13, fontWeight: FontWeight.w900)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                          // E) Tüm Ürünler Okutulduysa Alt Orta: Poşeti Teslim Et & Ödeme Al Butonu
                          if (cust != null && isAllPacked && !isScanning)
                            Positioned(
                              bottom: compact ? 8 : 20,
                              left: 24,
                              right: 24,
                              child: Center(
                                child: ElevatedButton.icon(
                                  onPressed: _handPackageAndCollect,
                                  icon: const Text('{card}', style: TextStyle(fontSize: 22)),
                                  label: Text(
                                    'TAKE PAYMENT +\$${_totalAmount.toStringAsFixed(0)}',
                                    style: TextStyle(fontSize: compact ? 14 : 15, fontWeight: FontWeight.w900),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28, vertical: compact ? 10 : 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
                                    elevation: 10,
                                  ),
                                ),
                              ),
                            ),

                          // F) Kasada henüz müşteri yoksa bekleme bilgisi
                          if (cust == null)
                            Positioned(
                              top: sceneSize.height * (compact ? 0.16 : 0.24),
                              left: 24,
                              right: compact ? 190 : 260,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF17120F).withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.zero,
                                    border: Border.all(color: const Color(0xFFE8B84A).withValues(alpha: 0.65), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(3, 4), blurRadius: 0),
                                    ],
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Waiting for a customer',
                                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildPosReceiptCard(SimCustomer? cust, int packedCount, bool isAllPacked, bool inLaserPhase, bool compact) {
    return Container(
      width: compact ? 168 : 225,
      padding: EdgeInsets.all(compact ? 7 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17120F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: inLaserPhase ? const Color(0xFF4ADE80) : const Color(0xFF4A3C30),
          width: inLaserPhase ? 2.0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(3, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECEIPT',
                style: TextStyle(color: Color(0xFFE8B84A), fontSize: 11, fontWeight: FontWeight.w900),
              ),
              Text(
                cust == null ? '0/0' : '$packedCount/${cust.basket.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Color(0xFF4A3C30), height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: compact ? 46 : 135),
            child: cust == null
                ? const SizedBox(height: 12)
                : packedCount == 0
                    ? const SizedBox(height: 12)
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
                                '${def.ico} ${def.name}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                            Text(
                              '\$${def.retailPrice.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(color: Color(0xFF4A3C30), height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL:', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
              Text(
                '\$${_scannedAmount.toStringAsFixed(0)} / \$${_totalAmount.toStringAsFixed(0)}',
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

/// First-person cashier view, drawn in the same chunky pixel style as the shop.
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

  static const double u = 4.0; // one "art pixel"
  static const Color _ol = Color(0xFF14100E);
  final Paint _p = Paint()..isAntiAlias = false;

  double _s(double v) => (v / u).round() * u;

  void _r(Canvas c, double x, double y, double w, double h, Color col) {
    _p.color = col;
    final x0 = _s(x), y0 = _s(y);
    final x1 = _s(x + w), y1 = _s(y + h);
    c.drawRect(Rect.fromLTRB(x0, y0, max(x1, x0 + u), max(y1, y0 + u)), _p);
  }

  /// Box with a dark pixel outline.
  void _box(Canvas c, Rect r, Color fill, {Color? hi, double o = u}) {
    _r(c, r.left - o, r.top - o, r.width + o * 2, r.height + o * 2, _ol);
    _r(c, r.left, r.top, r.width, r.height, fill);
    if (hi != null) _r(c, r.left, r.top, r.width, u, hi);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = _s(h * 0.44);

    // ---- BACK WALL -------------------------------------------------------
    _r(canvas, 0, 0, w, horizonY, const Color(0xFF243635));
    for (double y = 0; y < horizonY; y += u * 6) {
      _r(canvas, 0, y, w, u, const Color(0xFF1F302F)); // panel seams
    }
    // ceiling strip
    _r(canvas, 0, 0, w, u * 3, const Color(0xFF17120F));
    // ceiling lights (stepped glow)
    for (final tx in [w * 0.22, w * 0.50, w * 0.78]) {
      _r(canvas, tx - 60, u * 3, 120, u, const Color(0x22FFF2B0));
      _r(canvas, tx - 40, u * 3, 80, u * 2, const Color(0x33FFF2B0));
      _r(canvas, tx - 28, u * 3, 56, u * 2, _ol);
      _r(canvas, tx - 24, u * 3, 48, u, const Color(0xFFFFF2B0));
    }
    // wainscot band + floor strip
    _r(canvas, 0, horizonY - u * 9, w, u * 5, const Color(0xFF6F6858));
    _r(canvas, 0, horizonY - u * 9, w, u, const Color(0xFF9A9280));
    for (double x = 0; x < w; x += u * 8) {
      for (double y = horizonY - u * 4; y < horizonY + u * 2; y += u * 2) {
        final alt = (((x / (u * 8)).floor() + (y / (u * 2)).floor()) % 2 == 0);
        _r(canvas, x, y, u * 8, u * 2, alt ? const Color(0xFF3B3129) : const Color(0xFF30271F));
      }
    }

    // distant shelves
    for (final rx in [w * 0.14, w * 0.84]) {
      final sr = Rect.fromCenter(center: Offset(rx, horizonY - 30), width: 112, height: 88);
      _box(canvas, sr, const Color(0xFF3A2A1C));
      const cols = [Color(0xFFD9534F), Color(0xFFE8B84A), Color(0xFF5BB0D6), Color(0xFF6BBF6A)];
      for (int row = 0; row < 3; row++) {
        final ry = sr.top + 20 + row * 24;
        _r(canvas, sr.left + 4, ry, sr.width - 8, u, const Color(0xFF8A5A33));
        for (double px = sr.left + 12; px < sr.right - 12; px += 16) {
          _r(canvas, px, ry - 12, 10, 12, cols[(px.toInt() ~/ 4 + row) % 4]);
        }
      }
    }

    // ---- CUSTOMER ---------------------------------------------------------
    if (customer != null) {
      _drawCustomer(canvas, w * 0.46, horizonY + 12, customer!);
    }

    // ---- COUNTER ----------------------------------------------------------
    final ctop = horizonY + u * 2;
    _r(canvas, 0, ctop - u, w, h - ctop + u, _ol);
    _r(canvas, 0, ctop, w, h - ctop, const Color(0xFF5A3A22));
    _r(canvas, 0, ctop, w, u * 2, const Color(0xFFB07A45)); // lit top edge
    _r(canvas, 0, ctop + u * 2, w, u, const Color(0xFF8A5A33));
    for (double y = ctop + u * 10; y < h; y += u * 10) {
      _r(canvas, 0, y, w, u, const Color(0xFF4A2F1B)); // plank seams
    }
    _r(canvas, 0, ctop + u * 3, w, u, const Color(0xFF94A3B8)); // steel rail

    // ---- CONVEYOR BELT ----------------------------------------------------
    final bx0 = _s(w * 0.04), bx1 = _s(w * 0.44);
    final by0 = _s(horizonY + 28), by1 = _s(h * 0.88);
    _r(canvas, bx0 - u, by0 - u, bx1 - bx0 + u * 2, by1 - by0 + u * 2, _ol);
    _r(canvas, bx0, by0, bx1 - bx0, by1 - by0, const Color(0xFF1B1F27));
    _r(canvas, bx0, by0, bx1 - bx0, u, const Color(0xFF3B4250));
    _r(canvas, bx0, by1 - u, bx1 - bx0, u, const Color(0xFF3B4250));
    final scroll = ((ambientTime * 20) % 28 / u).floor() * u;
    for (double x = bx0 + scroll; x < bx1; x += 28) {
      _r(canvas, x, by0 + u * 2, u, by1 - by0 - u * 4, const Color(0xFF2E3440));
    }

    // ---- SCANNER ----------------------------------------------------------
    final scannerRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.67), width: 120, height: 120);
    final inLaser = isScanning && scanProgress <= 0.58;
    _box(canvas, scannerRect.inflate(u * 2), const Color(0xFF475569), hi: const Color(0xFF94A3B8));
    _r(canvas, scannerRect.left, scannerRect.top, scannerRect.width, scannerRect.height, const Color(0xFF05070D));
    final laser = inLaser ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    final lt = inLaser ? u * 1.5 : u;
    _r(canvas, scannerRect.left + 12, scannerRect.center.dy - lt / 2, scannerRect.width - 24, lt, laser);
    _r(canvas, scannerRect.center.dx - lt / 2, scannerRect.top + 12, lt, scannerRect.height - 24, laser);
    // diagonal as stepped blocks
    for (int i = 0; i < 6; i++) {
      final d = scannerRect.left + 22 + i * 14.0;
      _r(canvas, d, scannerRect.top + 22 + i * 14.0, u, u, laser);
    }
    if (inLaser) {
      _r(canvas, scannerRect.left + 8, scannerRect.top + 8, scannerRect.width - 16, scannerRect.height - 16, const Color(0x22EF4444));
      _text(canvas, 'BEEP!', scannerRect.center.dx, scannerRect.top - 22, fontSize: 16, color: const Color(0xFF4ADE80));
    } else {
      _text(canvas, 'LASER SCANNER', scannerRect.center.dx, scannerRect.bottom + 22, fontSize: 10, color: const Color(0xFF94A3B8));
    }

    // ---- BAG --------------------------------------------------------------
    final bagCenter = Offset(w * 0.78, h * 0.69);
    final bounce = isScanning && scanProgress > 0.58 ? sin(((scanProgress - 0.58) / 0.42) * pi) * 10.0 : 0.0;
    final bagRect = Rect.fromCenter(
      center: Offset(bagCenter.dx, bagCenter.dy - bounce * 0.4),
      width: 124 + packedCount * 3.0,
      height: 116 + bounce,
    );
    final ready = customer?.isFullyPacked ?? false;
    _r(canvas, bagRect.left + 8, bagRect.bottom + u, bagRect.width, u * 2, const Color(0x55000000)); // shadow
    final bagMain = ready ? const Color(0xFF3F9B5A) : const Color(0xFFC08A4A);
    final bagLight = ready ? const Color(0xFF63C07C) : const Color(0xFFDDA865);
    final bagDark = ready ? const Color(0xFF2B6E40) : const Color(0xFF8C5F2E);
    _box(canvas, bagRect, bagMain);
    _r(canvas, bagRect.left, bagRect.top, u * 3, bagRect.height, bagLight);
    _r(canvas, bagRect.right - u * 3, bagRect.top, u * 3, bagRect.height, bagDark);
    _r(canvas, bagRect.left, bagRect.bottom - u * 2, bagRect.width, u * 2, bagDark);
    _r(canvas, bagRect.left + u * 4, bagRect.top + u * 2, bagRect.width - u * 8, u * 6, const Color(0xFF17120F)); // mouth
    if (customer != null) {
      for (int i = 0; i < min(packedCount, 6); i++) {
        final def = productCatalog[customer!.basket[i]]!;
        PixelSprites.paint(canvas, def.type.name,
            Offset(bagRect.center.dx - 44 + (i % 3) * 30, bagRect.top + 14 + (i ~/ 3) * 26), 3);
      }
    }
    _text(
      canvas,
      customer == null
          ? 'STORE BAG'
          : (ready ? 'BAG READY!' : 'STORE BAG ($packedCount/${customer!.basket.length})'),
      bagCenter.dx,
      bagRect.bottom + 24,
      fontSize: 11,
      color: ready ? const Color(0xFF4ADE80) : Colors.white,
    );

    // ---- ITEM FLYING THROUGH ---------------------------------------------
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
      // cashier arm (stepped blocks from the bottom-right corner)
      final from = Offset(w * 0.58, h + 10);
      final to = cur + const Offset(10, 16);
      for (int i = 0; i <= 10; i++) {
        final pt = Offset.lerp(from, to, i / 10)!;
        _r(canvas, pt.dx - 12, pt.dy - 12, 24, 24, _ol);
      }
      for (int i = 0; i <= 10; i++) {
        final pt = Offset.lerp(from, to, i / 10)!;
        _r(canvas, pt.dx - 8, pt.dy - 8, 16, 16, const Color(0xFFC2410C));
      }
      _r(canvas, to.dx - 14, to.dy - 14, 28, 28, _ol);
      _r(canvas, to.dx - 10, to.dy - 10, 20, 20, const Color(0xFFE0B08A));
      // item card
      final card = Rect.fromCenter(center: cur, width: 64, height: 64);
      _box(canvas, card, Colors.white);
      _r(canvas, card.left, card.bottom - u * 2, card.width, u * 2, inLaser ? const Color(0xFFEF4444) : def.primaryColor);
      PixelSprites.paint(canvas, def.type.name, Offset(cur.dx - 16, cur.dy - 20), 4);
    }
  }

  void _drawCustomer(Canvas c, double cx, double cy, SimCustomer cu) {
    final bob = (sin(ambientTime * 1.5) * 1.5).round() * u / 2;
    Color shirt = const Color(0xFF0D9488);
    if (cu.isVip) shirt = const Color(0xFFCA8A04);
    if (cu.archetype == CustomerArchetype.chef) shirt = const Color(0xFFE8ECEF);
    if (cu.archetype == CustomerArchetype.grandma) shirt = const Color(0xFF9333EA);
    if (cu.archetype == CustomerArchetype.athlete) shirt = const Color(0xFFEF4444);
    if (cu.archetype == CustomerArchetype.student) shirt = const Color(0xFF2563EB);
    final dark = Color.lerp(shirt, Colors.black, 0.35)!;
    final hair = cu.archetype == CustomerArchetype.grandma ? const Color(0xFFD8DEE6) : const Color(0xFF3F2A1D);
    const skin = Color(0xFFE0B08A);
    const skinD = Color(0xFFB98562);

    // torso
    final t = Rect.fromLTWH(cx - 56, cy - 60 + bob, 112, 76);
    _r(c, t.left - u, t.top - u, t.width + u * 2, t.height + u, _ol);
    _r(c, t.left, t.top, t.width, t.height, shirt);
    _r(c, t.left, t.top, t.width, u * 2, Color.lerp(shirt, Colors.white, 0.25)!);
    _r(c, t.left, t.top + t.height - u * 4, t.width, u * 4, dark);
    _r(c, t.left + 4, t.top + u * 4, u * 2, u * 10, dark); // sleeve shading
    _r(c, t.right - 4 - u * 2, t.top + u * 4, u * 2, u * 10, dark);
    // neck
    _r(c, cx - 12, cy - 66 + bob, 24, 8, skinD);
    // head
    final head = Rect.fromLTWH(cx - 32, cy - 124 + bob, 64, 60);
    _r(c, head.left - u, head.top - u, head.width + u * 2, head.height + u * 2, _ol);
    _r(c, head.left, head.top, head.width, head.height, skin);
    _r(c, head.left, head.bottom - u * 2, head.width, u * 2, skinD);
    // hair
    _r(c, head.left, head.top - u, head.width, u * 5, hair);
    _r(c, head.left, head.top, u * 2, u * 8, hair);
    _r(c, head.right - u * 2, head.top, u * 2, u * 8, hair);
    // eyes + mouth
    _r(c, head.left + 14, head.top + 26, u * 2, u * 2, _ol);
    _r(c, head.right - 22, head.top + 26, u * 2, u * 2, _ol);
    if (cu.isFullyPacked) {
      _r(c, head.center.dx - 8, head.bottom - 18, 16, u, const Color(0xFF881337));
      _r(c, head.center.dx - 12, head.bottom - 22, u, u, const Color(0xFF881337));
      _r(c, head.center.dx + 8, head.bottom - 22, u, u, const Color(0xFF881337));
    } else {
      _r(c, head.center.dx - 6, head.bottom - 18, 12, u, const Color(0xFF881337));
    }

    // speech bubble
    final msg = cu.isFullyPacked
        ? 'Great, thanks! Here is your payment.'
        : 'Have a nice day! (${cu.basket.length - packedCount} items left)';
    final bubble = Rect.fromCenter(center: Offset(cx + 160, head.center.dy - 14), width: 244, height: 36);
    _box(c, bubble, Colors.white, o: 2);
    _r(c, bubble.left - 8, bubble.center.dy, 8, u, Colors.white); // tail towards the head
    _text(c, msg, bubble.center.dx, bubble.center.dy, fontSize: 11, color: const Color(0xFF17120F), outline: false);
  }

  static final Map<String, TextPainter> _fpTextCache = {};

  TextPainter _tp(String text, double fontSize, Color color) {
    final key = '$text|$fontSize|${color.toARGB32()}';
    var tp = _fpTextCache[key];
    if (tp == null) {
      if (_fpTextCache.length > 300) _fpTextCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold, fontFamily: 'Pixelify'),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      _fpTextCache[key] = tp;
    }
    return tp;
  }

  void _text(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, Color color = Colors.white, bool outline = true}) {
    final tp = _tp(text, fontSize, color);
    final off = Offset((x - tp.width / 2).roundToDouble(), (y - tp.height / 2).roundToDouble());
    if (outline) {
      final o = _tp(text, fontSize, _ol);
      for (final d in const [Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1)]) {
        o.paint(canvas, off + d);
      }
    }
    tp.paint(canvas, off);
  }

  @override
  bool shouldRepaint(covariant _CashierFirstPersonPainter oldDelegate) => true;
}
