import 'dart:math';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'simulation_engine.dart';
import 'simulation_models.dart';

/// World units per art pixel. Everything is drawn on this grid with
/// anti-aliasing off, so the whole game looks like chunky pixel art.
const double kPx = 3.0;

class Pal {
  // Moody, slightly desaturated palette (dark teal walls, warm wood, red rug)
  static const outline = Color(0xFF14100E);
  static const shadow = Color(0x55000000);

  static const wallDark = Color(0xFF1B2828);
  static const wallMid = Color(0xFF243635);
  static const wallLight = Color(0xFF2F4745);
  static const wainscot = Color(0xFF9A9280);
  static const wainscotDark = Color(0xFF6F6858);
  static const trim = Color(0xFF4A3524);

  static const floorA = Color(0xFF3B3129);
  static const floorB = Color(0xFF352C25);
  static const floorC = Color(0xFF30271F);
  static const grout = Color(0xFF231C17);

  static const rugBase = Color(0xFF5A2222);
  static const rugMid = Color(0xFF7A2F2D);
  static const rugGold = Color(0xFFB08A3E);

  static const woodDark = Color(0xFF5A3A22);
  static const wood = Color(0xFF8A5A33);
  static const woodLight = Color(0xFFB07A45);

  static const asphalt = Color(0xFF24272D);
  static const asphaltLine = Color(0xFF50545C);
  static const pave1 = Color(0xFF4B4943);
  static const pave2 = Color(0xFF423F3A);

  static const skin = Color(0xFFE0B08A);
  static const skinDark = Color(0xFFB98562);
}

class PixelPainter extends CustomPainter {
  final SimulationEngine engine;
  PixelPainter({required this.engine}) : super(repaint: engine);

  static ui.Picture? _staticPicture;
  static final Map<String, TextPainter> _textCache = {};
  final Paint _p = Paint()..isAntiAlias = false;

  // ---------------------------------------------------------------------------
  // low level helpers
  // ---------------------------------------------------------------------------
  double _snap(double v) => (v / kPx).round() * kPx;

  void _r(Canvas c, double wx, double wy, num gx, num gy, num gw, num gh, Color col) {
    _p.color = col;
    c.drawRect(Rect.fromLTWH(wx + gx * kPx, wy + gy * kPx, gw * kPx, gh * kPx), _p);
  }

  /// rectangle in world units (snapped to the pixel grid)
  void _wr(Canvas c, Rect r, Color col) {
    _p.color = col;
    final l = _snap(r.left), t = _snap(r.top);
    final rr = _snap(r.right), b = _snap(r.bottom);
    c.drawRect(Rect.fromLTRB(l, t, max(rr, l + kPx), max(b, t + kPx)), _p);
  }

  int _hash(int a, int b) {
    int h = (a * 73856093) ^ (b * 19349663);
    h = (h ^ (h >> 13)) & 0x7fffffff;
    return h;
  }

  TextPainter _tp(String text, double size, Color color, bool bold) {
    final key = '$text|$size|${color.toARGB32()}|$bold';
    final cached = _textCache[key];
    if (cached != null) return cached;
    if (_textCache.length > 400) _textCache.clear();
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'Pixelify',
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _textCache[key] = tp;
    return tp;
  }

  /// Pixel-ish label with a dark outline. Emoji are stripped on purpose.
  void _text(Canvas c, String text, double x, double y,
      {double size = 10, Color color = Colors.white, bool bold = true, bool plate = false}) {
    final clean = _clean(text);
    if (clean.isEmpty) return;
    // Tiny text turns digits like 2/3/8 into blobs, so keep a readable minimum
    // and put every label that holds numbers on a dark plate.
    if (size < 13) size = 13;
    if (RegExp(r'[0-9]').hasMatch(clean)) plate = true;
    final tp = _tp(clean, size, color, bold);
    final dx = x - tp.width / 2;
    final dy = y - tp.height / 2;
    if (plate) {
      _p.color = const Color(0xCC0E0B0A);
      c.drawRect(Rect.fromLTWH(dx - 3, dy - 1, tp.width + 6, tp.height + 2), _p);
    } else {
      final o = _tp(clean, size, Pal.outline, bold);
      for (final d in const [Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1)]) {
        o.paint(c, Offset(dx + d.dx, dy + d.dy));
      }
    }
    tp.paint(c, Offset(dx, dy));
  }

  static final RegExp _emoji = RegExp(
      r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
      unicode: true);
  static final RegExp _iconToken = RegExp(r'\{[a-z_]+\}');
  String _clean(String s) =>
      s.replaceAll(_emoji, '').replaceAll(_iconToken, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ---------------------------------------------------------------------------
  // paint
  // ---------------------------------------------------------------------------
  @override
  void paint(Canvas canvas, Size size) {
    final scale = engine.getEffectiveScale(size);
    final cam = engine.getCameraTopLeft(size);
    final camX = (cam.dx / kPx).round() * kPx;
    final camY = (cam.dy / kPx).round() * kPx;

    canvas.save();
    canvas.scale(scale);
    canvas.translate(-camX, -camY);
    canvas.clipRect(Rect.fromLTWH(0, 0, engine.worldWidth, engine.worldHeight));

    if (_staticPicture == null) {
      final rec = ui.PictureRecorder();
      _paintStaticWorld(Canvas(rec));
      _staticPicture = rec.endRecording();
    }
    canvas.drawPicture(_staticPicture!);

    _paintAlley(canvas);
    _paintCourierZone(canvas);
    _paintLockedFloorPlates(canvas);
    _paintSorted(canvas);
    _paintFlyingItems(canvas);
    _paintLighting(canvas);
    _paintLockedExpansion(canvas);
    _paintMouseTarget(canvas);
    _paintDeliveryMarker(canvas);
    _paintParticles(canvas);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PixelPainter oldDelegate) => true;

  // ---------------------------------------------------------------------------
  // static world (cached): street, facade, floor, walls, rug, decorations
  // ---------------------------------------------------------------------------
  void _paintStaticWorld(Canvas c) {
    final W = engine.worldWidth;
    final H = engine.worldHeight;
    final doorCenter = W / 2;

    // Road + pavement (street at the front of the shop)
    _wr(c, Rect.fromLTWH(0, 0, W, 150), Pal.asphalt);
    for (double x = 0; x < W; x += 150) {
      _wr(c, Rect.fromLTWH(x + 30, 72, 78, 6), Pal.asphaltLine);
    }
    for (double y = 150; y < 200; y += 12) {
      for (double x = 0; x < W; x += 24) {
        final h = _hash((x ~/ 24), (y ~/ 12));
        _wr(c, Rect.fromLTWH(x, y, 24, 12), (h % 3 == 0) ? Pal.pave2 : Pal.pave1);
        _wr(c, Rect.fromLTWH(x, y + 9, 24, 3), const Color(0xFF38352F));
      }
    }

    // Facade (front wall of the shop, y 196..252)
    _wr(c, Rect.fromLTWH(0, 196, W, 58), Pal.wallMid);
    for (double x = 0; x < W; x += 12) {
      _wr(c, Rect.fromLTWH(x, 196, 3, 58), Pal.wallDark);
    }
    _wr(c, Rect.fromLTWH(0, 196, W, 6), Pal.trim);
    // wainscot
    _wr(c, Rect.fromLTWH(0, 228, W, 26), Pal.wainscot);
    for (double x = 0; x < W; x += 30) {
      _wr(c, Rect.fromLTWH(x, 228, 3, 26), Pal.wainscotDark);
    }
    _wr(c, Rect.fromLTWH(0, 225, W, 3), Pal.trim);
    _wr(c, Rect.fromLTWH(0, 252, W, 3), Pal.trim);

    // Shop windows (lit glass) left and right of the door
    for (final wx in [250.0, 520.0, 1380.0, 1650.0]) {
      _wr(c, Rect.fromLTWH(wx, 204, 150, 42), Pal.trim);
      _wr(c, Rect.fromLTWH(wx + 6, 210, 138, 30), const Color(0xFF3E5F63));
      _wr(c, Rect.fromLTWH(wx + 6, 210, 138, 9), const Color(0xFF557C80));
      _wr(c, Rect.fromLTWH(wx + 72, 210, 6, 30), Pal.trim);
    }

    // Door opening + mat
    _wr(c, Rect.fromLTWH(doorCenter - 150, 196, 300, 62), Pal.trim);
    _wr(c, Rect.fromLTWH(doorCenter - 138, 204, 276, 54), const Color(0xFF1A1411));
    _wr(c, Rect.fromLTWH(doorCenter - 120, 240, 240, 12), const Color(0xFF3A2A22));

    // Shop sign above the door
    _wr(c, Rect.fromLTWH(doorCenter - 132, 150, 264, 42), Pal.woodDark);
    _wr(c, Rect.fromLTWH(doorCenter - 126, 156, 252, 30), Pal.wood);
    _wr(c, Rect.fromLTWH(doorCenter - 126, 156, 252, 6), Pal.woodLight);

    // Interior floor (wooden planks)
    const floorTop = 255.0;
    final floorBottom = 990.0;
    for (double y = floorTop; y < floorBottom; y += 18) {
      final row = ((y - floorTop) ~/ 18);
      double x = -((row * 37) % 96).toDouble();
      while (x < W) {
        final len = 72.0 + (_hash(row, x ~/ 24) % 4) * 12.0;
        final h = _hash(row, (x ~/ 12) + 7);
        final col = h % 3 == 0 ? Pal.floorA : (h % 3 == 1 ? Pal.floorB : Pal.floorC);
        _wr(c, Rect.fromLTWH(x, y, len, 18), col);
        _wr(c, Rect.fromLTWH(x, y + 15, len, 3), Pal.grout);
        _wr(c, Rect.fromLTWH(x + len - 3, y, 3, 18), Pal.grout);
        x += len;
      }
    }

    // Side walls (inside)
    for (final sx in [0.0, W - 90]) {
      _wr(c, Rect.fromLTWH(sx, 255, 90, floorBottom - 255), Pal.wallMid);
      for (double y = 255; y < floorBottom; y += 12) {
        _wr(c, Rect.fromLTWH(sx, y, 90, 3), Pal.wallDark);
      }
    }
    _wr(c, Rect.fromLTWH(84, 255, 6, floorBottom - 255), Pal.trim);
    _wr(c, Rect.fromLTWH(W - 90, 255, 6, floorBottom - 255), Pal.trim);

    // Back wall + back door
    _wr(c, Rect.fromLTWH(0, floorBottom, W, 20), Pal.wallDark);
    _wr(c, Rect.fromLTWH(0, floorBottom, W, 5), Pal.trim);
    for (double x = 0; x < W; x += 12) {
      _wr(c, Rect.fromLTWH(x, floorBottom + 5, 3, 15), Pal.wallMid);
    }
    _wr(c, Rect.fromLTWH(doorCenter - 150, floorBottom - 6, 300, 26), Pal.trim);
    _wr(c, Rect.fromLTWH(doorCenter - 138, floorBottom, 276, 20), const Color(0xFF1A1411));
    // yellow hazard strip in front of the back door (delivery spot)
    for (double x = doorCenter - 150; x < doorCenter + 150; x += 24) {
      _wr(c, Rect.fromLTWH(x, floorBottom - 18, 12, 6), const Color(0xFF9A7A24));
    }

    // Rug in the entrance aisle (red, gold border) like a cosy shop carpet
    final rug = Rect.fromLTWH(doorCenter - 150, 270, 300, 380);
    _wr(c, rug, Pal.rugGold);
    _wr(c, rug.deflate(9), Pal.rugBase);
    _wr(c, rug.deflate(18), Pal.rugMid);
    _wr(c, rug.deflate(27), Pal.rugBase);
    for (double y = rug.top + 45; y < rug.bottom - 45; y += 54) {
      _wr(c, Rect.fromCenter(center: Offset(doorCenter, y + 18), width: 30, height: 30), Pal.rugGold);
      _wr(c, Rect.fromCenter(center: Offset(doorCenter, y + 18), width: 18, height: 18), Pal.rugMid);
      _wr(c, Rect.fromCenter(center: Offset(doorCenter, y + 18), width: 6, height: 6), Pal.rugGold);
    }

    // Wall decoration: framed posters on the facade (inside face)
    for (final px in [700.0, 1250.0, 1560.0]) {
      _wr(c, Rect.fromLTWH(px, 232, 48, 21), Pal.woodDark);
      _wr(c, Rect.fromLTWH(px + 3, 235, 42, 15), const Color(0xFFB9A57A));
      _wr(c, Rect.fromLTWH(px + 9, 238, 12, 9), const Color(0xFF7A3B2E));
      _wr(c, Rect.fromLTWH(px + 24, 241, 15, 6), const Color(0xFF3E5F63));
    }

    // Back alley ground (truck road)
    _wr(c, Rect.fromLTWH(0, floorBottom + 20, W, H - floorBottom - 20), Pal.asphalt);
    for (double x = 0; x < W; x += 120) {
      _wr(c, Rect.fromLTWH(x + 20, H - 18, 60, 6), Pal.asphaltLine);
    }
  }

  void _paintAlley(Canvas c) {
    // Delivery truck driving along the back alley
    if (!engine.isTruckArriving) return;
    final x = _snap(engine.truckX);
    const y = 1030.0;
    // cargo box
    _r(c, x, y, -24, -10, 28, 16, Pal.outline);
    _r(c, x, y, -23, -9, 26, 14, const Color(0xFFD7D2C4));
    _r(c, x, y, -23, -9, 26, 2, const Color(0xFFEFEADB));
    _r(c, x, y, -23, 3, 26, 2, const Color(0xFF9E9886));
    _r(c, x, y, -18, -5, 16, 5, const Color(0xFF9A5A2E)); // crate logo
    // cab
    _r(c, x, y, 4, -6, 12, 12, Pal.outline);
    _r(c, x, y, 5, -5, 10, 10, const Color(0xFF3B6EA5));
    _r(c, x, y, 8, -4, 6, 4, const Color(0xFF9CC4E0));
    // wheels
    for (final wx in [-16.0, 8.0]) {
      _r(c, x, y, wx - 1, 3, 6, 6, Pal.outline);
      _r(c, x, y, wx, 4, 4, 4, const Color(0xFF3A3A40));
    }
    _text(c, 'DELIVERY', x - 30, y - 42, size: 9, color: const Color(0xFFFDE68A));
  }

  void _paintCourierZone(Canvas c) {
    // Parking spot marking in front of the courier stop (on the pavement)
    final r = engine.courierStation;
    _wr(c, Rect.fromLTWH(r.left, r.top + 40, r.width, 3), const Color(0xFF8A8478));
    _wr(c, Rect.fromLTWH(r.left, r.top + 40, 3, 30), const Color(0xFF8A8478));
    _wr(c, Rect.fromLTWH(r.right - 3, r.top + 40, 3, 30), const Color(0xFF8A8478));
    _text(c, 'COURIER STOP', r.center.dx, r.top - 6, size: 9, color: const Color(0xFFFDE68A));
  }

  // ---------------------------------------------------------------------------
  // y-sorted objects
  // ---------------------------------------------------------------------------
  void _paintSorted(Canvas c) {
    final items = <MapEntry<double, void Function()>>[];
    void add(double y, void Function() fn) => items.add(MapEntry(y, fn));

    for (final s in engine.shelves) {
      if (s.isUnlocked) add(s.rect.bottom - 6, () => _drawShelf(c, s));
    }
    for (int i = 0; i < engine.unlockedCheckoutCount; i++) {
      final r = engine.checkoutCounters[i];
      final idx = i;
      add(r.bottom - 6, () => _drawCheckout(c, r, idx));
    }
    add(engine.computerDesk.bottom - 6, () => _drawComputerDesk(c));
    add(engine.courierPackingDesk.bottom - 6, () => _drawPackingDesk(c));
    add(engine.trashCan.bottom - 4, () => _drawTrash(c));

    for (final b in engine.deliveryBoxes) {
      add(b.y, () => _drawDeliveryBox(c, b));
    }
    if (engine.courierX < engine.worldWidth + 60 && engine.courierState != CourierState.away) {
      add(172, () => _drawCourierBike(c));
    }
    if (engine.hasAutoCashier && engine.staffOnDuty) {
      for (int i = 0; i < engine.unlockedCheckoutCount; i++) {
        final r = engine.checkoutCounters[i];
        add(r.top - 6, () => _drawPerson(c, r.center.dx - 14, r.top - 14, facing: 0, phase: 0,
            shirt: const Color(0xFF2F6E9E), pants: const Color(0xFF1E2430), hair: const Color(0xFF6B3F1E)));
      }
    }
    if (engine.hasRestocker && engine.isRestockerHired && !engine.restockerAtHome) {
      add(engine.restocker.y, () => _drawRestocker(c));
    }
    for (final cu in engine.customers) {
      add(cu.y, () => _drawCustomer(c, cu));
    }
    for (final t in engine.thieves) {
      add(t.y, () => _drawThief(c, t));
    }
    add(engine.playerY, () => _drawPlayer(c));

    items.sort((a, b) => a.key.compareTo(b.key));
    for (final it in items) {
      it.value();
    }
  }

  // ---------------------------------------------------------------------------
  // product icons (5x5 art pixels)
  // ---------------------------------------------------------------------------
  void _icon(Canvas c, SimProductType t, double wx, double wy) {
    switch (t) {
      case SimProductType.milk:
        _r(c, wx, wy, 1, 1, 3, 4, const Color(0xFFF2F0E8));
        _r(c, wx, wy, 1, 0, 3, 1, const Color(0xFF3B78C2));
        _r(c, wx, wy, 1, 3, 3, 1, const Color(0xFF6FA2DD));
        break;
      case SimProductType.flour:
        _r(c, wx, wy, 0, 1, 5, 4, const Color(0xFFD9C9A0));
        _r(c, wx, wy, 1, 0, 3, 1, const Color(0xFF8A6A3C));
        _r(c, wx, wy, 0, 4, 5, 1, const Color(0xFFB09C70));
        break;
      case SimProductType.egg:
        _r(c, wx, wy, 0, 3, 5, 2, const Color(0xFF8A6A3C));
        _r(c, wx, wy, 0, 1, 2, 3, const Color(0xFFF1E3C2));
        _r(c, wx, wy, 3, 1, 2, 3, const Color(0xFFF1E3C2));
        break;
      case SimProductType.tomato:
        _r(c, wx, wy, 0, 1, 5, 4, const Color(0xFFD33A2C));
        _r(c, wx, wy, 1, 2, 1, 1, const Color(0xFFF08A7A));
        _r(c, wx, wy, 1, 0, 3, 1, const Color(0xFF3E8E3A));
        break;
      case SimProductType.pepper:
        _r(c, wx, wy, 1, 1, 3, 4, const Color(0xFF3FA13A));
        _r(c, wx, wy, 2, 0, 1, 1, const Color(0xFF2B6B28));
        _r(c, wx, wy, 1, 4, 3, 1, const Color(0xFF2B7A2A));
        break;
      case SimProductType.cheese:
        _r(c, wx, wy, 0, 2, 5, 3, const Color(0xFFE6B73A));
        _r(c, wx, wy, 1, 1, 3, 1, const Color(0xFFF2CF63));
        _r(c, wx, wy, 1, 3, 1, 1, const Color(0xFFB88A1E));
        _r(c, wx, wy, 3, 2, 1, 1, const Color(0xFFB88A1E));
        break;
      case SimProductType.apple:
        _r(c, wx, wy, 0, 1, 5, 4, const Color(0xFF9CC23A));
        _r(c, wx, wy, 1, 2, 1, 1, const Color(0xFFD4EC7A));
        _r(c, wx, wy, 2, 0, 1, 1, const Color(0xFF6B4423));
        break;
      case SimProductType.bread:
        _r(c, wx, wy, 0, 2, 5, 3, const Color(0xFFB9742E));
        _r(c, wx, wy, 1, 1, 3, 1, const Color(0xFFD9964A));
        _r(c, wx, wy, 1, 3, 1, 1, const Color(0xFF8A5220));
        _r(c, wx, wy, 3, 3, 1, 1, const Color(0xFF8A5220));
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // furniture
  // ---------------------------------------------------------------------------
  void _drawShelf(Canvas c, StoreShelf s) {
    final r = s.rect;
    final x = _snap(r.left);
    final y = _snap(r.top);
    final gw = (r.width / kPx).round();
    final gh = (r.height / kPx).round();
    final isCooler = s.assignedProduct == SimProductType.milk ||
        s.assignedProduct == SimProductType.cheese;
    final isStand = s.assignedProduct == SimProductType.tomato ||
        s.assignedProduct == SimProductType.pepper ||
        s.assignedProduct == SimProductType.apple;

    final frame = isCooler ? const Color(0xFF3A5266) : Pal.wood;
    final frameDark = isCooler ? const Color(0xFF263644) : Pal.woodDark;
    final back = isCooler ? const Color(0xFF1B2833) : const Color(0xFF2E2118);

    // ground shadow
    _r(c, x, y, 1, gh - 1, gw, 3, Pal.shadow);
    // outline + frame
    _r(c, x, y, -1, -1, gw + 2, gh + 2, Pal.outline);
    _r(c, x, y, 0, 0, gw, gh, frame);
    _r(c, x, y, 0, 0, gw, 2, isCooler ? const Color(0xFF5B7A92) : Pal.woodLight);
    _r(c, x, y, 2, 3, gw - 4, gh - 6, back);

    final innerW = gw - 4;
    final innerH = gh - 6;
    final rows = max(2, (innerH / 10).floor());
    final rowH = innerH / rows;
    final cols = max(1, ((innerW - 1) / 6).floor());
    final total = rows * cols;
    final filled = (s.maxCapacity <= 0) ? 0 : (s.currentStock / s.maxCapacity * total).ceil().clamp(0, total).toInt();
    int placed = 0;
    for (int row = 0; row < rows; row++) {
      final ry = 3 + ((row + 1) * rowH).round();
      // shelf board
      _r(c, x, y, 2, ry - 1, innerW, 1, frameDark);
      for (int col = 0; col < cols; col++) {
        if (placed >= filled) break;
        placed++;
        final ix = 2 + 1 + col * 6;
        if (isStand) {
          _icon(c, s.assignedProduct, x + ix * kPx, y + (ry - 5) * kPx);
        } else {
          _icon(c, s.assignedProduct, x + ix * kPx, y + (ry - 6) * kPx);
        }
      }
    }
    if (isCooler) {
      // glass shine
      _r(c, x, y, 3, 4, 2, gh - 9, const Color(0x22FFFFFF));
      _r(c, x, y, 7, 4, 1, gh - 9, const Color(0x14FFFFFF));
    }
    if (s.isHovered) {
      _p.color = const Color(0xAAFFFFFF);
      _p.style = PaintingStyle.stroke;
      _p.strokeWidth = kPx;
      c.drawRect(Rect.fromLTWH(x - kPx, y - kPx, (gw + 2) * kPx, (gh + 2) * kPx), _p);
      _p.style = PaintingStyle.fill;
    }
    // price/stock plate
    final def = productCatalog[s.assignedProduct]!;
    _text(c, '${def.name}  ${s.currentStock}/${s.maxCapacity}', r.center.dx, r.top - 9,
        size: 9, color: s.currentStock == 0 ? const Color(0xFFFF8A80) : Colors.white, plate: true);
  }

  void _drawCheckout(Canvas c, Rect r, int index) {
    final x = _snap(r.left);
    final y = _snap(r.top);
    final gw = (r.width / kPx).round();
    final gh = (r.height / kPx).round();
    _r(c, x, y, 1, gh - 1, gw, 3, Pal.shadow);
    _r(c, x, y, -1, -1, gw + 2, gh + 2, Pal.outline);
    _r(c, x, y, 0, 0, gw, gh, Pal.wood);
    _r(c, x, y, 0, 0, gw, 3, Pal.woodLight);
    _r(c, x, y, 0, gh - 7, gw, 7, Pal.woodDark);
    // conveyor belt
    _r(c, x, y, 3, 5, gw - 22, 9, const Color(0xFF2A2A30));
    for (int i = 0; i < gw - 22; i += 4) {
      _r(c, x, y, 3 + i, 5, 1, 9, const Color(0xFF3A3A42));
    }
    // register
    _r(c, x, y, gw - 17, 3, 14, 12, Pal.outline);
    _r(c, x, y, gw - 16, 4, 12, 10, const Color(0xFF8E9096));
    _r(c, x, y, gw - 14, 5, 8, 4, const Color(0xFF3DDC84));
    _r(c, x, y, gw - 14, 10, 8, 2, const Color(0xFF55585E));
    // scanner glow
    _r(c, x, y, gw - 24, 9, 5, 2, const Color(0xFFE53935));
    _text(c, 'REGISTER ${index + 1}', r.center.dx, r.top - 8, size: 9, color: const Color(0xFFFDE68A), plate: true);
  }

  void _drawComputerDesk(Canvas c) {
    final r = engine.computerDesk;
    final x = _snap(r.left);
    final y = _snap(r.top);
    final gw = (r.width / kPx).round();
    final gh = (r.height / kPx).round();
    _r(c, x, y, 1, gh - 1, gw, 3, Pal.shadow);
    _r(c, x, y, -1, -1, gw + 2, gh + 2, Pal.outline);
    _r(c, x, y, 0, 0, gw, gh, Pal.wood);
    _r(c, x, y, 0, 0, gw, 3, Pal.woodLight);
    _r(c, x, y, 0, gh - 8, gw, 8, Pal.woodDark);
    // CRT monitor
    final mx = (gw / 2 - 9).round();
    _r(c, x, y, mx - 1, -9, 20, 17, Pal.outline);
    _r(c, x, y, mx, -8, 18, 15, const Color(0xFFCFC8B4));
    _r(c, x, y, mx + 2, -6, 14, 10, const Color(0xFF17302C));
    final blink = (engine.worldTime * 2).floor() % 2 == 0;
    _r(c, x, y, mx + 4, -4, 6, 1, const Color(0xFF59F0B0));
    _r(c, x, y, mx + 4, -2, 9, 1, const Color(0xFF59F0B0));
    if (blink) _r(c, x, y, mx + 4, 0, 2, 2, const Color(0xFF59F0B0));
    _r(c, x, y, mx + 4, 8, 10, 2, const Color(0xFFB9B29E)); // base
    // keyboard
    _r(c, x, y, mx - 2, 10, 22, 4, const Color(0xFF9C9684));
    _r(c, x, y, mx - 1, 11, 20, 2, const Color(0xFF6C6858));
    _text(c, 'COMPUTER', r.center.dx, r.top - 22, size: 9, color: const Color(0xFFFDE68A), plate: true);
    if (r.inflate(15).contains(Offset(engine.mouseWorldX, engine.mouseWorldY))) {
      _p.color = const Color(0xAAFFFFFF);
      _p.style = PaintingStyle.stroke;
      _p.strokeWidth = kPx;
      c.drawRect(Rect.fromLTWH(x - kPx, y - kPx, (gw + 2) * kPx, (gh + 2) * kPx), _p);
      _p.style = PaintingStyle.fill;
    }
  }

  void _drawPackingDesk(Canvas c) {
    final r = engine.courierPackingDesk;
    final x = _snap(r.left);
    final y = _snap(r.top);
    final gw = (r.width / kPx).round();
    final gh = (r.height / kPx).round();
    _r(c, x, y, 1, gh - 1, gw, 3, Pal.shadow);
    _r(c, x, y, -1, -1, gw + 2, gh + 2, Pal.outline);
    _r(c, x, y, 0, 0, gw, gh, const Color(0xFF6D7A80));
    _r(c, x, y, 0, 0, gw, 3, const Color(0xFF8E9CA3));
    _r(c, x, y, 0, gh - 6, gw, 6, const Color(0xFF475358));
    // parcels + tape
    _r(c, x, y, 4, 5, 12, 9, Pal.outline);
    _r(c, x, y, 5, 6, 10, 7, const Color(0xFFB88A55));
    _r(c, x, y, 9, 6, 2, 7, const Color(0xFFE9D9A8));
    if (engine.courierStagedCount > 0 && engine.courierStagedProduct != null) {
      _icon(c, engine.courierStagedProduct!, x + 22 * kPx, y + 7 * kPx);
      _text(c, 'x${engine.courierStagedCount}', r.center.dx + 10, r.top + 6, size: 9);
    }
    _text(c, 'PACKING', r.center.dx, r.top - 8, size: 9, color: const Color(0xFFFDE68A), plate: true);
  }

  void _drawTrash(Canvas c) {
    final r = engine.trashCan;
    final x = _snap(r.left);
    final y = _snap(r.top);
    _r(c, x, y, 1, 18, 21, 3, Pal.shadow);
    _r(c, x, y, 0, 3, 22, 18, Pal.outline);
    _r(c, x, y, 1, 4, 20, 16, const Color(0xFF5E666B));
    _r(c, x, y, 1, 4, 20, 3, const Color(0xFF7E888E));
    for (int i = 4; i < 20; i += 5) {
      _r(c, x, y, i, 8, 1, 11, const Color(0xFF454C50));
    }
    _r(c, x, y, 0, 1, 22, 3, const Color(0xFF8E989E));
  }

  void _drawDeliveryBox(Canvas c, DeliveryBox b) {
    final x = _snap(b.x - 18);
    final y = _snap(b.y - 15);
    _r(c, x, y, 1, 9, 13, 2, Pal.shadow);
    _r(c, x, y, -1, 0, 14, 11, Pal.outline);
    _r(c, x, y, 0, 1, 12, 9, const Color(0xFFB98A55));
    _r(c, x, y, 0, 1, 12, 2, const Color(0xFFD9AE76));
    _r(c, x, y, 5, 1, 2, 9, const Color(0xFFE9D9A8));
    _icon(c, b.productType, x + 3.5 * kPx, y + 2.5 * kPx);
    if (b.isHovered) {
      _p.color = const Color(0xAAFFFFFF);
      _p.style = PaintingStyle.stroke;
      _p.strokeWidth = kPx;
      c.drawRect(Rect.fromLTWH(x - kPx * 2, y - kPx, 16 * kPx, 13 * kPx), _p);
      _p.style = PaintingStyle.fill;
    }
    _text(c, 'x${b.currentCount}', b.x, b.y - 28, size: 9);
  }

  void _drawCourierBike(Canvas c) {
    final x = _snap(engine.courierX);
    const y = 171.0;
    _r(c, x, y, -9, 5, 22, 3, Pal.shadow);
    // scooter body
    _r(c, x, y, -10, -1, 22, 8, Pal.outline);
    _r(c, x, y, -9, 0, 20, 6, const Color(0xFFD64B3C));
    _r(c, x, y, -9, 0, 20, 2, const Color(0xFFEE7A6B));
    _r(c, x, y, -7, -5, 8, 5, const Color(0xFF8E4A22)); // delivery box
    _r(c, x, y, -7, -5, 8, 1, const Color(0xFFC08A55));
    for (final wx in [-9.0, 8.0]) {
      _r(c, x, y, wx - 1, 3, 6, 6, Pal.outline);
      _r(c, x, y, wx, 4, 4, 4, const Color(0xFF2B2B30));
    }
    // rider
    _r(c, x, y, 2, -11, 6, 12, Pal.outline);
    _r(c, x, y, 3, -10, 4, 5, Pal.skin);
    _r(c, x, y, 3, -11, 5, 3, const Color(0xFF2E5E8E));
    _r(c, x, y, 3, -6, 5, 6, const Color(0xFFDDA82E));
    if (engine.courierState == CourierState.waitingForOrder && engine.activeCourierOrder != null) {
      final o = engine.activeCourierOrder!;
      _p.color = const Color(0xEEFFF8E1);
      c.drawRect(Rect.fromLTWH(x - 14 * kPx, y - 44 * kPx / 2 - 24, 30 * kPx, 9 * kPx), _p);
      _icon(c, o.productType, x - 12 * kPx, y - 44 * kPx / 2 - 22);
      _text(c, '${o.deliveredQty}/${o.requiredQty}  ${o.remainingTime.toInt()}s', x + 6 * kPx, y - 44 * kPx / 2 - 10,
          size: 9, color: const Color(0xFF3B2A14), bold: true, plate: false);
    }
  }

  // ---------------------------------------------------------------------------
  // people
  // ---------------------------------------------------------------------------
  int _facingFromAngle(double a) {
    final cx = cos(a), sy = sin(a);
    if (cx.abs() > sy.abs()) return cx < 0 ? 1 : 2;
    return sy > 0 ? 0 : 3;
  }

  void _drawPerson(
    Canvas c,
    double wx,
    double wy, {
    required int facing,
    required double phase,
    required Color shirt,
    required Color pants,
    required Color hair,
    Color skin = Pal.skin,
    Color? hat,
    Color? mask,
    bool backpack = false,
    bool glasses = false,
    bool flash = false,
  }) {
    final x = _snap(wx);
    final y = _snap(wy);
    final liftL = phase > 0.35;
    final liftR = phase < -0.35;
    final bob = (phase.abs() > 0.7) ? 1 : 0;
    final shirtC = flash ? Colors.white : shirt;
    final pantsC = flash ? Colors.white : pants;
    final skinC = flash ? Colors.white : skin;
    final hairC = flash ? Colors.white : hair;

    // shadow
    _r(c, x, y, -5, 5, 10, 2, Pal.shadow);
    _r(c, x, y, -4, 6, 8, 1, Pal.shadow);

    final side = facing == 1 || facing == 2;
    final dir = facing == 1 ? -1 : 1;

    // --- legs
    if (!side) {
      _r(c, x, y, -4, 0, 8, 7, Pal.outline);
      _r(c, x, y, -3, 1, 3, liftL ? 3 : 4, pantsC);
      _r(c, x, y, 1, 1, 3, liftR ? 3 : 4, pantsC);
      _r(c, x, y, -3, liftL ? 4 : 5, 3, 1, const Color(0xFF1A1512));
      _r(c, x, y, 1, liftR ? 4 : 5, 3, 1, const Color(0xFF1A1512));
    } else {
      final f = (phase * 2).round().clamp(-1, 1).toInt();
      _r(c, x, y, -4, 0, 8, 7, Pal.outline);
      _r(c, x, y, -2 + f, 1, 3, 4, pantsC);
      _r(c, x, y, 0 - f, 1, 3, 4, pantsC);
      _r(c, x, y, -2 + f + (dir > 0 ? 1 : 0), 5, 3, 1, const Color(0xFF1A1512));
      _r(c, x, y, 0 - f + (dir > 0 ? 1 : 0), 5, 3, 1, const Color(0xFF1A1512));
    }

    // --- backpack (behind the torso)
    if (backpack && (facing == 3 || side)) {
      _r(c, x, y, side ? (dir > 0 ? -6 : 3) : -4, -5 + bob, 3, 5, const Color(0xFF8B2E2E));
    }

    // --- torso + arms
    final ty = -6 + bob;
    if (!side) {
      _r(c, x, y, -7, ty - 1, 14, 9, Pal.outline);
      _r(c, x, y, -4, ty, 8, 7, shirtC);
      _r(c, x, y, -4, ty + 5, 8, 2, Color.lerp(shirtC, Colors.black, 0.25)!);
      final swing = (phase * 1.5).round().clamp(-1, 1).toInt();
      _r(c, x, y, -6, ty + 1 + swing, 2, 5, shirtC);
      _r(c, x, y, 4, ty + 1 - swing, 2, 5, shirtC);
      _r(c, x, y, -6, ty + 6 + swing, 2, 1, skinC);
      _r(c, x, y, 4, ty + 6 - swing, 2, 1, skinC);
    } else {
      _r(c, x, y, -5, ty - 1, 10, 9, Pal.outline);
      _r(c, x, y, -3, ty, 6, 7, shirtC);
      _r(c, x, y, -3, ty + 5, 6, 2, Color.lerp(shirtC, Colors.black, 0.25)!);
      final swing = (phase * 2).round().clamp(-1, 1).toInt();
      _r(c, x, y, -1 + swing, ty + 1, 2, 5, Color.lerp(shirtC, Colors.black, 0.12)!);
      _r(c, x, y, -1 + swing, ty + 6, 2, 1, skinC);
    }

    // --- head
    final hy = -12 + bob;
    _r(c, x, y, -4, hy - 1, 8, 8, Pal.outline);
    _r(c, x, y, -3, hy, 6, 6, skinC);
    if (facing == 0) {
      _r(c, x, y, -3, hy, 6, 2, hairC);
      _r(c, x, y, -2, hy + 3, 1, 1, const Color(0xFF1A1512));
      _r(c, x, y, 1, hy + 3, 1, 1, const Color(0xFF1A1512));
      if (glasses) {
        _r(c, x, y, -3, hy + 3, 6, 1, const Color(0xFF111111));
      }
    } else if (facing == 3) {
      _r(c, x, y, -3, hy, 6, 5, hairC);
    } else {
      _r(c, x, y, -3, hy, 6, 2, hairC);
      _r(c, x, y, dir > 0 ? -3 : 1, hy + 2, 2, 3, hairC);
      _r(c, x, y, dir > 0 ? 1 : -2, hy + 3, 1, 1, const Color(0xFF1A1512));
      if (glasses) {
        _r(c, x, y, dir > 0 ? 0 : -3, hy + 3, 3, 1, const Color(0xFF111111));
      }
    }
    if (mask != null && facing != 3) {
      _r(c, x, y, -3, hy + 2, 6, 2, mask);
    }
    if (hat != null) {
      _r(c, x, y, -4, hy - 2, 8, 3, hat);
      _r(c, x, y, -4, hy, 8, 1, Color.lerp(hat, Colors.black, 0.3)!);
    }
  }

  void _drawPlayer(Canvas c) {
    final px = engine.playerX, py = engine.playerY;
    final moving = engine.playerSpeedNow > 25;
    final phase = moving ? sin(engine.walkAnimTime * 0.9) : 0.0;
    // selection ring on the floor
    _p.color = const Color(0x66F59E0B);
    c.drawRect(Rect.fromCenter(center: Offset(_snap(px), _snap(py) + 18), width: 15 * kPx, height: 3 * kPx), _p);
    _drawPerson(c, px, py,
        facing: engine.playerFacing,
        phase: phase,
        shirt: const Color(0xFFC2581E),
        pants: const Color(0xFF1F2733),
        hair: const Color(0xFF2A1D16),
        hat: null);
    if (engine.carriedBox != null) {
      final b = engine.carriedBox!;
      final bx = _snap(px) - 5 * kPx;
      final by = _snap(py) - 27 * kPx;
      _r(c, bx, by, -1, 0, 12, 9, Pal.outline);
      _r(c, bx, by, 0, 1, 10, 7, b.isCourierPackage ? const Color(0xFFE8D6A0) : const Color(0xFFB98A55));
      _icon(c, b.productType, bx + 2.5 * kPx, by + 2 * kPx);
      _text(c, '${b.currentCount}/${b.maxCount}', px, py - 92, size: 9);
    }
    _drawStick(c, px, py);
  }

  void _drawStick(Canvas c, double px, double py) {
    final swinging = engine.stickSwingTimer > 0;
    if (!engine.isNight && !swinging) return;
    final dir = swinging ? engine.stickHitDirX : (engine.playerFacing == 1 ? -1.0 : 1.0);
    final t = 1.0 - engine.stickSwingTimer;
    final pivot = Offset(_snap(px) + dir * 6 * kPx, _snap(py) - 1 * kPx);
    void stick(double a, Color col) {
      for (int k = 1; k <= 9; k++) {
        final sx = pivot.dx + dir * sin(a) * k * kPx;
        final sy = pivot.dy - cos(a) * k * kPx;
        _p.color = k > 6 ? Color.lerp(col, Colors.white, 0.25)! : col;
        c.drawRect(Rect.fromLTWH(_snap(sx), _snap(sy), 2 * kPx, 2 * kPx), _p);
      }
    }
    if (swinging) {
      final a = -0.6 + t * 2.6;
      stick(a - 0.55, const Color(0x55E7C58A));
      stick(a - 0.28, const Color(0x99D9A860));
      stick(a, const Color(0xFF9B6A32));
    } else {
      stick(0.35, const Color(0xFF9B6A32));
    }
  }

  void _drawCustomer(Canvas c, SimCustomer cu) {
    final walking = cu.state != CustomerState.waitingAtCheckout && cu.shelfGrabTimer <= 0;
    final seed = cu.id.hashCode % 628;
    final phase = walking ? sin(engine.worldTime * 7.5 + seed) : 0.0;
    final facing = cu.state == CustomerState.waitingAtCheckout ? 3 : _facingFromAngle(cu.walkAngle);

    Color shirt, pants, hair;
    Color? hat;
    bool backpack = false, glasses = false;
    final h = cu.id.hashCode.abs();
    const shirts = [Color(0xFF3F7D5B), Color(0xFF7A4FA3), Color(0xFF3B6EA5), Color(0xFFB0553C), Color(0xFF8A8A3A), Color(0xFF2F8A8A)];
    const hairs = [Color(0xFF2A1D16), Color(0xFF5A3A22), Color(0xFFB8862E), Color(0xFF8A8A8A), Color(0xFF1A1A1A)];
    shirt = shirts[h % shirts.length];
    pants = const Color(0xFF2B3040);
    hair = hairs[(h ~/ 7) % hairs.length];
    switch (cu.archetype) {
      case CustomerArchetype.grandma:
        hair = const Color(0xFFD0CCC4);
        shirt = const Color(0xFF8A4F7A);
        pants = const Color(0xFF4A3A5A);
        break;
      case CustomerArchetype.athlete:
        shirt = const Color(0xFFD33A2C);
        pants = const Color(0xFF1F2A44);
        hat = const Color(0xFFEFEFEF);
        break;
      case CustomerArchetype.chef:
        shirt = const Color(0xFFEDEDED);
        pants = const Color(0xFF2B2B32);
        hat = const Color(0xFFF6F6F6);
        break;
      case CustomerArchetype.student:
        backpack = true;
        shirt = const Color(0xFF3B6EA5);
        break;
      case CustomerArchetype.family:
        shirt = const Color(0xFFC96A8E);
        break;
      case CustomerArchetype.vip:
        shirt = const Color(0xFF1E1E26);
        pants = const Color(0xFF14141A);
        glasses = true;
        hat = const Color(0xFFD9AE2E);
        break;
      case CustomerArchetype.regular:
        break;
    }
    _drawPerson(c, cu.x, cu.y,
        facing: facing, phase: phase, shirt: shirt, pants: pants, hair: hair, hat: hat, backpack: backpack, glasses: glasses);

    // shopping bag in hand
    if (cu.basket.isNotEmpty && cu.state != CustomerState.waitingAtCheckout) {
      _r(c, _snap(cu.x), _snap(cu.y), 5, -2, 4, 5, const Color(0xFF9C6B3A));
      _r(c, _snap(cu.x), _snap(cu.y), 5, -2, 4, 1, const Color(0xFFC79A62));
    }

    // thought bubble with the wanted product
    if (cu.state == CustomerState.shopping && cu.currentShoppingIndex < cu.shoppingList.length) {
      final want = cu.shoppingList[cu.currentShoppingIndex];
      final bx = _snap(cu.x) - 5 * kPx;
      final by = _snap(cu.y) - 30 * kPx;
      _r(c, bx, by, -1, -1, 12, 9, Pal.outline);
      _r(c, bx, by, 0, 0, 10, 7, const Color(0xFFF4EFE0));
      _r(c, bx, by, 4, 7, 2, 2, const Color(0xFFF4EFE0));
      _icon(c, want, bx + 2.5 * kPx, by + 1 * kPx);
    }

    // patience bar at the register
    if (cu.state == CustomerState.waitingAtCheckout) {
      final frac = (cu.patience / cu.maxPatience).clamp(0.0, 1.0).toDouble();
      final col = frac > 0.55 ? const Color(0xFF4CAF50) : (frac > 0.25 ? const Color(0xFFE0B030) : const Color(0xFFE04B3C));
      final bx = _snap(cu.x) - 8 * kPx;
      final by = _snap(cu.y) - 30 * kPx;
      _r(c, bx, by, 0, 0, 16, 4, Pal.outline);
      _r(c, bx, by, 1, 1, 14, 2, const Color(0xFF3A2F2A));
      _r(c, bx, by, 1, 1, (14 * frac).round(), 2, col);
      if (frac < 0.3 && (engine.worldTime * 4).floor() % 2 == 0) {
        _text(c, '!', cu.x, cu.y - 108, size: 13, color: const Color(0xFFFF5252));
      }
    }
  }

  void _drawThief(Canvas c, Thief t) {
    final walking = t.state == ThiefState.sneaking || t.state == ThiefState.fleeing;
    final phase = walking ? sin(t.walkAnim) : 0.0;
    final facing = t.state == ThiefState.stealing ? 3 : _facingFromAngle(t.walkAngle);
    _drawPerson(c, t.x, t.y,
        facing: facing,
        phase: phase,
        shirt: const Color(0xFF23252E),
        pants: const Color(0xFF15161C),
        hair: const Color(0xFF0E0E12),
        hat: const Color(0xFF2B2D3A),
        mask: const Color(0xFF050507),
        flash: t.hitFlash > 0.4);
    if (t.carried > 0) {
      _r(c, _snap(t.x), _snap(t.y), 3, -8, 6, 6, Pal.outline);
      _r(c, _snap(t.x), _snap(t.y), 4, -7, 4, 4, const Color(0xFF9C7A3A));
      _r(c, _snap(t.x), _snap(t.y), 5, -9, 2, 2, const Color(0xFF9C7A3A));
      if (t.loot != null) _icon(c, t.loot!, _snap(t.x) - 3 * kPx, _snap(t.y) - 22 * kPx);
    }
    // hp pips
    final bx = _snap(t.x) - t.maxHp * 2 * kPx;
    for (int i = 0; i < t.maxHp; i++) {
      _r(c, bx, _snap(t.y) - 22 * kPx, i * 4, 0, 3, 2, i < t.hp ? const Color(0xFFE04B3C) : const Color(0xFF3A2F2A));
    }
    if (t.state == ThiefState.stunned) {
      final a = engine.worldTime * 10;
      for (int i = 0; i < 3; i++) {
        final ang = a + i * 2.1;
        _r(c, _snap(t.x) + cos(ang) * 7 * kPx, _snap(t.y) - 17 * kPx + sin(ang) * 2 * kPx, 0, 0, 1, 1, const Color(0xFFFFE066));
      }
    }
  }

  void _drawRestocker(Canvas c) {
    final w = engine.restocker;
    final phase = sin(w.walkTimer);
    _drawPerson(c, w.x, w.y,
        facing: 0,
        phase: phase,
        shirt: const Color(0xFF1F8AA0),
        pants: const Color(0xFF1C2230),
        hair: const Color(0xFFD08A2E),
        hat: const Color(0xFFE0A020));
    if (w.carriedBox != null) {
      final bx = _snap(w.x) - 5 * kPx;
      final by = _snap(w.y) - 27 * kPx;
      _r(c, bx, by, -1, 0, 12, 9, Pal.outline);
      _r(c, bx, by, 0, 1, 10, 7, const Color(0xFFB98A55));
      _icon(c, w.carriedBox!.productType, bx + 2.5 * kPx, by + 2 * kPx);
    }
  }

  // ---------------------------------------------------------------------------
  // effects
  // ---------------------------------------------------------------------------
  void _paintFlyingItems(Canvas c) {
    for (final f in engine.flyingShelfItems) {
      final t = f.progress.clamp(0.0, 1.0).toDouble();
      final pos = Offset.lerp(f.startPos, f.endPos, t)!;
      final arc = -sin(t * pi) * 14;
      _icon(c, f.productType, _snap(pos.dx - 7), _snap(pos.dy + arc - 7));
    }
  }

  void _paintLockedFloorPlates(Canvas c) {
    // closed shelves (whose area is already open) show an outlined floor plate
    for (final s in engine.shelves) {
      if (s.isUnlocked || engine.storeLevel < s.zoneLevel) continue;
      final r = s.rect;
      _p.color = const Color(0x55FBBF24);
      _p.style = PaintingStyle.stroke;
      _p.strokeWidth = kPx;
      c.drawRect(Rect.fromLTWH(_snap(r.left), _snap(r.top), _snap(r.width), _snap(r.height)), _p);
      _p.style = PaintingStyle.fill;
      final def = productCatalog[s.assignedProduct]!;
      _icon(c, s.assignedProduct, _snap(r.center.dx) - 2.5 * kPx, _snap(r.center.dy) - 14);
      _text(c, def.name, r.center.dx, r.center.dy + 6, size: 9, color: const Color(0xFFFDE68A));
      _text(c, engine.shelfLockReason(s), r.center.dx, r.center.dy + 20, size: 9, color: const Color(0xFFFFFFFF));
    }
    for (int i = engine.unlockedCheckoutCount; i < engine.checkoutCounters.length; i++) {
      final r = engine.checkoutCounters[i];
      if (r.left < engine.storeMinX - 2) continue; // hidden behind the locked area
      _text(c, 'REGISTER ${i + 1}', r.center.dx, r.center.dy - 6, size: 9, color: const Color(0xFFFDE68A));
      _text(c, 'Store Level ${i + 1}', r.center.dx, r.center.dy + 8, size: 9);
    }
  }

  void _paintLockedExpansion(Canvas c) {
    const top = 255.0;
    final bottom = 990.0;
    final zones = <Rect>[
      if (engine.storeMinX > 95) Rect.fromLTRB(0, top, engine.storeMinX, bottom),
      if (engine.storeMaxX < engine.worldWidth - 95) Rect.fromLTRB(engine.storeMaxX, top, engine.worldWidth, bottom),
    ];
    for (final z in zones) {
      _wr(c, z, const Color(0xE60B0F18));
      for (double y = z.top; y < z.bottom; y += 36) {
        for (double x = z.left + ((y / 36).floor() % 2) * 18; x < z.right; x += 36) {
          _wr(c, Rect.fromLTWH(x, y, 9, 9), const Color(0x14FBBF24));
        }
      }
      final edgeX = z.left < 10 ? z.right - 6 : z.left;
      _wr(c, Rect.fromLTWH(edgeX, z.top, 6, z.height), const Color(0xFFB08A3E));
      for (double y = z.top; y < z.bottom; y += 60) {
        _wr(c, Rect.fromLTWH(edgeX - 3, y, 12, 12), const Color(0xFF6B4423));
      }
      final cx = z.center.dx;
      final cy = (z.top + z.bottom) / 2;
      _text(c, 'LOCKED AREA', cx, cy - 20, size: 14);
      if (engine.storeLevel < 3) {
        _text(c, 'Expand the store via Manager', cx, cy + 2, size: 10, color: const Color(0xFFFDE68A));
        _text(c, '\$${engine.nextLevelUpgradeCost.toStringAsFixed(0)}', cx, cy + 20, size: 12, color: const Color(0xFF7CFC9A));
      }
    }
  }

  void _paintLighting(Canvas c) {
    final W = engine.worldWidth, H = engine.worldHeight;
    final d = engine.nightDarkness;
    // day: gentle muted tint to keep the moody look
    _p.color = Color.fromRGBO(18, 22, 34, 0.14 + 0.5 * d);
    c.drawRect(Rect.fromLTWH(0, 0, W, H), _p);
    if (d > 0.02) {
      _p.color = Color.fromRGBO(8, 12, 40, 0.20 * d);
      c.drawRect(Rect.fromLTWH(0, 0, W, H), _p);
    }
    // wall lamps (always visible) + stepped glow
    final glowStrength = 0.10 + 0.55 * d;
    for (final lx in [400.0, 800.0, 1200.0, 1600.0]) {
      _r(c, _snap(lx), 236, 0, 0, 3, 3, const Color(0xFFFFE9A0));
      for (final step in const [[230.0, 0.30], [160.0, 0.45], [95.0, 0.7]]) {
        final rad = step[0];
        _p.color = Color.fromRGBO(255, 214, 140, 0.07 * glowStrength * step[1] * 3.2);
        _p.blendMode = BlendMode.plus;
        c.drawOval(Rect.fromCenter(center: Offset(lx, 330), width: rad * 2, height: rad * 1.5), _p);
        _p.blendMode = BlendMode.srcOver;
      }
    }
    if (d > 0.02) {
      // lantern around the player
      for (final step in const [[150.0, 0.18], [100.0, 0.28], [58.0, 0.4]]) {
        _p.color = Color.fromRGBO(255, 224, 170, step[1] * d * 0.45);
        _p.blendMode = BlendMode.plus;
        c.drawOval(Rect.fromCenter(center: Offset(_snap(engine.playerX), _snap(engine.playerY)), width: step[0] * 2, height: step[0] * 1.6), _p);
        _p.blendMode = BlendMode.srcOver;
      }
    }
  }

  void _paintMouseTarget(Canvas c) {
    if (engine.targetMoveX == null || engine.targetMoveY == null) return;
    final tx = _snap(engine.targetMoveX!);
    final ty = _snap(engine.targetMoveY!);
    final pulse = (sin(engine.worldTime * 8) * 0.5 + 0.5).round();
    final o = (3 + pulse) * kPx;
    _p.color = const Color(0xCCFFE066);
    for (final d in [Offset(-o, 0), Offset(o, 0), Offset(0, -o), Offset(0, o)]) {
      c.drawRect(Rect.fromLTWH(tx + d.dx - kPx / 2, ty + d.dy - kPx / 2, kPx, kPx), _p);
    }
  }

  /// Pulsing yellow frame + bouncing arrow over boxes waiting at the back door.
  void _paintDeliveryMarker(Canvas c) {
    if (engine.deliveryBoxes.isEmpty) return;
    double minX = 1e9, maxX = -1e9, minY = 1e9;
    for (final b in engine.deliveryBoxes) {
      minX = min(minX, b.x);
      maxX = max(maxX, b.x);
      minY = min(minY, b.y);
    }
    final pulse = (sin(engine.worldTime * 6) + 1) / 2;
    _p.style = PaintingStyle.stroke;
    _p.strokeWidth = kPx;
    _p.color = Color.fromARGB((120 + 110 * pulse).toInt(), 255, 214, 64);
    c.drawRect(Rect.fromLTRB(_snap(minX - 34), _snap(minY - 30), _snap(maxX + 34), _snap(engine.deliveryBoxes.map((b) => b.y).reduce(max) + 24)), _p);
    _p.style = PaintingStyle.fill;
    final cx = _snap((minX + maxX) / 2);
    final by = _snap(minY - 62 - 6 * pulse);
    _p.color = Pal.outline;
    c.drawRect(Rect.fromLTWH(cx - 3 * kPx, by - kPx, 6 * kPx, 5 * kPx), _p);
    c.drawRect(Rect.fromLTWH(cx - 5 * kPx, by + 3 * kPx, 10 * kPx, 3 * kPx), _p);
    _p.color = const Color(0xFFFFD640);
    c.drawRect(Rect.fromLTWH(cx - 2 * kPx, by, 4 * kPx, 4 * kPx), _p);
    c.drawRect(Rect.fromLTWH(cx - 4 * kPx, by + 4 * kPx, 8 * kPx, 2 * kPx), _p);
    _text(c, 'DELIVERY', cx, by - 14, size: 12, color: const Color(0xFFFFD640), plate: true);
  }

  void _paintParticles(Canvas c) {
    for (final p in engine.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0).toDouble();
      final col = p.color.withValues(alpha: min(1.0, a * 1.6));
      _text(c, p.text, _snap(p.x), _snap(p.y), size: max(9.0, p.size * 0.75), color: col);
    }
  }
}
