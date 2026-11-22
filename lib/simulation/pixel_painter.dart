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
  static double? _staticWorldH;
  static final Map<String, TextPainter> _textCache = {};
  final Paint _p = Paint()..isAntiAlias = false;

  // ---------------------------------------------------------------------------
  // low level helpers
  // ---------------------------------------------------------------------------
  // Characters move in 1-unit steps (a 3-unit grid made them judder at 60 fps).
  double _snap(double v) => v.roundToDouble();

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
      {double size = 10, Color color = Colors.white, bool bold = true, bool? plate}) {
    final clean = _clean(text);
    if (clean.isEmpty) return;
    // Tiny text turns digits like 2/3/8 into blobs, so keep a readable minimum
    // and put every label that holds numbers on a dark plate.
    if (size < 13) size = 13;
    final bool usePlate = plate ?? RegExp(r'[0-9]').hasMatch(clean);
    final tp = _tp(clean, size, color, bold);
    final dx = x - tp.width / 2;
    final dy = y - tp.height / 2;
    if (usePlate) {
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
    // Snap the camera to whole device pixels: crisp pixels, but no stepping.
    final camX = (cam.dx * scale).roundToDouble() / scale;
    final camY = (cam.dy * scale).roundToDouble() / scale;

    canvas.save();
    canvas.scale(scale);
    canvas.translate(-camX, -camY);
    canvas.clipRect(Rect.fromLTWH(0, 0, engine.worldWidth, engine.worldHeight));

    if (_staticPicture == null || _staticWorldH != engine.worldHeight) {
      final rec = ui.PictureRecorder();
      _paintStaticWorld(Canvas(rec));
      _staticPicture = rec.endRecording();
      _staticWorldH = engine.worldHeight;
    }
    canvas.drawPicture(_staticPicture!);

    _paintFarms(canvas);
    _paintSlidingDoors(canvas);
    _paintAlley(canvas);
    _paintCourierZone(canvas);
    _paintSorted(canvas);
    _paintFlyingItems(canvas);
    _paintLighting(canvas);
    _paintLockedExpansion(canvas);
    _paintLockedFloorPlates(canvas);
    _paintMouseTarget(canvas);
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

    // Backyard Farm Valley (y: 1010..H) — yol kaldırıldı, doğrudan doğal çimenlik tarla alanı
    final farmTop = floorBottom + 20;
    if (H > farmTop) {
      _wr(c, Rect.fromLTWH(0, farmTop, W, H - farmTop), const Color(0xFF1E562B));
      for (double y = farmTop; y < H; y += 24) {
        for (double x = 0; x < W; x += 36) {
          final h = _hash((x ~/ 36), (y ~/ 24));
          if (h % 3 == 0) {
            _wr(c, Rect.fromLTWH(x, y, 36, 24), const Color(0xFF236331));
          } else if (h % 5 == 0) {
            _wr(c, Rect.fromLTWH(x, y, 36, 24), const Color(0xFF194B24));
          }
          if (h % 7 == 0) {
            _r(c, x + 12, y + 9, 0, 0, 2, 3, const Color(0xFF3FA13A));
            _r(c, x + 18, y + 6, 0, 0, 2, 4, const Color(0xFF3FA13A));
          }
          if (h % 13 == 0) {
            _r(c, x + 21, y + 12, 0, 0, 2, 2, const Color(0xFFF2CF4A));
          }
        }
      }
    }
  }

  /// Giriş kapısı (ve arka kapı) için yaklaşınca iki yana kayarak açılan otomatik sürgülü cam kapı.
  void _paintSlidingDoors(Canvas c) {
    final doorCenter = engine.worldWidth / 2;
    _drawSingleSlidingDoor(
      c,
      centerX: doorCenter,
      topY: 204,
      doorH: 48,
      halfGap: 138,
      sensorY: 228,
    );
    _drawSingleSlidingDoor(
      c,
      centerX: doorCenter,
      topY: 990,
      doorH: 20,
      halfGap: 138,
      sensorY: 998,
    );
  }

  void _drawSingleSlidingDoor(
    Canvas c, {
    required double centerX,
    required double topY,
    required double doorH,
    required double halfGap,
    required double sensorY,
  }) {
    double minDist = 9999.0;
    void checkActor(double ax, double ay) {
      final dx = (ax - centerX).abs();
      final dy = (ay - sensorY).abs();
      if (dx < halfGap + 45 && dy < 115) {
        final d = max(0.0, dx - 30) * 0.45 + dy;
        if (d < minDist) minDist = d;
      }
    }

    checkActor(engine.playerX, engine.playerY);
    for (final cu in engine.customers) {
      checkActor(cu.x, cu.y);
    }
    if (engine.hasRestocker && engine.isRestockerHired && !engine.restockerAtHome) {
      checkActor(engine.restocker.x, engine.restocker.y);
    }
    for (final t in engine.thieves) {
      checkActor(t.x, t.y);
    }

    final openT = ((110.0 - minDist) / 65.0).clamp(0.0, 1.0);
    final isOpen = openT > 0.05;
    final panelW = halfGap - 3;
    final slideDist = openT * (panelW - 18);

    // Üst sensör rayı ve durum ışığı
    final railRect = Rect.fromCenter(center: Offset(centerX, topY - 3), width: halfGap * 2 + 12, height: 6);
    _wr(c, railRect, Pal.outline);
    _wr(c, railRect.deflate(1.5), const Color(0xFF37474F));
    _wr(
      c,
      Rect.fromCenter(center: Offset(centerX, topY - 3), width: 12, height: 4),
      isOpen ? const Color(0xFF4ADE80) : const Color(0xFF38BDF8),
    );

    // Sol ve Sağ sürgülü cam kapı kanatları
    c.save();
    c.clipRect(Rect.fromLTWH(centerX - halfGap, topY, halfGap * 2, doorH));
    for (final side in [-1.0, 1.0]) {
      final left = side < 0
          ? (centerX - panelW - slideDist)
          : (centerX + slideDist);
      final panelRect = Rect.fromLTWH(_snap(left), _snap(topY), _snap(panelW), _snap(doorH));

      // Dış metal/ahşap çerçeve
      _wr(c, panelRect, Pal.outline);
      _wr(c, panelRect.deflate(kPx), const Color(0xFF607D8B));
      // Yarı saydam sürgülü cam yüzeyi
      final glassRect = panelRect.deflate(2 * kPx);
      _wr(c, glassRect, const Color(0xAA2C4A52));
      _wr(
        c,
        Rect.fromLTWH(glassRect.left, glassRect.top, glassRect.width, max(kPx, glassRect.height * 0.25)),
        const Color(0xAA4D7C85),
      );
      // Cam parlama şeritleri
      if (glassRect.width > 24) {
        _wr(
          c,
          Rect.fromLTWH(glassRect.left + 12, glassRect.top + 3, 6, max(kPx, glassRect.height - 6)),
          const Color(0x44FFFFFF),
        );
        _wr(
          c,
          Rect.fromLTWH(glassRect.left + 24, glassRect.top + 3, 3, max(kPx, glassRect.height - 6)),
          const Color(0x28FFFFFF),
        );
      }
      // Kapı kolu (orta birleşim kenarında)
      final handleX = side < 0 ? (panelRect.right - 3 * kPx) : (panelRect.left + 2 * kPx);
      final handleH = max(2 * kPx, (doorH * 0.42));
      final handleY = panelRect.top + (doorH - handleH) / 2;
      _wr(c, Rect.fromLTWH(handleX - 1, handleY - 1, kPx + 2, handleH + 2), Pal.outline);
      _wr(c, Rect.fromLTWH(handleX, handleY, kPx, handleH), const Color(0xFFF2CF4A));
    }
    c.restore();
  }

  // ---------------------------------------------------------------------------
  // backyard farms: İnek Çiftliği, Un Tarlası, Tavuk Çiftliği + 3 Kilitli Tarla (Domates, Biber, Elma)
  // ---------------------------------------------------------------------------
  void _paintFarms(Canvas c) {
    for (final farm in engine.farmProducers) {
      if (!farm.isUnlocked) {
        _drawLockedFarmPlot(c, farm);
        continue;
      }
      if (farm.zoneType == FarmZoneType.barn) {
        _drawCowFarm(c, farm);
      } else if (farm.zoneType == FarmZoneType.field) {
        _drawFlourField(c, farm);
      } else if (farm.zoneType == FarmZoneType.coop) {
        _drawChickenFarm(c, farm);
      }
      _drawToolStand(c, farm);
    }
  }

  /// Draws a crisp pixel-art padlock icon (7x8 art pixels) at (wx, wy).
  void _drawPixelLock(Canvas c, double wx, double wy, {bool unlocked = false}) {
    final x = _snap(wx);
    final y = _snap(wy);
    // Shackle
    _r(c, x, y, 1, 0, 5, 4, Pal.outline);
    _r(c, x, y, 2, 1, 3, 2, const Color(0xFFB0BEC5));
    _r(c, x, y, 3, 2, 1, 2, Pal.outline);
    // Body
    _r(c, x, y, 0, 3, 7, 6, Pal.outline);
    _r(c, x, y, 1, 4, 5, 4, unlocked ? const Color(0xFF4ADE80) : const Color(0xFFF2CF4A));
    _r(c, x, y, 1, 4, 5, 1, unlocked ? const Color(0xFF86EFAC) : const Color(0xFFFFE98A));
    // Keyhole
    _r(c, x, y, 3, 5, 1, 2, Pal.outline);
  }

  /// Kilitli tarla: kilit işareti + ürün ikonu + tarla/ürün adı
  void _drawLockedFarmPlot(Canvas c, FarmProducer farm) {
    final r = farm.rect;
    final def = productCatalog[farm.primaryProduct]!;
    final shelf = engine.shelfForProduct(farm.primaryProduct);
    final canOpenNow = shelf != null && engine.storeLevel >= shelf.zoneLevel;

    // Subtle staked plot border on the grass
    _p.color = farm.isHovered
        ? const Color(0xFFFFE066)
        : (canOpenNow ? const Color(0x994ADE80) : const Color(0x668A6A3C));
    _p.style = PaintingStyle.stroke;
    _p.strokeWidth = kPx;
    c.drawRect(Rect.fromLTWH(_snap(r.left), _snap(r.top), _snap(r.width), _snap(r.height)), _p);
    _p.style = PaintingStyle.fill;

    // Corner wooden stakes
    for (final pt in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      _wr(c, Rect.fromCenter(center: pt, width: 12, height: 12), Pal.outline);
      _wr(c, Rect.fromCenter(center: pt, width: 6, height: 6), Pal.woodLight);
    }

    // Center sign board with Lock Icon + Product Icon + Product/Field Name
    final cx = _snap(r.center.dx);
    final cy = _snap(r.center.dy);
    final signRect = Rect.fromCenter(center: Offset(cx, cy), width: 264, height: 64);
    _wr(c, signRect.inflate(3), Pal.outline);
    _wr(c, signRect, const Color(0xFF1F1813));
    _wr(
      c,
      Rect.fromLTWH(signRect.left, signRect.top, signRect.width, 4),
      canOpenNow ? const Color(0xFF4ADE80) : const Color(0xFFF2CF4A),
    );

    // Pixel lock icon + product icon on the left side of the title
    _drawPixelLock(c, cx - 114, cy - 22, unlocked: canOpenNow);
    _icon(c, farm.primaryProduct, cx - 88, cy - 19);

    _text(
      c,
      '${farm.name} (${def.name})',
      cx + 16,
      cy - 10,
      size: 13,
      color: const Color(0xFFFDE68A),
      plate: false,
    );

    final subText = shelf != null ? engine.shelfLockReason(shelf) : 'Kilitli';
    _text(
      c,
      subText,
      cx,
      cy + 14,
      size: 12,
      color: canOpenNow ? const Color(0xFF7CFC9A) : const Color(0xFFCFD8DC),
      plate: false,
    );
  }

  void _drawPixelFence(Canvas c, Rect r, double gateMinX, double gateMaxX) {
    // Top rail (with open gate gap)
    _wr(c, Rect.fromLTRB(r.left, r.top - 3, gateMinX, r.top + 6), Pal.outline);
    _wr(c, Rect.fromLTRB(r.left + 3, r.top, gateMinX - 3, r.top + 3), Pal.wood);
    _wr(c, Rect.fromLTRB(gateMaxX, r.top - 3, r.right, r.top + 6), Pal.outline);
    _wr(c, Rect.fromLTRB(gateMaxX + 3, r.top, r.right - 3, r.top + 3), Pal.wood);

    // Bottom, left, right rails
    _wr(c, Rect.fromLTRB(r.left, r.bottom - 6, r.right, r.bottom + 3), Pal.outline);
    _wr(c, Rect.fromLTRB(r.left + 3, r.bottom - 3, r.right - 3, r.bottom), Pal.wood);
    _wr(c, Rect.fromLTRB(r.left - 3, r.top, r.left + 6, r.bottom), Pal.outline);
    _wr(c, Rect.fromLTRB(r.left, r.top + 3, r.left + 3, r.bottom - 3), Pal.woodDark);
    _wr(c, Rect.fromLTRB(r.right - 6, r.top, r.right + 3, r.bottom), Pal.outline);
    _wr(c, Rect.fromLTRB(r.right - 3, r.top + 3, r.right, r.bottom - 3), Pal.woodDark);

    // Fence posts
    for (double px = r.left; px <= r.right; px += 44) {
      if (px < gateMinX - 6 || px > gateMaxX + 6) {
        _wr(c, Rect.fromCenter(center: Offset(px, r.top), width: 12, height: 15), Pal.outline);
        _wr(c, Rect.fromCenter(center: Offset(px, r.top), width: 6, height: 9), Pal.woodLight);
      }
      _wr(c, Rect.fromCenter(center: Offset(px, r.bottom), width: 12, height: 15), Pal.outline);
      _wr(c, Rect.fromCenter(center: Offset(px, r.bottom), width: 6, height: 9), Pal.woodLight);
    }

    // Gate pillars
    for (final gx in [gateMinX, gateMaxX]) {
      _wr(c, Rect.fromCenter(center: Offset(gx, r.top), width: 15, height: 18), Pal.outline);
      _wr(c, Rect.fromCenter(center: Offset(gx, r.top), width: 9, height: 12), const Color(0xFFD9A441));
    }
  }

  void _drawToolStand(Canvas c, FarmProducer farm) {
    final pos = farm.toolStandPos;
    final x = _snap(pos.dx - 30);
    final y = _snap(pos.dy - 14);
    final isEquipped = engine.playerTool == farm.requiredTool;

    // Shadow & wooden table
    _r(c, x, y, 1, 9, 20, 3, Pal.shadow);
    _r(c, x, y, -1, -1, 22, 11, Pal.outline);
    _r(c, x, y, 0, 0, 20, 9, Pal.wood);
    _r(c, x, y, 0, 0, 20, 2, Pal.woodLight);
    _r(c, x, y, 0, 7, 20, 2, Pal.woodDark);

    // Tool icon(s) resting on the stand
    if (farm.requiredTool == FarmToolType.milkBucket) {
      _drawPixelMilkBucket(c, pos.dx - 11, pos.dy - 4, hasMilk: false);
      _drawPixelMilkBucket(c, pos.dx + 11, pos.dy - 4, hasMilk: true);
    } else if (farm.requiredTool == FarmToolType.scythe) {
      _drawPixelHoeIcon(c, pos.dx - 8, pos.dy - 2);
      _drawPixelHoeIcon(c, pos.dx + 10, pos.dy - 2);
    } else {
      _drawPixelEggBucket(c, pos.dx - 11, pos.dy - 4, hasEggs: false);
      _drawPixelEggBucket(c, pos.dx + 11, pos.dy - 4, hasEggs: true);
    }

    if (farm.isToolStandHovered || isEquipped) {
      _p.color = isEquipped ? const Color(0xFF4ADE80) : const Color(0xFFFDE68A);
      _p.style = PaintingStyle.stroke;
      _p.strokeWidth = kPx;
      c.drawRect(Rect.fromLTWH(x - 2 * kPx, y - 2 * kPx, 24 * kPx, 13 * kPx), _p);
      _p.style = PaintingStyle.fill;
    }

    final label = isEquipped ? 'Elde: ${farm.requiredTool.name}' : '${farm.requiredTool.name} Al';
    _text(
      c,
      label,
      pos.dx,
      pos.dy - 28,
      size: 11,
      color: isEquipped ? const Color(0xFF7CFC9A) : const Color(0xFFFDE68A),
      plate: true,
    );
  }

  void _drawCowFarm(Canvas c, FarmProducer farm) {
    final r = farm.rect;
    // Pasture grass
    _wr(c, r, const Color(0xFF287238));
    for (double y = r.top + 12; y < r.bottom - 18; y += 24) {
      for (double x = r.left + 12; x < r.right - 24; x += 36) {
        if (_hash(x ~/ 18, y ~/ 18) % 3 == 0) {
          _wr(c, Rect.fromLTWH(x, y, 24, 15), const Color(0xFF2E8040));
        }
      }
    }

    // Water trough in center & hay bales on top-right
    final tx = _snap(r.center.dx - 27), ty = _snap(r.top + 125);
    _r(c, tx, ty, -1, -1, 20, 10, Pal.outline);
    _r(c, tx, ty, 0, 0, 18, 8, const Color(0xFF546E7A));
    _r(c, tx, ty, 2, 2, 14, 4, const Color(0xFF4FC3F7));

    for (final hx in [r.right - 72, r.right - 38]) {
      final bx = _snap(hx), by = _snap(r.top + 36);
      _r(c, bx, by, -1, -1, 11, 8, Pal.outline);
      _r(c, bx, by, 0, 0, 9, 6, const Color(0xFFE2B03B));
      _r(c, bx, by, 0, 0, 9, 2, const Color(0xFFF5D061));
      _r(c, bx, by, 2, 0, 1, 6, const Color(0xFF8A5A22));
      _r(c, bx, by, 6, 0, 1, 6, const Color(0xFF8A5A22));
    }

    _drawPixelFence(c, r, farm.gateMinX, farm.gateMaxX);

    // 4 Cows
    for (int i = 0; i < farm.spots.length; i++) {
      final spot = farm.spots[i];
      final phase = engine.worldTime * 2.0 + i * 1.7;
      final ox = _snap(spot.x + sin(phase) * 4);
      final oy = _snap(spot.y + cos(phase * 0.7) * 2);
      _drawPixelCow(c, ox, oy, spot);
      _drawSpotBadge(c, spot, 'Süt Sağ', const Color(0xFF5DADE2));
    }

    _text(
      c,
      'İNEK ÇİFTLİĞİ (Süt Kovası)  ${farm.readySpotCount}/${farm.spots.length}',
      r.left + 150,
      r.top - 14,
      size: 12,
      color: const Color(0xFF9AD7FF),
      plate: true,
    );
  }

  void _drawPixelCow(Canvas c, double wx, double wy, FarmHarvestSpot spot) {
    final x = _snap(wx);
    final y = _snap(wy);
    final graze = (sin(engine.worldTime * 3 + spot.index) > 0.3) ? 1 : 0;
    // Shadow
    _r(c, x, y, -7, 4, 15, 3, Pal.shadow);
    // Legs
    for (final lx in [-5, -2, 2, 5]) {
      _r(c, x, y, lx, 2, 2, 4, Pal.outline);
      _r(c, x, y, lx, 2, 1.5, 3, const Color(0xFFECEFF1));
    }
    // Pink udder
    if (spot.isReady) {
      _r(c, x, y, -1, 2, 3, 2, const Color(0xFFF48FB1));
    }
    // Body
    _r(c, x, y, -7, -5, 14, 8, Pal.outline);
    _r(c, x, y, -6, -4, 12, 6, const Color(0xFFF5F7F8));
    // Black spots
    _r(c, x, y, -4, -4, 4, 3, const Color(0xFF1C242B));
    _r(c, x, y, 1, -2, 3, 3, const Color(0xFF1C242B));
    // Head + horns + pink snout
    final hy = -6 + graze;
    _r(c, x, y, 5, hy - 1, 7, 7, Pal.outline);
    _r(c, x, y, 6, hy, 5, 5, const Color(0xFFF5F7F8));
    _r(c, x, y, 6, hy - 2, 1, 2, const Color(0xFFE6C88A));
    _r(c, x, y, 9, hy - 2, 1, 2, const Color(0xFFE6C88A));
    _r(c, x, y, 8, hy + 1, 1, 1, const Color(0xFF14100E)); // eye
    _r(c, x, y, 9, hy + 3, 3, 2, const Color(0xFFF48FB1)); // snout
  }

  void _drawFlourField(Canvas c, FarmProducer farm) {
    final r = farm.rect;
    final isOrchard = farm.primaryProduct == SimProductType.apple;
    final hasMill = !farm.solidBuildingRect.isEmpty;

    // Plowed soil (or orchard green-soil for Elma Tarlası)
    _wr(c, r, isOrchard ? const Color(0xFF235D2A) : const Color(0xFF4E301B));
    final furrowLeft = hasMill ? r.left + 120 : r.left + 20;
    for (double fy = r.top + 28; fy < r.bottom - 20; fy += 24) {
      _wr(
        c,
        Rect.fromLTRB(furrowLeft, fy, r.right - 18, fy + 9),
        isOrchard ? const Color(0xFF1B4B20) : const Color(0xFF3B2212),
      );
      _wr(
        c,
        Rect.fromLTRB(furrowLeft, fy - 3, r.right - 18, fy),
        isOrchard ? const Color(0xFF2E7336) : const Color(0xFF664026),
      );
    }

    _drawPixelFence(c, r, farm.gateMinX, farm.gateMaxX);

    // Windmill / Mill building on the left inside the Flour Field
    final mr = farm.solidBuildingRect;
    if (!mr.isEmpty) {
      final mx = _snap(mr.left), my = _snap(mr.top);
      final gw = (mr.width / kPx).round(), gh = (mr.height / kPx).round();
      _r(c, mx, my, 1, gh - 1, gw, 3, Pal.shadow);
      _r(c, mx, my, -1, -1, gw + 2, gh + 2, Pal.outline);
      _r(c, mx, my, 0, 0, gw, gh, const Color(0xFF8D867A));
      _r(c, mx, my, 2, 2, gw - 4, gh - 4, const Color(0xFFA8A092));
      // Roof
      _r(c, mx, my, -2, -4, gw + 4, 7, Pal.outline);
      _r(c, mx, my, -1, -3, gw + 2, 5, const Color(0xFF9A4422));
      // Door
      _r(c, mx, my, (gw ~/ 2) - 4, gh - 10, 8, 10, Pal.outline);
      _r(c, mx, my, (gw ~/ 2) - 3, gh - 9, 6, 9, Pal.woodDark);
      // Rotating pixel windmill blades
      final hubX = mr.center.dx;
      final hubY = mr.top + 22;
      final ang = engine.worldTime * 1.6;
      for (int b = 0; b < 4; b++) {
        final a = ang + b * (pi / 2);
        for (int k = 2; k <= 12; k++) {
          final bx = _snap(hubX + cos(a) * k * kPx);
          final by = _snap(hubY + sin(a) * k * kPx);
          _r(c, bx, by, 0, 0, 2, 2, k > 4 ? const Color(0xFFF5E6C4) : Pal.woodDark);
        }
      }
      _r(c, _snap(hubX), _snap(hubY), -1, -1, 3, 3, const Color(0xFFD9A441));
    }

    // Crop / orchard spots
    for (final spot in farm.spots) {
      _drawPixelWheatSpot(c, spot);
      _drawSpotBadge(c, spot, 'Çapa Vur', const Color(0xFFF2CF4A));
    }

    _text(
      c,
      '${farm.name.toUpperCase()} (Çapa)  ${farm.readySpotCount}/${farm.spots.length}',
      r.left + 145,
      r.top - 14,
      size: 12,
      color: const Color(0xFFFDE68A),
      plate: true,
    );
  }

  void _drawPixelWheatSpot(Canvas c, FarmHarvestSpot spot) {
    final x = _snap(spot.x);
    final y = _snap(spot.y);
    final growth = spot.isReady ? 1.0 : (spot.regrowTimer / spot.regrowDuration).clamp(0.15, 0.95);
    final sway = (sin(engine.worldTime * 3.5 + spot.index) * 1.5).round();

    for (final dx in [-7, -2, 3, 8]) {
      for (final dy in [-4, 3]) {
        if (!spot.isReady) {
          final h = (2 + 4 * growth).round();
          _r(c, x, y, dx, dy + 2 - h, 2, h, const Color(0xFF4CAF50));
          continue;
        }
        if (spot.productType == SimProductType.tomato) {
          // 🍅 Domates fidesi
          _r(c, x, y, dx - 1, dy - 6, 4, 5, Pal.outline);
          _r(c, x, y, dx, dy - 5, 3, 4, const Color(0xFF2E7D32));
          _r(c, x, y, dx + sway, dy - 4, 2, 2, const Color(0xFFE53935));
        } else if (spot.productType == SimProductType.pepper) {
          // 🌶️ Biber fidesi
          _r(c, x, y, dx - 1, dy - 6, 4, 5, Pal.outline);
          _r(c, x, y, dx, dy - 5, 3, 4, const Color(0xFF1B5E20));
          _r(c, x, y, dx + sway, dy - 4, 1.5, 3, const Color(0xFF66BB6A));
        } else if (spot.productType == SimProductType.apple) {
          // 🍎 Bodur Elma Ağacı ve Kırmızı Elmalar
          _r(c, x, y, dx, dy - 3, 2, 4, Pal.woodDark);
          _r(c, x, y, dx - 2, dy - 8, 6, 6, Pal.outline);
          _r(c, x, y, dx - 1, dy - 7, 4, 4, const Color(0xFF2E7D32));
          _r(c, x, y, dx + sway, dy - 6, 2, 2, const Color(0xFFD32F2F));
        } else {
          // 🌾 Altın Buğday / Un Başakları
          _r(c, x, y, dx, dy - 4, 2, 6, const Color(0xFFB8861E));
          _r(c, x, y, dx + sway, dy - 8, 3, 5, Pal.outline);
          _r(c, x, y, dx + sway, dy - 7, 2, 4, const Color(0xFFF2CF4A));
        }
      }
    }
  }

  void _drawChickenFarm(Canvas c, FarmProducer farm) {
    final r = farm.rect;
    // Warm sandy / straw coop yard
    _wr(c, r, const Color(0xFF7D5A2A));
    for (double y = r.top + 12; y < r.bottom - 18; y += 24) {
      for (double x = r.left + 12; x < r.right - 24; x += 36) {
        if (_hash(x ~/ 18, y ~/ 18) % 2 == 0) {
          _wr(c, Rect.fromLTWH(x, y, 21, 12), const Color(0xFF8E6732));
        }
      }
    }

    _drawPixelFence(c, r, farm.gateMinX, farm.gateMaxX);

    // Wooden Chicken Coop house on the right
    final cr = farm.solidBuildingRect;
    if (!cr.isEmpty) {
      final cx = _snap(cr.left), cy = _snap(cr.top);
      final gw = (cr.width / kPx).round(), gh = (cr.height / kPx).round();
      _r(c, cx, cy, 1, gh - 1, gw, 3, Pal.shadow);
      _r(c, cx, cy, -1, -1, gw + 2, gh + 2, Pal.outline);
      _r(c, cx, cy, 0, 0, gw, gh, Pal.wood);
      _r(c, cx, cy, 0, 0, gw, 5, const Color(0xFFA93226)); // Red coop roof
      _r(c, cx, cy, 0, 5, gw, 2, const Color(0xFF7B241C));
      // Coop ramp on the left wall
      _r(c, cx, cy, -10, gh ~/ 2 - 4, 10, 8, Pal.outline);
      _r(c, cx, cy, -9, gh ~/ 2 - 3, 9, 6, Pal.woodLight);
      _r(c, cx, cy, 0, gh ~/ 2 - 5, 4, 9, const Color(0xFF1A1411));
    }

    // 4 Nests & Chickens
    for (int i = 0; i < farm.spots.length; i++) {
      final spot = farm.spots[i];
      _drawPixelChickenSpot(c, spot, i);
      _drawSpotBadge(c, spot, 'Yumurta Al', const Color(0xFFFFB74D));
    }

    _text(
      c,
      'TAVUK ÇİFTLİĞİ (Tavuk Kovası)  ${farm.readySpotCount}/${farm.spots.length}',
      r.right - 155,
      r.top - 14,
      size: 12,
      color: const Color(0xFFFFE082),
      plate: true,
    );
  }

  void _drawPixelChickenSpot(Canvas c, FarmHarvestSpot spot, int index) {
    final x = _snap(spot.x);
    final y = _snap(spot.y);

    // Straw nest
    _r(c, x, y, -5, -2, 10, 6, Pal.outline);
    _r(c, x, y, -4, -1, 8, 4, const Color(0xFFD9A441));
    _r(c, x, y, -3, 0, 6, 2, const Color(0xFFF5D061));

    // Eggs in nest
    final ratio = spot.isReady ? 1.0 : (spot.regrowTimer / spot.regrowDuration).clamp(0.0, 1.0);
    final eggCount = spot.isReady ? 3 : (ratio * 3).floor();
    const offs = [-3, 0, 2];
    for (int e = 0; e < eggCount; e++) {
      _r(c, x, y, offs[e], -3, 2, 3, Pal.outline);
      _r(c, x, y, offs[e], -2, 1.5, 2, const Color(0xFFFFF8E1));
    }

    // Animated pixel chicken next to the nest
    final phase = engine.worldTime * 4.0 + index * 2.1;
    final hx = _snap(spot.x - 22 + cos(phase * 0.6) * 5);
    final hy = _snap(spot.y - 6 + sin(phase) * 2);
    final peck = sin(engine.worldTime * 7 + index) > 0.4 ? 1 : 0;
    _r(c, hx, hy, -3, 3, 7, 2, Pal.shadow);
    _r(c, hx, hy, -4, -3, 8, 6, Pal.outline);
    _r(c, hx, hy, -3, -2, 6, 4, const Color(0xFFFDFEFE)); // White body
    _r(c, hx, hy, 1, -5 + peck, 4, 4, Pal.outline);
    _r(c, hx, hy, 2, -4 + peck, 3, 3, const Color(0xFFFDFEFE)); // Head
    _r(c, hx, hy, 2, -6 + peck, 2, 2, const Color(0xFFD33A2C)); // Red comb
    _r(c, hx, hy, 5, -3 + peck, 2, 1, const Color(0xFFF39C12)); // Beak
    _r(c, hx, hy, 3, -3 + peck, 1, 1, Pal.outline); // Eye
  }

  void _drawSpotBadge(Canvas c, FarmHarvestSpot spot, String readyText, Color col) {
    final bx = _snap(spot.x);
    final by = _snap(spot.y - 34);
    if (spot.harvestProgress > 0.01) {
      final frac = spot.harvestProgress.clamp(0.0, 1.0);
      _r(c, bx - 9 * kPx, by, 0, 0, 18, 4, Pal.outline);
      _r(c, bx - 9 * kPx, by, 1, 1, 16, 2, const Color(0xFF263238));
      _r(c, bx - 9 * kPx, by, 1, 1, (16 * frac).round(), 2, const Color(0xFF4ADE80));
      _text(c, '%${(frac * 100).toInt()}', bx, by - 10, size: 11, color: const Color(0xFF7CFC9A), plate: true);
    } else if (spot.isReady) {
      _text(c, readyText, bx, by, size: 10, color: col, plate: true);
    } else {
      final frac = (spot.regrowTimer / spot.regrowDuration).clamp(0.0, 1.0);
      _r(c, bx - 7 * kPx, by, 0, 0, 14, 3, Pal.outline);
      _r(c, bx - 7 * kPx, by, 1, 1, (12 * frac).round(), 1, const Color(0xFFF2CF4A));
    }
  }

  void _paintAlley(Canvas c) {
    // Delivery truck driving along the front street
    if (!engine.isTruckArriving) return;
    final x = _snap(engine.truckX);
    const y = 92.0;
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
        add(r.top - 6, () {
          _drawPerson(c, r.center.dx - 14, r.top - 14, facing: 0, phase: 0,
              shirt: const Color(0xFF2F6E9E), pants: const Color(0xFF1E2430), hair: const Color(0xFF6B3F1E));
          _text(c, 'CASHIER', r.center.dx - 14, r.top - 14 - 31 * kPx, size: 12, color: const Color(0xFF9AD7FF), plate: true);
        });
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
    // Animated double cabinet doors (açılıp kapanan çift kanatlı reyon kapıları)
    _drawShelfDoors(c, s, x, y, gw, gh, isCooler);

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

  /// Draws animated double glass doors with handles on every unlocked shelf using `s.doorOpenProgress`.
  void _drawShelfDoors(Canvas c, StoreShelf s, double x, double y, int gw, int gh, bool isCooler) {
    final openT = s.doorOpenProgress.clamp(0.0, 1.0);
    final innerW = gw - 4;
    final innerH = gh - 6;
    final halfW = innerW / 2.0;

    final doorBorder = isCooler ? const Color(0xFF5B7A92) : const Color(0xFFB07A45);
    final doorGlass = isCooler ? const Color(0x2E80D8FF) : const Color(0x24FFE0B2);
    final handleCol = isCooler ? const Color(0xFFECEFF1) : const Color(0xFFF2CF4A);

    // As openT goes 0 -> 1, each door wing swings outward to its hinge side and foreshortens
    final closedFrac = (1.0 - openT * 0.72).clamp(0.28, 1.0);
    final wingW = max(3, (halfW * closedFrac).round());
    final swingOut = (openT * 4).round();
    final handleH = max(4, (innerH * 0.24).round());
    final handleY = 3 + ((innerH - handleH) ~/ 2);

    // Left door wing (hinged at left x + 2)
    final leftX = 2 - swingOut;
    _r(c, x, y, leftX, 3, wingW, innerH, doorGlass);
    _r(c, x, y, leftX, 3, wingW, 1, doorBorder);
    _r(c, x, y, leftX, 3 + innerH - 1, wingW, 1, doorBorder);
    _r(c, x, y, leftX, 3, 1, innerH, doorBorder);
    _r(c, x, y, leftX + wingW - 1, 3, 1, innerH, Pal.outline);
    // Left door glass reflection + handle
    if (wingW > 5) {
      _r(c, x, y, leftX + 2, 5, 1, innerH - 4, const Color(0x33FFFFFF));
    }
    final leftHandleX = leftX + max(1, wingW - 3);
    _r(c, x, y, leftHandleX - 0.5, handleY - 0.5, 2, handleH + 1, Pal.outline);
    _r(c, x, y, leftHandleX, handleY, 1, handleH, handleCol);

    // Right door wing (hinged at right x + gw - 2)
    final rightX = (gw - 2) - wingW + swingOut;
    _r(c, x, y, rightX, 3, wingW, innerH, doorGlass);
    _r(c, x, y, rightX, 3, wingW, 1, doorBorder);
    _r(c, x, y, rightX, 3 + innerH - 1, wingW, 1, doorBorder);
    _r(c, x, y, rightX + wingW - 1, 3, 1, innerH, doorBorder);
    _r(c, x, y, rightX, 3, 1, innerH, Pal.outline);
    // Right door glass reflection + handle
    if (wingW > 5) {
      _r(c, x, y, rightX + wingW - 3, 5, 1, innerH - 4, const Color(0x33FFFFFF));
    }
    final rightHandleX = rightX + 1;
    _r(c, x, y, rightHandleX - 0.5, handleY - 0.5, 2, handleH + 1, Pal.outline);
    _r(c, x, y, rightHandleX, handleY, 1, handleH, handleCol);
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
    _text(c, 'COURIER', x + 2 * kPx, y - 15 * kPx, size: 12, color: const Color(0xFFFFB3A8), plate: true);
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
    if (engine.playerTool != null) {
      _drawHeldTool(
        c,
        px,
        py,
        engine.playerFacing,
        engine.playerTool!,
        engine.playerActionAnimTimer,
        engine.activeHarvestSpot != null,
      );
      if (engine.carriedBox == null) {
        _text(c, engine.playerTool!.name, px, py - 92, size: 11, color: const Color(0xFFFDE68A), plate: true);
      }
    }
    if (engine.carriedBox != null) {
      final b = engine.carriedBox!;
      _drawCarriedLoad(c, px, py, b);
    }
    _drawStick(c, px, py);
  }

  /// Draws either a farm bucket (only while inside the farm) or a product box/sack once outside the farm.
  void _drawCarriedLoad(Canvas c, double px, double py, CarriedBox b, {bool showLabel = true}) {
    final bx = _snap(px) - 5 * kPx;
    final by = _snap(py) - 27 * kPx;
    final insideFarm = engine.farmProducers.any((f) => f.rect.inflate(10).contains(Offset(px, py)));
    if (insideFarm && b.isFromFarm && b.productType == SimProductType.milk) {
      // Çiftliğin içindeyken Süt Kovası
      _drawPixelMilkBucket(c, _snap(px), by + 4 * kPx, hasMilk: true);
      if (showLabel) {
        _text(c, 'Süt Kovası ${b.currentCount}/${b.maxCount}', px, py - 94, size: 11, color: const Color(0xFF9AD7FF), plate: true);
      }
      return;
    }
    if (insideFarm && b.isFromFarm && b.productType == SimProductType.egg) {
      // Çiftliğin içindeyken Tavuk Kovası
      _drawPixelEggBucket(c, _snap(px), by + 4 * kPx, hasEggs: true);
      if (showLabel) {
        _text(c, 'Tavuk Kovası ${b.currentCount}/${b.maxCount}', px, py - 94, size: 11, color: const Color(0xFFFFE082), plate: true);
      }
      return;
    }
    if (b.isFromFarm && b.productType == SimProductType.flour) {
      // Hasat edilen Un Çuvalı
      _r(c, bx, by, 0, 0, 10, 9, Pal.outline);
      _r(c, bx, by, 1, 1, 8, 7, const Color(0xFFE6D6B5));
      _r(c, bx, by, 2, 0, 6, 2, const Color(0xFFB89E6E));
      _r(c, bx, by, 2, 2, 6, 1, const Color(0xFF8A5220));
      _icon(c, SimProductType.flour, bx + 2.5 * kPx, by + 2.5 * kPx);
      if (showLabel) {
        _text(c, 'Un ${b.currentCount}/${b.maxCount}', px, py - 94, size: 11, color: const Color(0xFFFDE68A), plate: true);
      }
      return;
    }
    _r(c, bx, by, -1, 0, 12, 9, Pal.outline);
    _r(c, bx, by, 0, 1, 10, 7, b.isCourierPackage ? const Color(0xFFE8D6A0) : const Color(0xFFB98A55));
    _icon(c, b.productType, bx + 2.5 * kPx, by + 2 * kPx);
    if (showLabel) {
      _text(c, '${b.currentCount}/${b.maxCount}', px, py - 92, size: 9);
    }
  }

  /// Draws the equipped farm tool (Süt Kovası, Çapa, Tavuk Kovası) directly in the character's hand.
  void _drawHeldTool(
    Canvas c,
    double px,
    double py,
    int facing,
    FarmToolType tool,
    double animTimer,
    bool isHarvesting,
  ) {
    final dir = facing == 1 ? -1.0 : 1.0;
    final hx = _snap(px) + dir * 7 * kPx;
    final hy = _snap(py) - 2 * kPx;

    switch (tool) {
      case FarmToolType.scythe:
        // ⛏️ ÇAPA (Hoe for Flour Field / Un Tarlası)
        final swing = isHarvesting ? sin(animTimer * 1.3) * 4 * kPx : 0.0;
        final tipY = hy - 7 * kPx + swing;
        // Wooden handle from hand up/outward
        for (int i = 0; i < 7; i++) {
          final sx = hx + dir * (i * 0.9) * kPx;
          final sy = hy + (2 - i) * kPx + (swing * i / 7);
          _r(c, _snap(sx), _snap(sy), 0, 0, 2, 2, Pal.outline);
          _r(c, _snap(sx), _snap(sy), 0, 0, 1.5, 1.5, const Color(0xFF9B6A32));
        }
        // Angled steel hoe blade (Çapa demiri)
        final bx = _snap(hx + dir * 5.5 * kPx);
        final by = _snap(tipY);
        _r(c, bx, by, dir > 0 ? -1 : -3, 0, 5, 6, Pal.outline);
        _r(c, bx, by, dir > 0 ? 0 : -2, 1, 3, 4, const Color(0xFFB0BEC5));
        _r(c, bx, by, dir > 0 ? 1 : -2, 4, 2, 1, const Color(0xFFECEFF1));
        break;

      case FarmToolType.milkBucket:
        // 🪣 SÜT KOVASI (Milk Bucket held in hand)
        final bob = isHarvesting ? sin(animTimer * 1.2) * 1.5 * kPx : 0.0;
        _drawPixelMilkBucket(c, hx + dir * 2 * kPx, _snap(hy + 2 * kPx + bob), hasMilk: isHarvesting);
        break;

      case FarmToolType.eggBucket:
        // 🪣 TAVUK KOVASI (Chicken / Egg Bucket held in hand)
        final bob = isHarvesting ? sin(animTimer * 1.2) * 1.5 * kPx : 0.0;
        _drawPixelEggBucket(c, hx + dir * 2 * kPx, _snap(hy + 2 * kPx + bob), hasEggs: isHarvesting);
        break;
    }
  }

  void _drawPixelMilkBucket(Canvas c, double wx, double wy, {bool hasMilk = false}) {
    final x = _snap(wx);
    final y = _snap(wy);
    // Handle arch
    _r(c, x, y, -3, -5, 6, 1, const Color(0xFFCFD8DC));
    _r(c, x, y, -4, -4, 1, 2, const Color(0xFF90A4AE));
    _r(c, x, y, 3, -4, 1, 2, const Color(0xFF90A4AE));
    // Bucket body
    _r(c, x, y, -4, -3, 8, 7, Pal.outline);
    _r(c, x, y, -3, -2, 6, 5, const Color(0xFF2980B9));
    _r(c, x, y, -3, -2, 2, 5, const Color(0xFF5DADE2));
    // Top rim / milk inside
    _r(c, x, y, -3, -2, 6, 2, hasMilk ? const Color(0xFFFDFEFE) : const Color(0xFF1B4F72));
  }

  void _drawPixelEggBucket(Canvas c, double wx, double wy, {bool hasEggs = false}) {
    final x = _snap(wx);
    final y = _snap(wy);
    // Handle arch
    _r(c, x, y, -3, -5, 6, 1, const Color(0xFF8A5220));
    _r(c, x, y, -4, -4, 1, 2, const Color(0xFF6B4423));
    _r(c, x, y, 3, -4, 1, 2, const Color(0xFF6B4423));
    // Bucket body (warm golden chicken bucket with red chicken crest)
    _r(c, x, y, -4, -3, 8, 7, Pal.outline);
    _r(c, x, y, -3, -2, 6, 5, const Color(0xFFE69A28));
    _r(c, x, y, -3, -2, 2, 5, const Color(0xFFF5B945));
    _r(c, x, y, -1, 0, 2, 2, const Color(0xFFD33A2C)); // little chicken crest emblem
    if (hasEggs) {
      _r(c, x, y, -3, -3, 2, 2, const Color(0xFFFFF8E1));
      _r(c, x, y, 0, -3, 3, 2, const Color(0xFFF5E6C4));
    } else {
      _r(c, x, y, -3, -2, 6, 1, const Color(0xFF784212));
    }
  }

  void _drawPixelHoeIcon(Canvas c, double wx, double wy) {
    final x = _snap(wx);
    final y = _snap(wy);
    // Angled wooden handle + steel hoe head
    for (int i = -3; i <= 3; i++) {
      _r(c, x, y, i - 1, -i, 2, 2, Pal.outline);
      _r(c, x, y, i, -i, 1, 1, const Color(0xFF9B6A32));
    }
    _r(c, x, y, 2, -4, 5, 5, Pal.outline);
    _r(c, x, y, 3, -3, 3, 3, const Color(0xFFCFD8DC));
    _r(c, x, y, 4, -1, 2, 1, Colors.white);
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
    _text(c, 'STOCKER', _snap(w.x), _snap(w.y) - 31 * kPx - 4, size: 12, color: const Color(0xFFFFD27A), plate: true);
    if (w.equippedTool != null) {
      _drawHeldTool(c, w.x, w.y, 2, w.equippedTool!, w.actionAnimTimer, w.actionAnimTimer > 0);
    }
    if (w.carriedBox != null) {
      _drawCarriedLoad(c, w.x, w.y, w.carriedBox!, showLabel: false);
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
    // Reyonlar açılmadığı sürece raf çizilmez; sadece kilit işareti ve adları görünür!
    for (final s in engine.shelves) {
      if (s.isUnlocked) continue;
      final r = s.rect;
      final cx = _snap(r.center.dx);
      final cy = _snap(r.center.dy);
      final canOpenNow = engine.storeLevel >= s.zoneLevel;

      _drawPixelLock(c, cx - 86, cy - 14, unlocked: canOpenNow);
      _text(
        c,
        s.name,
        cx + 8,
        cy - 4,
        size: 13,
        color: s.isHovered ? Colors.white : const Color(0xFFFDE68A),
        plate: true,
      );
      _text(
        c,
        engine.shelfLockReason(s),
        cx,
        cy + 16,
        size: 11,
        color: canOpenNow ? const Color(0xFF7CFC9A) : const Color(0xFFCFD8DC),
        plate: true,
      );
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
      _wr(c, z, const Color(0xBF0B0F18));
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
      const cy = 415.0;
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
    final vis = c.getLocalClipBounds();
    for (final lx in [400.0, 800.0, 1200.0, 1600.0]) {
      if (lx + 240 < vis.left || lx - 240 > vis.right) continue; // lamp glow is off-screen
      _r(c, _snap(lx), 236, 0, 0, 3, 3, const Color(0xFFFFE9A0));
      for (final step in const [[210.0, 0.4], [110.0, 0.8]]) {
        final rad = step[0];
        _p.color = Color.fromRGBO(255, 214, 140, 0.07 * glowStrength * step[1] * 3.2);
        c.drawOval(Rect.fromCenter(center: Offset(lx, 330), width: rad * 2, height: rad * 1.5), _p);
      }
    }
    if (d > 0.02) {
      // lantern around the player
      for (final step in const [[130.0, 0.25], [64.0, 0.45]]) {
        _p.color = Color.fromRGBO(255, 224, 170, step[1] * d * 0.45);
        c.drawOval(Rect.fromCenter(center: Offset(_snap(engine.playerX), _snap(engine.playerY)), width: step[0] * 2, height: step[0] * 1.6), _p);
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

  void _paintParticles(Canvas c) {
    for (final p in engine.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0).toDouble();
      final col = p.color.withValues(alpha: min(1.0, a * 1.6));
      _text(c, p.text, _snap(p.x), _snap(p.y), size: max(9.0, p.size * 0.75), color: col);
    }
  }
}
