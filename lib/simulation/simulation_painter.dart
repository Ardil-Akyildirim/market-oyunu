import 'dart:math';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'simulation_engine.dart';
import 'simulation_models.dart';

class SimulationPainter extends CustomPainter {
  final SimulationEngine engine;

  // Performans Önbellekleri (Statik zemin/ışık Picture ve TextPainter cache)
  static ui.Picture? _cachedWorldPicture;
  static ui.Picture? _cachedLightingPicture;
  static final Map<String, TextPainter> _textCache = {};

  SimulationPainter({required this.engine}) : super(repaint: engine);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = engine.getEffectiveScale(size);
    final camTopLeft = engine.getCameraTopLeft(size);

    canvas.save();
    canvas.scale(scale);
    canvas.translate(-camTopLeft.dx, -camTopLeft.dy);
    canvas.clipRect(Rect.fromLTWH(0, 0, engine.worldWidth, engine.worldHeight));

    // 1. Devasa Dünya Zemini (Statik katman tek seferde GPU Picture olarak cache'lenir!)
    if (_cachedWorldPicture == null) {
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      _drawStaticWorldEnvironment(recCanvas);
      _cachedWorldPicture = recorder.endRecording();
    }
    canvas.drawPicture(_cachedWorldPicture!);
    _drawDynamicWorldDetails(canvas);

    // 2. Arka Bahçe 3D Çiftlik Tesisleri (Ahır + Silo, Yel Değirmenli Tarla, Tavuk Çiftliği)
    _drawFarmProducers(canvas);

    // 3. Lojistik Kamyonu & 🛵 3D Hızlı Kurye Durağı + Motosikleti
    _drawTruck(canvas);
    _drawCourierStationAndBike(canvas);

    // 4. Yerdeki 3D Paletli Kargo Kolileri
    _drawDeliveryBoxes(canvas);

    // 5. 3D Mağaza Mobilyaları, Soğutucu Dolaplar, Manav ve Gondol Reyonlar
    _drawFurnitureAndShelves(canvas);
    _drawLockedExpansion(canvas);

    // 6. Derinlik Sıralı (Y-Sorted) 3D Müşteriler & Oyuncu
    _drawCharactersSorted(canvas);

    // 6.B Tek Tek Rafa / Sepete / Pakete Uçan 3D Ürün Efektleri
    _drawFlyingShelfItems(canvas);

    // 7. Tavan Spot Işıkları, Cam Yansımaları ve Atmosferik Işık Hüzmeleri
    _drawAtmosphericLighting(canvas);
    _drawNightOverlay(canvas);

    // 8. Mouse Hedef Göstergesi
    _drawMouseTarget(canvas);

    // 9. Uçuşan Parçacıklar
    _drawParticles(canvas);

    canvas.restore();
  }

  // =========================================================================
  // YARDIMCI 3D EKSTRÜZYON & GERÇEKÇİ GÖLGE FONKSİYONLARI
  // =========================================================================

  /// Yumuşak gerçekçi güneş/ortam gölgesi çizer (Blur filtresiz yüksek FPS katmanlı gölge)
  void _drawSoftShadow(Canvas canvas, Rect rect, {double radius = 12, double offsetX = 10, double offsetY = 16, double blur = 14, double alpha = 0.42}) {
    final outerShadow = Paint()..color = Colors.black.withValues(alpha: alpha * 0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(offsetX, offsetY).inflate(blur * 0.25), Radius.circular(radius + 2)),
      outerShadow,
    );
    // Ambient Occlusion (Temas Gölgesi)
    final aoPaint = Paint()..color = Colors.black.withValues(alpha: alpha * 0.72);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(2.5, 4.5), Radius.circular(radius)),
      aoPaint,
    );
  }

  /// Tam 3 Boyutlu (Üst Yüzey + Ön Yüzey + Sağ Yan Derinlik Yüzeyi + Pah & Taban Kenarı) Prizma/Blok çizer
  void _draw3DBox(
    Canvas canvas, {
    required Rect baseRect,
    required double height3D,
    required List<Color> topColors,
    required List<Color> frontColors,
    Color? sideColor,
    double radius = 8,
    bool castShadow = true,
    Color? borderColor,
  }) {
    final double sideDepth = height3D * 0.42;

    if (castShadow) {
      _drawSoftShadow(
        canvas,
        baseRect,
        radius: radius,
        offsetX: sideDepth + 7,
        offsetY: height3D * 0.48 + 9,
        blur: 14,
        alpha: 0.44,
      );
    }

    final topRect = baseRect.translate(0, -height3D);
    final frontRect = Rect.fromLTWH(baseRect.left, baseRect.bottom - height3D, baseRect.width, height3D);

    // Sağ 3D Yan Derinlik Yüzeyi (Gradyanlı Hacim Gölgelendirmesi)
    final sidePath = Path()
      ..moveTo(topRect.right - radius * 0.25, topRect.top + radius * 0.25)
      ..lineTo(topRect.right + sideDepth, topRect.top + sideDepth * 0.58)
      ..lineTo(baseRect.right + sideDepth, baseRect.bottom - sideDepth * 0.18)
      ..lineTo(baseRect.right, baseRect.bottom)
      ..lineTo(topRect.right, topRect.bottom)
      ..close();

    final Color baseSide = sideColor ?? Color.lerp(frontColors.last, Colors.black, 0.35)!;
    final sideBounds = Rect.fromLTWH(topRect.right - 2, topRect.top, sideDepth + 4, baseRect.height + height3D);
    canvas.drawPath(
      sidePath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(baseSide, Colors.white, 0.14)!,
            baseSide,
            Color.lerp(baseSide, Colors.black, 0.42)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(sideBounds),
    );

    // Ön 3D Gövde Yüzeyi (Dikey Işık Kırılması)
    final frontPaint = Paint()
      ..shader = LinearGradient(
        colors: frontColors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(frontRect);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        frontRect,
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
      frontPaint,
    );

    // Ön Yüzey Alt Baza Karartması (Zemin Temas AO Çizgisi)
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(frontRect.left, frontRect.bottom - (height3D * 0.22).clamp(2.0, 7.0), frontRect.width, (height3D * 0.22).clamp(2.0, 7.0)),
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.26),
    );

    // Ön-Sağ Dikey Köşe Sırt Çizgisi (3D Ridge Line)
    canvas.drawLine(
      Offset(topRect.right - 0.5, topRect.bottom - 1),
      Offset(baseRect.right - 0.5, baseRect.bottom - 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 1.4,
    );

    // Üst 3D Tavan Yüzeyi
    final topPaint = Paint()
      ..shader = LinearGradient(
        colors: topColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(topRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(topRect, Radius.circular(radius)),
      topPaint,
    );

    // Üst Yüzey İç Çerçeve Işıltısı (3D Rim Light)
    if (topRect.width > 24 && topRect.height > 16) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(topRect.deflate(1.6), Radius.circular((radius - 1.5).clamp(1.0, 20.0))),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Üst-Ön Kenar Parlama Çizgisi (3D Bevel Specular Highlight)
    canvas.drawLine(
      Offset(topRect.left + radius, topRect.bottom - 0.5),
      Offset(topRect.right - radius, topRect.bottom - 0.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.58)
        ..strokeWidth = 2.2,
    );

    if (borderColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(topRect, Radius.circular(radius)),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  // =========================================================================
  // 1. DEVASA DÜNYA ZEMİNİ, 3D DUVARLAR, CADDE & ARKA ÇİFTLİK VADİSİ
  // =========================================================================
  void _drawStaticWorldEnvironment(Canvas canvas) {
    final doorCenter = engine.worldWidth / 2; // 1000

    // A. Ön Sokak Asfaltı (y: 0 - 150) - Gerçekçi Koyu Asfalt & Dokusu
    final asphaltRect = Rect.fromLTWH(0, 0, engine.worldWidth, 150);
    final asphaltPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF090D16), Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)],
        stops: [0.0, 0.35, 0.75, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(asphaltRect);
    canvas.drawRect(asphaltRect, asphaltPaint);

    // Asfalt Tekerlek İzleri ve Mikro Yansımalar
    final tireTrackPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = 14.0;
    canvas.drawLine(const Offset(0, 46), Offset(engine.worldWidth, 46), tireTrackPaint);
    canvas.drawLine(const Offset(0, 102), Offset(engine.worldWidth, 102), tireTrackPaint);

    // Yol Kesik Çift Sarı Şeritleri (Parlak Floresan Boya)
    final roadLineGlow = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..strokeWidth = 9.0;
    final roadLinePaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 4.5;
    for (double x = 20; x < engine.worldWidth; x += 90) {
      canvas.drawLine(Offset(x, 74), Offset(x + 52, 74), roadLineGlow);
      canvas.drawLine(Offset(x, 74), Offset(x + 52, 74), roadLinePaint);
    }

    // 3D Yaya Geçidi (Kabartmalı ve Gölgeli Zebra Şeritleri)
    for (double zy = 18; zy < 135; zy += 22) {
      final zRect = Rect.fromLTWH(doorCenter - 58, zy, 116, 13);
      canvas.drawRRect(
        RRect.fromRectAndRadius(zRect.translate(0, 3), const Radius.circular(3)),
        Paint()..color = Colors.black38,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zRect, const Radius.circular(3)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFFCBD5E1)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(zRect),
      );
    }

    // B. Ön Yaya Kaldırımı (y: 150 - 230) & 3D Bordür Taşı
    final sidewalkRect = Rect.fromLTWH(0, 150, engine.worldWidth, 80);
    // Kaldırımın Asfalta Düşen Oluk Gölgesi
    canvas.drawRect(
      Rect.fromLTWH(0, 140, engine.worldWidth, 12),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final sidewalkPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1), Color(0xFF94A3B8)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(sidewalkRect);
    canvas.drawRect(sidewalkRect, sidewalkPaint);

    // Kaldırım 3D Karo Derzleri ve Pah Işığı
    final paveLine = Paint()
      ..color = const Color(0xFF475569).withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    final paveHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    for (double px = 0; px < engine.worldWidth; px += 44) {
      canvas.drawLine(Offset(px, 150), Offset(px, 230), paveLine);
      canvas.drawLine(Offset(px + 1.5, 150), Offset(px + 1.5, 230), paveHighlight);
    }
    canvas.drawLine(const Offset(0, 190), Offset(engine.worldWidth, 190), paveLine);

    // 3D Kırmızı-Beyaz Kaldırım Bordür Taşları
    for (double cx = 0; cx < engine.worldWidth; cx += 40) {
      final isRed = ((cx ~/ 40) % 2 == 0);
      canvas.drawRect(
        Rect.fromLTWH(cx, 145, 40, 8),
        Paint()..color = isRed ? const Color(0xFFDC2626) : const Color(0xFFF1F5F9),
      );
      canvas.drawRect(
        Rect.fromLTWH(cx, 151, 40, 4),
        Paint()..color = isRed ? const Color(0xFF7F1D1D) : const Color(0xFF64748B),
      );
    }

    // C. ARKA BAHÇE ÇİFTLİK VADİSİ ZEMİNİ (y: 990 - 1650)
    final farmBgRect = Rect.fromLTWH(0, 990, engine.worldWidth, engine.worldHeight - 990);
    final grassPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF15803D), Color(0xFF166534), Color(0xFF14532D), Color(0xFF052E16)],
        stops: [0.0, 0.35, 0.75, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(farmBgRect);
    canvas.drawRect(farmBgRect, grassPaint);

    // Doğal Çimen Kümeleri, Gölgeli Toprak Benekleri & Kır Çiçekleri (Statik Picture'a kaydedilir)
    for (double gy = 1020; gy < engine.worldHeight - 25; gy += 58) {
      for (double gx = 55; gx < engine.worldWidth - 55; gx += 76) {
        final wave = sin(gx * 0.03 + gy * 0.02) * 2.2;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(gx, gy + 4), width: 22, height: 8),
          Paint()..color = Colors.black.withValues(alpha: 0.16),
        );
        final bladePaint = Paint()
          ..color = const Color(0xFF4ADE80).withValues(alpha: 0.55)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(gx - 3, gy + 2), Offset(gx - 7 + wave, gy - 9), bladePaint);
        canvas.drawLine(Offset(gx, gy + 2), Offset(gx + wave, gy - 11), bladePaint);
        canvas.drawLine(Offset(gx + 3, gy + 2), Offset(gx + 7 + wave, gy - 8), bladePaint);
        canvas.drawCircle(Offset(gx + 14, gy + 7), 2.8, Paint()..color = const Color(0xFFFDE047));
        canvas.drawCircle(Offset(gx + 14, gy + 7), 1.2, Paint()..color = const Color(0xFFEA580C));
      }
    }

    // Arka Kapıdan Ahır, Tarla, Kümes ve Alt Sıra Meyve/Sebze Tarlalarına Uzanan 3D Kabartmalı Taş Patika Yol
    final mainPath = Rect.fromLTWH(doorCenter - 68, 990, 136, 145);
    const crossPath = Rect.fromLTWH(260, 1082, 1480, 74);
    const leftCorridor = Rect.fromLTWH(640, 1145, 80, 355);
    const rightCorridor = Rect.fromLTWH(1280, 1145, 80, 355);
    const lowerCrossPath = Rect.fromLTWH(230, 1482, 1540, 62);

    _drawSoftShadow(canvas, mainPath, radius: 12, offsetX: 4, offsetY: 7, blur: 8, alpha: 0.35);
    _drawSoftShadow(canvas, crossPath, radius: 18, offsetX: 4, offsetY: 7, blur: 8, alpha: 0.35);
    _drawSoftShadow(canvas, leftCorridor, radius: 12, offsetX: 4, offsetY: 7, blur: 8, alpha: 0.30);
    _drawSoftShadow(canvas, rightCorridor, radius: 12, offsetX: 4, offsetY: 7, blur: 8, alpha: 0.30);
    _drawSoftShadow(canvas, lowerCrossPath, radius: 16, offsetX: 4, offsetY: 7, blur: 8, alpha: 0.32);

    final pathPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFD6D3D1), Color(0xFFA8A29E), Color(0xFF78716C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(crossPath);
    canvas.drawRRect(RRect.fromRectAndRadius(mainPath, const Radius.circular(12)), pathPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(crossPath, const Radius.circular(18)), pathPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(leftCorridor, const Radius.circular(12)), pathPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rightCorridor, const Radius.circular(12)), pathPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(lowerCrossPath, const Radius.circular(16)), pathPaint);

    // 3D Arnavut Kaldırımı Taşları (Gölge + Üst Işık)
    for (double sx = 290; sx < 1710; sx += 44) {
      final s1 = Rect.fromCenter(center: Offset(sx, 1106), width: 28, height: 16);
      final s2 = Rect.fromCenter(center: Offset(sx + 22, 1132), width: 26, height: 15);
      canvas.drawOval(s1.translate(1.5, 2.5), Paint()..color = Colors.black38);
      canvas.drawOval(s1, Paint()..color = const Color(0xFFE7E5E4));
      canvas.drawOval(s2.translate(1.5, 2.5), Paint()..color = Colors.black38);
      canvas.drawOval(s2, Paint()..color = const Color(0xFFD6D3D1));

      final s3 = Rect.fromCenter(center: Offset(sx, 1504), width: 26, height: 14);
      final s4 = Rect.fromCenter(center: Offset(sx + 22, 1524), width: 24, height: 14);
      canvas.drawOval(s3.translate(1.5, 2.5), Paint()..color = Colors.black38);
      canvas.drawOval(s3, Paint()..color = const Color(0xFFE7E5E4));
      canvas.drawOval(s4.translate(1.5, 2.5), Paint()..color = Colors.black38);
      canvas.drawOval(s4, Paint()..color = const Color(0xFFD6D3D1));
    }

    // D. MARKET BİNASI İÇ ZEMİN FAYANSI (x: 85 - 1915, y: 230 - 990)
    final floorRect = Rect.fromLTWH(85, 230, engine.worldWidth - 170, 760);

    // Bina Dış Çevre Devasa 3D Gölgesi
    _drawSoftShadow(canvas, floorRect, radius: 18, offsetX: 14, offsetY: 22, blur: 24, alpha: 0.55);

    // Mermer/Porselen Zemin Alt Taban
    canvas.drawRRect(
      RRect.fromRectAndRadius(floorRect, const Radius.circular(18)),
      Paint()..color = const Color(0xFFF1F5F9),
    );

    const tileSize = 75.0;
    final seamPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.38)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    for (double y = 230; y < 990; y += tileSize) {
      for (double x = 85; x < engine.worldWidth - 85; x += tileSize) {
        final w = min(tileSize, engine.worldWidth - 85 - x);
        final h = min(tileSize, 990 - y);
        final r = Rect.fromLTWH(x, y, w, h);

        final isAlt = ((x ~/ tileSize) + (y ~/ tileSize)) % 2 == 0;
        final tileGrad = Paint()
          ..shader = LinearGradient(
            colors: isAlt
                ? [const Color(0xFFFFFFFF), const Color(0xFFF1F5F9)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r);

        canvas.drawRect(r, tileGrad);
        canvas.drawRect(r, seamPaint);

        // Fayans Sol-Üst Pah Parlaması
        canvas.drawLine(
          Offset(x + 2, y + 2),
          Offset(x + w - 2, y + 2),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.8)
            ..strokeWidth = 1.0,
        );
      }
    }

    // Zeminde Çapraz Cilalı Mermer Yansıma Şeritleri (Glossy Specular Floor Streaks)
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(floorRect, const Radius.circular(18)));
    final glossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 55.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawLine(const Offset(250, 220), const Offset(680, 990), glossPaint);
    canvas.drawLine(const Offset(850, 220), const Offset(1320, 990), glossPaint);
    canvas.drawLine(const Offset(1450, 220), const Offset(1850, 990), glossPaint);

    // Duvar Diplerinde İç Ortam Gölgesi (Interior Wall Ambient Occlusion)
    canvas.drawRect(
      Rect.fromLTWH(85, 230, engine.worldWidth - 170, 32),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.black.withValues(alpha: 0.28), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(85, 230, engine.worldWidth - 170, 32)),
    );
    canvas.drawRect(
      Rect.fromLTWH(85, 230, 32, 760),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.black.withValues(alpha: 0.24), Colors.transparent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(const Rect.fromLTWH(85, 230, 32, 760)),
    );
    canvas.restore();

    // E. Ön Giriş Paspası ("🌟 SÜPERMARKET 3D 🌟")
    final matRect = Rect.fromLTWH(doorCenter - 100, 236, 200, 54);
    _drawSoftShadow(canvas, matRect, radius: 10, offsetX: 3, offsetY: 5, blur: 6, alpha: 0.35);
    final matPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF065F46), Color(0xFF064E3B), Color(0xFF022C22)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(matRect);
    canvas.drawRRect(RRect.fromRectAndRadius(matRect, const Radius.circular(10)), matPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(matRect.deflate(3.5), const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _drawText(canvas, '🌟 WELCOME 🌟', doorCenter, 263, fontSize: 13, color: const Color(0xFFFEF3C7), isBold: true);

    // F. Arka Çiftlik Kapısı Paspası
    final backMatRect = Rect.fromLTWH(doorCenter - 115, 938, 230, 46);
    _drawSoftShadow(canvas, backMatRect, radius: 10, offsetX: 3, offsetY: 5, blur: 6, alpha: 0.35);
    final backMatPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF92400E), Color(0xFF78350F), Color(0xFF451A03)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(backMatRect);
    canvas.drawRRect(RRect.fromRectAndRadius(backMatRect, const Radius.circular(10)), backMatPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(backMatRect.deflate(3), const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFFFCD34D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    _drawText(canvas, '🚪 BACK DOOR 🚪', doorCenter, 961, fontSize: 11.5, color: const Color(0xFFFEF3C7), isBold: true);

    // G. 3D YÜKSEK DUVARLAR, ÇATI PARAPETİ VE CAM VİTRİNLER
    _draw3DWallSegment(canvas, 68, 215, 26, 785); // Sol 3D Duvar
    _draw3DWallSegment(canvas, engine.worldWidth - 94, 215, 26, 785); // Sağ 3D Duvar

    // Ön Duvar (Sol ve Sağ Kanat - Ortada Geniş Otomatik Cam Kapı)
    _draw3DWallSegment(canvas, 68, 215, doorCenter - 140 - 68, 28, isFrontGlass: true);
    _draw3DWallSegment(canvas, doorCenter + 140, 215, (engine.worldWidth - 68) - (doorCenter + 140), 28, isFrontGlass: true);

    // Ön Giriş 3D Işıklı Market Kanopisi / Tabelası & Çizgili Tente
    final awningDropRect = Rect.fromCenter(center: Offset(doorCenter, 224), width: 310, height: 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(awningDropRect.translate(0, 6), const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    for (int s = 0; s < 10; s++) {
      final sx = awningDropRect.left + s * (awningDropRect.width / 10);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(sx, awningDropRect.top, awningDropRect.width / 10 - 1, awningDropRect.height),
          bottomLeft: const Radius.circular(6),
          bottomRight: const Radius.circular(6),
        ),
        Paint()..color = s.isEven ? const Color(0xFF0284C7) : const Color(0xFFF8FAFC),
      );
    }

    final mainSignRect = Rect.fromCenter(center: Offset(doorCenter, 204), width: 310, height: 36);
    _draw3DBox(
      canvas,
      baseRect: mainSignRect,
      height3D: 22,
      topColors: const [Color(0xFF0284C7), Color(0xFF0369A1)],
      frontColors: const [Color(0xFF0F172A), Color(0xFF1E293B)],
      radius: 10,
      borderColor: const Color(0xFF38BDF8),
    );
    _drawText(canvas, '🏪 VILLAGE MARKET', doorCenter, 191, fontSize: 12.5, color: Colors.white, isBold: true);

    // Kaldırım Üzeri 3D Market Alışveriş Arabaları Park Durağı ve Ahşap Bank
    _draw3DShoppingCartCorral(canvas, 480, 184);
    _draw3DOutdoorBench(canvas, 1520, 184);

    // Arka Duvar (Sol ve Sağ Kanat - Ortada Geniş Çiftlik Kapısı)
    _draw3DWallSegment(canvas, 68, 982, doorCenter - 140 - 68, 26);
    _draw3DWallSegment(canvas, doorCenter + 140, 982, (engine.worldWidth - 68) - (doorCenter + 140), 26);

    // Kaldırım Sokak Lambaları & 3D Ağaçlar
    for (var lx in [340.0, 820.0, 1180.0, 1660.0]) {
      _draw3DStreetLamp(canvas, lx, 162);
    }
    for (var tx in [140.0, 620.0, 1380.0, 1840.0]) {
      _draw3DTreeStatic(canvas, tx, 186);
    }
    // Çiftlik Kenarı 3D Ağaçlar
    for (var ftx in [85.0, 1915.0]) {
      _draw3DTreeStatic(canvas, ftx, 1150);
      _draw3DTreeStatic(canvas, ftx, 1540);
    }
  }

  /// Dinamik dünya detayları (hareketli otomatik kayar kapılar)
  void _drawDynamicWorldDetails(Canvas canvas) {
    final doorCenter = engine.worldWidth / 2;
    _draw3DAutomaticSlidingDoors(canvas, doorCenter, 215, 140);
    _draw3DAutomaticSlidingDoors(canvas, doorCenter, 982, 140, isFarmDoor: true);
  }

  /// Ön ve arka girişlerdeki 3D otomatik kayar cam kapıları ve sensörlerini çizer
  void _draw3DAutomaticSlidingDoors(Canvas canvas, double centerX, double wallY, double halfGap, {bool isFarmDoor = false}) {
    bool someoneNear = (engine.playerX - centerX).abs() < 165 && (engine.playerY - wallY).abs() < 120;
    if (!someoneNear && !isFarmDoor) {
      for (final c in engine.customers) {
        if ((c.x - centerX).abs() < 150 && (c.y - wallY).abs() < 110) {
          someoneNear = true;
          break;
        }
      }
    }
    if (!someoneNear && isFarmDoor && engine.hasRestocker && engine.isRestockerHired) {
      if ((engine.restocker.x - centerX).abs() < 150 && (engine.restocker.y - wallY).abs() < 110) {
        someoneNear = true;
      }
    }

    final double slideOffset = someoneNear ? (halfGap * 0.72) : 4.0;
    final double panelW = halfGap - 6.0;

    // Üst Sensör Rayı
    final railRect = Rect.fromCenter(center: Offset(centerX, wallY - 18), width: halfGap * 2 + 16, height: 8);
    canvas.drawRRect(RRect.fromRectAndRadius(railRect, const Radius.circular(4)), Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      Offset(centerX, wallY - 18),
      3.5,
      Paint()..color = someoneNear ? const Color(0xFF4ADE80) : const Color(0xFF38BDF8),
    );

    for (final side in [-1.0, 1.0]) {
      final double px = side < 0
          ? (centerX - slideOffset - panelW)
          : (centerX + slideOffset);
      final Rect glassPanel = Rect.fromLTWH(px, wallY - 14, panelW, 24);

      // Cam Gölgesi
      canvas.drawRRect(
        RRect.fromRectAndRadius(glassPanel.translate(2, 5), const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );
      // 3D Yarı Saydam Mavi Temperli Cam Kanat
      canvas.drawRRect(
        RRect.fromRectAndRadius(glassPanel, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFFBAE6FD).withValues(alpha: 0.55),
              const Color(0xFF0284C7).withValues(alpha: 0.45),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(glassPanel),
      );
      // Krom Kapı Çerçevesi
      canvas.drawRRect(
        RRect.fromRectAndRadius(glassPanel, const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFFE2E8F0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      // Cam Üzeri Parlama Şeridi
      canvas.drawLine(
        Offset(glassPanel.left + 14, glassPanel.top + 3),
        Offset(glassPanel.left + 6, glassPanel.bottom - 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.65)
          ..strokeWidth = 2.5,
      );
    }
  }

  /// Kaldırım üzerinde iç içe geçmiş 3D metal market arabaları durağı çizer
  void _draw3DShoppingCartCorral(Canvas canvas, double x, double y) {
    final corralRect = Rect.fromCenter(center: Offset(x, y), width: 112, height: 34);
    _drawSoftShadow(canvas, corralRect, radius: 8, offsetX: 4, offsetY: 6, blur: 8, alpha: 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(corralRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF1E293B).withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(corralRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    for (int i = 0; i < 4; i++) {
      final cx = corralRect.left + 20.0 + i * 22.0;
      final cartRect = Rect.fromCenter(center: Offset(cx, y - 2), width: 20, height: 18);
      _draw3DBox(
        canvas,
        baseRect: cartRect,
        height3D: 9,
        topColors: const [Color(0xFFF8FAFC), Color(0xFFCBD5E1)],
        frontColors: const [Color(0xFF94A3B8), Color(0xFF475569)],
        radius: 3,
        castShadow: false,
      );
      canvas.drawLine(
        Offset(cartRect.left - 2, cartRect.top - 9),
        Offset(cartRect.left - 2, cartRect.bottom - 9),
        Paint()
          ..color = const Color(0xFFEF4444)
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Kaldırım üzerinde 3D ahşap dinlenme bankı ve çiçek saksıları çizer
  void _draw3DOutdoorBench(Canvas canvas, double x, double y) {
    final benchRect = Rect.fromCenter(center: Offset(x, y), width: 84, height: 24);
    _draw3DBox(
      canvas,
      baseRect: benchRect,
      height3D: 11,
      topColors: const [Color(0xFFD97706), Color(0xFF92400E)],
      frontColors: const [Color(0xFF78350F), Color(0xFF451A03)],
      radius: 5,
    );
    final backRest = Rect.fromCenter(center: Offset(x, y - 16), width: 82, height: 7);
    canvas.drawRRect(RRect.fromRectAndRadius(backRest, const Radius.circular(3)), Paint()..color = const Color(0xFFB45309));
    // Yanlarda 2 adet 3D Çiçek Saksısı
    for (final px in [x - 58.0, x + 58.0]) {
      canvas.drawCircle(Offset(px + 2, y + 3), 12, Paint()..color = Colors.black38);
      canvas.drawCircle(Offset(px, y), 12, Paint()..color = const Color(0xFF78350F));
      canvas.drawCircle(Offset(px, y - 3), 9.5, Paint()..color = const Color(0xFF16A34A));
      canvas.drawCircle(Offset(px - 3, y - 5), 3.0, Paint()..color = const Color(0xFFF472B6));
      canvas.drawCircle(Offset(px + 3, y - 4), 3.0, Paint()..color = const Color(0xFFFACC15));
    }
  }

  void _draw3DWallSegment(Canvas canvas, double x, double y, double w, double h, {bool isFrontGlass = false}) {
    final baseRect = Rect.fromLTWH(x, y, w, h);
    _draw3DBox(
      canvas,
      baseRect: baseRect,
      height3D: 26,
      topColors: const [Color(0xFF64748B), Color(0xFF475569), Color(0xFF334155)],
      frontColors: const [Color(0xFF334155), Color(0xFF1E293B), Color(0xFF0F172A)],
      sideColor: const Color(0xFF0F172A),
      radius: 5,
      borderColor: const Color(0xFF94A3B8).withValues(alpha: 0.4),
    );

    if (isFrontGlass && w > 120) {
      // 3D Parlak Mavi Cam Vitrin ve Yansıma Çizgileri
      final glassRect = Rect.fromLTWH(x + 28, y - 16, w - 56, 28);
      final glassPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7DD3FC), Color(0xFF0284C7), Color(0xFF0369A1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(glassRect);
      canvas.drawRRect(RRect.fromRectAndRadius(glassRect, const Radius.circular(4)), glassPaint);

      // Cam Parlama Şeritleri
      final shinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 3.0;
      for (double gx = x + 60; gx < x + w - 60; gx += 85) {
        canvas.drawLine(Offset(gx, glassRect.top + 3), Offset(gx - 14, glassRect.bottom - 3), shinePaint);
      }
    }
  }

  void _draw3DStreetLamp(Canvas canvas, double x, double y) {
    // Yere Düşen Uzun Direk Gölgesi
    canvas.drawLine(
      Offset(x, y),
      Offset(x + 26, y + 18),
      Paint()
        ..color = Colors.black38
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    // Döküm Demir Kaide ve Direk
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = const Color(0xFF0F172A));
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y - 38),
      Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round,
    );
    // Lamba Başlığı ve Sıcak LED Işık Halesi (Blur filtresiz)
    canvas.drawCircle(
      Offset(x, y - 38),
      26,
      Paint()..color = const Color(0xFFFEF08A).withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      Offset(x, y - 38),
      15,
      Paint()..color = const Color(0xFFFEF08A).withValues(alpha: 0.24),
    );
    canvas.drawCircle(Offset(x, y - 38), 7, Paint()..color = const Color(0xFFFEF9C3));
  }

  void _draw3DTreeStatic(Canvas canvas, double x, double y) {
    // Yumuşak Ağaç Gölgesi
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 12, y + 16), width: 62, height: 30),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    // 3D Gövde ve Kök
    final trunkRect = Rect.fromCenter(center: Offset(x, y + 4), width: 13, height: 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trunkRect, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFF451A03)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(trunkRect),
    );

    // Katmanlı 3D Küresel Yaprak Tacı
    void drawLeafSphere(double cx, double cy, double r, List<Color> colors) {
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: colors,
            center: const Alignment(-0.35, -0.35),
          ).createShader(rect),
      );
    }

    drawLeafSphere(x, y - 10, 26, const [Color(0xFF22C55E), Color(0xFF15803D), Color(0xFF052E16)]);
    drawLeafSphere(x - 10, y - 18, 19, const [Color(0xFF4ADE80), Color(0xFF16A34A), Color(0xFF14532D)]);
    drawLeafSphere(x + 11, y - 16, 18, const [Color(0xFF4ADE80), Color(0xFF15803D), Color(0xFF052E16)]);
    drawLeafSphere(x, y - 26, 15, const [Color(0xFF86EFAC), Color(0xFF22C55E), Color(0xFF15803D)]);
  }

  // =========================================================================
  // 2. ARKA BAHÇE DEVASA 3D ÇİFTLİK TESİSLERİ (AHIR, TARLA, TAVUK ÇİFTLİĞİ)
  // Kova & Tırpan Standları, Açık Çit Kapıları ve İçeride Hasat/Sağım/Toplama!
  // =========================================================================
  void _drawFarmProducers(Canvas canvas) {
    if (engine.isCheeseUnlocked) {
      _draw3DCheeseMachine(canvas);
    }
    for (var farm in engine.farmProducers) {
      if (!farm.isUnlocked) {
        _drawLockedFarmPlot(canvas, farm);
        continue;
      }
      if (farm.zoneType == FarmZoneType.barn) {
        _draw3DBarn(canvas, farm);
      } else if (farm.zoneType == FarmZoneType.field) {
        _draw3DField(canvas, farm);
      } else if (farm.zoneType == FarmZoneType.coop) {
        _draw3DChickenCoop(canvas, farm);
      }
      _drawFarmToolStand(canvas, farm);
    }
  }

  /// Henüz marketteki reyonu açılmamış meyve/sebze/ekmek tarlası için sadece zeminde bilgilendirme yazısı gösterir
  void _drawLockedFarmPlot(Canvas canvas, FarmProducer farm) {
    final def = productCatalog[farm.primaryProduct]!;
    final center = farm.rect.center;
    final badgeRect = Rect.fromCenter(center: center, width: 250, height: 46);

    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect.translate(0, 3), const Radius.circular(14)),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(14)),
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.72),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(14)),
      Paint()
        ..color = def.primaryColor.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    _drawText(
      canvas,
      '🔒 ${def.emoji} ${farm.name}',
      center.dx,
      center.dy - 8,
      fontSize: 10.8,
      color: Colors.white,
      isBold: true,
    );
    _drawText(
      canvas,
      'This Field Unlocks When the Shelf Is Opened at the Store',
      center.dx,
      center.dy + 9,
      fontSize: 9.2,
      color: const Color(0xFFFDE047),
      isBold: true,
    );
  }

  // 🧀 3D PEYNİR YAPMA MAKİNESİ (Tulum Peyniri açıldığında devreye girer; Sütü Peynire dönüştürür)
  void _draw3DCheeseMachine(Canvas canvas) {
    final rect = engine.cheeseMachineRect;

    if (engine.isCheeseMachineHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(8), const Radius.circular(18)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    // 3D Makine Gövdesi (Paslanmaz Çelik & Bakır Mandıra Tezgahı)
    _draw3DBox(
      canvas,
      baseRect: rect,
      height3D: 24,
      topColors: const [Color(0xFFE2E8F0), Color(0xFF94A3B8)],
      frontColors: const [Color(0xFF475569), Color(0xFF1E293B)],
      sideColor: const Color(0xFF0F172A),
      radius: 12,
      borderColor: const Color(0xFFFACC15),
    );

    final topFace = rect.translate(0, -24);

    // Sol Taraf: 3D Yuvarlak Süt Mayalama Kazanı
    final vatCenter = Offset(topFace.left + 48, topFace.center.dy + 4);
    canvas.drawCircle(vatCenter.translate(2, 3), 24, Paint()..color = Colors.black38);
    canvas.drawCircle(
      vatCenter,
      24,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFF92400E)],
        ).createShader(Rect.fromCircle(center: vatCenter, radius: 24)),
    );
    // Kazan İçindeki Süt / Peynir Mayası
    final isProcessing = engine.cheeseMachineMilkInput > 0;
    canvas.drawCircle(
      vatCenter,
      18,
      Paint()..color = isProcessing ? const Color(0xFFFEF08A) : const Color(0xFFF8FAFC),
    );
    // Dönen Karıştırıcı Pervane
    canvas.save();
    canvas.translate(vatCenter.dx, vatCenter.dy);
    if (isProcessing) {
      canvas.rotate(engine.worldTime * 4.5);
    }
    final paddlePaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-12, 0), const Offset(12, 0), paddlePaint);
    canvas.drawLine(const Offset(0, -12), const Offset(0, 12), paddlePaint);
    canvas.restore();

    // Sağ Taraf: Hazır 3D Altın Tulum Peyniri Tekerleri Tepsisi
    final trayRect = Rect.fromLTWH(topFace.left + 92, topFace.top + 22, 88, 42);
    canvas.drawRRect(RRect.fromRectAndRadius(trayRect, const Radius.circular(8)), Paint()..color = const Color(0xFF334155));
    for (int i = 0; i < engine.cheeseMachineReadyBoxes; i++) {
      final cx = trayRect.left + 20.0 + (i * 25.0);
      final cy = trayRect.center.dy;
      canvas.drawCircle(Offset(cx + 1, cy + 3), 10, Paint()..color = Colors.black38);
      canvas.drawCircle(
        Offset(cx, cy),
        10,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFEF08A), Color(0xFFFACC15), Color(0xFFCA8A04)],
            center: Alignment(-0.3, -0.3),
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 10)),
      );
    }

    // Üst Başlık Tabelası
    final headerRect = Rect.fromLTWH(topFace.left + 8, topFace.top - 10, topFace.width - 16, 22);
    canvas.drawRRect(RRect.fromRectAndRadius(headerRect, const Radius.circular(6)), Paint()..color = const Color(0xFFCA8A04));
    _drawText(canvas, '🧀 CHEESE MAKING MACHINE', headerRect.center.dx, headerRect.center.dy, fontSize: 9.2, color: Colors.white, isBold: true);

    // Alt Durum Çubuğu
    final statusRect = Rect.fromLTWH(rect.left + 8, rect.bottom - 20, rect.width - 16, 17);
    canvas.drawRRect(RRect.fromRectAndRadius(statusRect, const Radius.circular(6)), Paint()..color = const Color(0xFF0F172A));
    if (isProcessing) {
      final prog = (engine.cheeseMachineTimer / engine.cheeseMachineDuration).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(statusRect.left + 2, statusRect.top + 2, (statusRect.width - 4) * prog, statusRect.height - 4),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFF22C55E),
      );
      _drawText(canvas, '⚙️ MAKING CHEESE ${(prog * 100).toInt()}%', statusRect.center.dx, statusRect.center.dy, fontSize: 8.5, color: Colors.white, isBold: true);
    } else if (engine.cheeseMachineReadyBoxes > 0) {
      _drawText(
        canvas,
        '🧀 READY: ${engine.cheeseMachineReadyBoxes}/${engine.cheeseMachineMaxBoxes} CHEESE (TAKE)',
        statusRect.center.dx,
        statusRect.center.dy,
        fontSize: 8.5,
        color: const Color(0xFF4ADE80),
        isBold: true,
      );
    } else {
      _drawText(
        canvas,
        '🥛 BRING MILK FROM THE BARN & POUR',
        statusRect.center.dx,
        statusRect.center.dy,
        fontSize: 8.5,
        color: Colors.amberAccent,
        isBold: true,
      );
    }
  }

  // 2.0 GİRİŞTEKİ 3D KOVA & TIRPAN STANDI (Süt Kovası, Tırpan, Yumurta Kovası)
  void _drawFarmToolStand(Canvas canvas, FarmProducer farm) {
    final pos = farm.toolStandPos;
    final isEquipped = engine.playerTool == farm.requiredTool;
    final standRect = Rect.fromCenter(center: pos, width: 68, height: 34);

    if (farm.isToolStandHovered || isEquipped) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(standRect.inflate(6), const Radius.circular(12)),
        Paint()
          ..color = isEquipped ? const Color(0xFF4ADE80) : Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }

    // 3D Ahşap Ekipman Tezgahı
    _draw3DBox(
      canvas,
      baseRect: standRect,
      height3D: 14,
      topColors: const [Color(0xFFD97706), Color(0xFF92400E)],
      frontColors: const [Color(0xFF78350F), Color(0xFF451A03)],
      sideColor: const Color(0xFF290F02),
      radius: 8,
      borderColor: const Color(0xFFFDE68A).withValues(alpha: 0.7),
    );

    final topCenter = Offset(pos.dx, pos.dy - 14);

    if (farm.requiredTool == FarmToolType.milkBucket) {
      // Stand üzerinde 2 adet Parlak 3D Metal Süt Kovası
      _draw3DMilkBucketIcon(canvas, topCenter.dx - 13, topCenter.dy - 2, scale: 0.95, hasMilk: false);
      _draw3DMilkBucketIcon(canvas, topCenter.dx + 13, topCenter.dy - 2, scale: 0.95, hasMilk: true);
    } else if (farm.requiredTool == FarmToolType.scythe) {
      // Stand üzerinde 3D Çelik Bıçaklı Hasat Tırpanı
      _draw3DScytheIcon(canvas, topCenter.dx, topCenter.dy - 4, angle: -0.35, scale: 1.05);
    } else {
      // Stand üzerinde 2 adet 3D Yumurta Toplama Kovası
      _draw3DEggBucketIcon(canvas, topCenter.dx - 13, topCenter.dy - 2, scale: 0.95, hasEggs: false);
      _draw3DEggBucketIcon(canvas, topCenter.dx + 13, topCenter.dy - 2, scale: 0.95, hasEggs: true);
    }

    // Üst Tabela Etiketi
    final badgeRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy - 36), width: 112, height: 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)),
      Paint()..color = isEquipped ? const Color(0xFF15803D) : const Color(0xFF0F172A).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)),
      Paint()
        ..color = isEquipped ? const Color(0xFF4ADE80) : Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _drawText(
      canvas,
      isEquipped ? '✅ ${farm.requiredTool.name.toUpperCase()}' : 'TAKE ${farm.requiredTool.emoji} ${farm.requiredTool.name.toUpperCase()}',
      pos.dx,
      pos.dy - 36,
      fontSize: 8.8,
      color: Colors.white,
      isBold: true,
    );
  }

  void _draw3DMilkBucketIcon(Canvas canvas, double x, double y, {double scale = 1.0, bool hasMilk = false}) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    // Kova gölgesi
    canvas.drawOval(Rect.fromCenter(center: const Offset(1, 8), width: 18, height: 8), Paint()..color = Colors.black38);
    // Metalik Mavi-Gümüş Kova Gövdesi
    final bodyRect = Rect.fromCenter(center: const Offset(0, 1), width: 16, height: 15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFF38BDF8), Color(0xFF0284C7)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bodyRect),
    );
    // Kova Üst Ağız ve Süt Doluluğu
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -6), width: 16, height: 6),
      Paint()..color = hasMilk ? Colors.white : const Color(0xFF0C4A6E),
    );
    // Metal Kova Sapı (Kemer)
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(0, -6), width: 16, height: 14),
      pi,
      pi,
      false,
      Paint()
        ..color = const Color(0xFFF8FAFC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.restore();
  }

  void _draw3DEggBucketIcon(Canvas canvas, double x, double y, {double scale = 1.0, bool hasEggs = false}) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    canvas.drawOval(Rect.fromCenter(center: const Offset(1, 8), width: 18, height: 8), Paint()..color = Colors.black38);
    final bodyRect = Rect.fromCenter(center: const Offset(0, 1), width: 17, height: 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(5)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFB45309)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bodyRect),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -5), width: 17, height: 6),
      Paint()..color = const Color(0xFF78350F),
    );
    if (hasEggs) {
      canvas.drawCircle(const Offset(-3, -6), 3.0, Paint()..color = const Color(0xFFFFFBEB));
      canvas.drawCircle(const Offset(3, -6), 3.0, Paint()..color = const Color(0xFFFEF3C7));
      canvas.drawCircle(const Offset(0, -7.5), 3.0, Paint()..color = Colors.white);
    }
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(0, -5), width: 16, height: 13),
      pi,
      pi,
      false,
      Paint()
        ..color = const Color(0xFF78350F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }

  void _draw3DScytheIcon(Canvas canvas, double x, double y, {double angle = 0.0, double scale = 1.0}) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.scale(scale);
    // Uzun Ahşap Tırpan Sapı
    canvas.drawLine(
      const Offset(-14, 12),
      const Offset(12, -12),
      Paint()
        ..color = const Color(0xFF92400E)
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round,
    );
    // Hilal Şeklinde Parlak Çelik Tırpan Bıçağı
    final bladePath = Path()
      ..moveTo(10, -12)
      ..quadraticBezierTo(26, -6, 22, 11)
      ..quadraticBezierTo(17, -1, 7, -9)
      ..close();
    canvas.drawPath(
      bladePath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFCBD5E1), Color(0xFF64748B)],
        ).createShader(const Rect.fromLTWH(6, -14, 24, 26)),
    );
    canvas.restore();
  }

  // 2.A 3D İNEK AHIRI, METAL SİLO & MANDIRA (İçeri Girip Kova ile Süt Sağma)
  void _draw3DBarn(Canvas canvas, FarmProducer farm) {
    final rect = farm.rect;

    if (farm.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(20)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5,
      );
    }

    _drawSoftShadow(canvas, rect, radius: 18, offsetX: 10, offsetY: 16, blur: 16, alpha: 0.45);

    // Canlı Yeşil Mera Zemini
    final pasturePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4ADE80), Color(0xFF22C55E), Color(0xFF15803D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), pasturePaint);

    // Kapıdan İneklere Uzanan Taşlı Toprak Yürüyüş Yolu
    final gatePathRect = Rect.fromLTWH(farm.gateMinX + 8, rect.top - 10, farm.gateMaxX - farm.gateMinX - 16, 85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(gatePathRect, const Radius.circular(12)),
      Paint()..color = const Color(0xFF15803D).withValues(alpha: 0.55),
    );

    // 3D Ahşap Çit Direkleri ve Açık Giriş Kapısı
    _draw3DWoodenFence(canvas, rect, gateMinX: farm.gateMinX, gateMaxX: farm.gateMaxX);

    // 3D Yüksek Metal Yem Silosu (Sol Üst Köşe)
    final siloCenter = Offset(rect.left + 44, rect.top + 56);
    _drawSoftShadow(canvas, Rect.fromCircle(center: siloCenter, radius: 24), radius: 24, offsetX: 8, offsetY: 12, blur: 10);
    final siloRect = Rect.fromCenter(center: siloCenter, width: 42, height: 58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(siloRect, const Radius.circular(18)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF94A3B8), Color(0xFFF8FAFC), Color(0xFF64748B), Color(0xFF334155)],
          stops: [0.0, 0.35, 0.75, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(siloRect),
    );
    // Silo Kubbesi
    canvas.drawCircle(
      Offset(siloCenter.dx, siloCenter.dy - 14),
      20,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFF94A3B8), Color(0xFF475569)],
          center: Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: Offset(siloCenter.dx, siloCenter.dy - 14), radius: 20)),
    );

    // 3D Su Yalağı & Sarı Saman Balyaları (Ferah Açık Mera Alanı)
    final troughRect = Rect.fromLTWH(rect.center.dx - 28, rect.top + 135, 56, 26);
    _draw3DBox(
      canvas,
      baseRect: troughRect,
      height3D: 12,
      topColors: const [Color(0xFF38BDF8), Color(0xFF0284C7)],
      frontColors: const [Color(0xFF475569), Color(0xFF1E293B)],
      radius: 6,
    );

    _draw3DHayBale(canvas, rect.right - 60, rect.top + 54);
    _draw3DHayBale(canvas, rect.right - 26, rect.top + 58);

    // İçerideki 4 Otlayan & Teker Teker Süt Üreten 3D İnek
    for (int i = 0; i < farm.spots.length; i++) {
      final spot = farm.spots[i];
      // Her ineğin yürüyüş ve otlama fazı birbirinden bağımsız (ayrı ayrı hareket ederler)
      final phase = engine.worldTime * 2.1 + (i * 1.85);
      final walkX = sin(phase) * 5.0;
      final walkY = cos(phase * 0.7) * 2.5;
      _draw3DCow(canvas, spot.x + walkX, spot.y + walkY, spot: spot);
      _drawSpotStatusBadge(
        canvas,
        spot: spot,
        readyLabel: '🥛 MILK',
        activeLabel: '🥛 Milking',
        accentColor: const Color(0xFF0284C7),
        offsetY: -32,
      );
    }

    _drawFarmHeaderAndStatus(canvas, farm, '🐄 COW PASTURE (🧺 TAKE A BUCKET & GO INSIDE TO MILK)', const Color(0xFF0284C7));
  }

  void _draw3DHayBale(Canvas canvas, double x, double y) {
    final r = Rect.fromCenter(center: Offset(x, y), width: 38, height: 24);
    _draw3DBox(
      canvas,
      baseRect: r,
      height3D: 12,
      topColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
      frontColors: const [Color(0xFFCA8A04), Color(0xFFA16207)],
      radius: 5,
    );
    final cord = Paint()
      ..color = const Color(0xFF78350F)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x - 8, r.top - 12), Offset(x - 8, r.bottom), cord);
    canvas.drawLine(Offset(x + 8, r.top - 12), Offset(x + 8, r.bottom), cord);
  }

  void _draw3DCow(Canvas canvas, double x, double y, {FarmHarvestSpot? spot}) {
    final idx = spot?.index ?? 0;
    final tailSwing = sin(engine.worldTime * 6.5 + idx * 2.3) * 5.0;
    final headGraze = sin(engine.worldTime * 3.0 + idx * 1.7) * 3.5;
    final popAnim = spot?.justProducedTimer ?? 0.0;

    // Süt dolumu tamamlandığında / teker teker süt üretirken genişleyen 3D süt halkası efekti
    if (popAnim > 0.01) {
      final ringRadius = 22.0 + (1.0 - popAnim) * 20.0;
      canvas.drawCircle(
        Offset(x, y),
        ringRadius,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: popAnim * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8,
      );
    }

    // 3D Yumuşak Yer Gölgesi (Blur filtresiz)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 3, y + 16), width: 52, height: 22),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );

    // Sallanan 3D Kuyruk
    canvas.drawLine(
      Offset(x - 20, y - 4),
      Offset(x - 27, y + 6 + tailSwing),
      Paint()
        ..color = const Color(0xFF1E293B)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // 4 Bacak & Toynaklar
    final legPaint = Paint()..color = const Color(0xFFE2E8F0);
    final hoofPaint = Paint()..color = const Color(0xFF1E293B);
    for (final lx in [-14.0, -7.0, 7.0, 13.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + lx, y + 3, 5, 13), const Radius.circular(2)), legPaint);
      canvas.drawRect(Rect.fromLTWH(x + lx, y + 13, 5, 3), hoofPaint);
    }

    // Pembe Meme (Süt doldukça büyür!)
    final milkRatio = (spot == null || spot.isReady)
        ? 1.0
        : (spot.regrowTimer / spot.regrowDuration).clamp(0.2, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x - 2, y + 8), width: 9 + 5 * milkRatio, height: 6 + 4 * milkRatio),
      Paint()..color = const Color(0xFFF472B6),
    );

    // 3D Beyaz Gövde (Silindirik Hacimli Gölgelendirme)
    final bodyRect = Rect.fromCenter(center: Offset(x, y - 2), width: 42, height: 26);
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFCBD5E1), Color(0xFF94A3B8)],
        stops: [0.0, 0.45, 0.8, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bodyRect);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)), bodyPaint);

    // Siyah Alaca Benekler
    final spotPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawCircle(Offset(x - 8, y - 5), 6.5, spotPaint);
    canvas.drawCircle(Offset(x + 6, y + 1), 5.5, spotPaint);
    canvas.drawCircle(Offset(x - 1, y + 4), 3.8, spotPaint);

    // Kafa, Kulaklar, Boynuzlar ve Pembe Burun (Otlarken aşağı-yukarı hareket eder)
    final headCenter = Offset(x + 21, y - 6 + headGraze);
    canvas.drawCircle(headCenter.translate(2, 4), 10.5, Paint()..color = Colors.black26);
    canvas.drawCircle(
      headCenter,
      10.5,
      Paint()
        ..shader = RadialGradient(
          colors: const [Colors.white, Color(0xFFCBD5E1)],
          center: const Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: headCenter, radius: 10.5)),
    );
    canvas.drawCircle(Offset(headCenter.dx - 4, headCenter.dy - 9), 3.4, Paint()..color = const Color(0xFFFEF3C7));
    canvas.drawCircle(Offset(headCenter.dx + 4, headCenter.dy - 9), 3.4, Paint()..color = const Color(0xFFFEF3C7));
    canvas.drawOval(Rect.fromCenter(center: Offset(headCenter.dx + 7, headCenter.dy + 1), width: 10, height: 11), Paint()..color = const Color(0xFFF472B6));
    canvas.drawCircle(Offset(headCenter.dx + 1.5, headCenter.dy - 2.5), 1.8, spotPaint);

    // Ağzında otlama yaprağı (kafası eğildiğinde görünür)
    if (headGraze > 1.2) {
      canvas.drawLine(
        Offset(headCenter.dx + 11, headCenter.dy + 3),
        Offset(headCenter.dx + 16, headCenter.dy + 7),
        Paint()
          ..color = const Color(0xFF4ADE80)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Teker teker süt dolumu damla animasyonu
    if (popAnim > 0.01) {
      final dropY = y - 12 - (1.0 - popAnim) * 20.0;
      _drawText(canvas, '🥛✨', x, dropY, fontSize: 12);
    }
  }

  // 2.B 3D TAŞ YEL DEĞİRMENİ & MEYVE / SEBZE / BUĞDAY TARLALARI
  void _draw3DField(Canvas canvas, FarmProducer farm) {
    final rect = farm.rect;
    final hasWindmill = !farm.solidBuildingRect.isEmpty;

    if (farm.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(20)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5,
      );
    }

    _drawSoftShadow(canvas, rect, radius: 18, offsetX: 10, offsetY: 16, blur: 16, alpha: 0.45);

    // Sürülmüş 3D Bereketli Toprak Zemin (Elma Bahçesi için çimenli-topraklı bahçe zemini)
    final isOrchard = farm.primaryProduct == SimProductType.apple;
    final soilPaint = Paint()
      ..shader = LinearGradient(
        colors: isOrchard
            ? const [Color(0xFF166534), Color(0xFF3F6212), Color(0xFF365314)]
            : const [Color(0xFF78350F), Color(0xFF451A03), Color(0xFF290F02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), soilPaint);

    _draw3DWoodenFence(canvas, rect, gateMinX: farm.gateMinX, gateMaxX: farm.gateMaxX);

    // 3D Derin Toprak Karıkları
    final furrowShadow = Paint()
      ..color = isOrchard ? const Color(0xFF14532D) : const Color(0xFF140600)
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round;
    final furrowRidge = Paint()
      ..color = (isOrchard ? const Color(0xFF4ADE80) : const Color(0xFF92400E)).withValues(alpha: 0.45)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final furrowStartX = hasWindmill ? rect.left + 158 : rect.left + 26;
    for (int r = 0; r < 6; r++) {
      final fy = rect.top + 52.0 + (r * 35.0);
      if (fy < rect.bottom - 38) {
        canvas.drawLine(Offset(furrowStartX, fy), Offset(rect.right - 24, fy), furrowShadow);
        canvas.drawLine(Offset(furrowStartX, fy - 4), Offset(rect.right - 24, fy - 4), furrowRidge);
      }
    }

    // Tarla İçindeki 6 Hasat Parseli (Teker Teker Boy Atan ve Başaklanan Canlı Ekinler!)
    for (final spot in farm.spots) {
      final growth = spot.isReady ? 1.0 : (spot.regrowTimer / spot.regrowDuration).clamp(0.08, 0.98);
      final popAnim = spot.justProducedTimer;

      // Başaklanma / olgunlaşma halkası animasyonu
      if (popAnim > 0.01) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(spot.x, spot.y), width: 72 + (1 - popAnim) * 18, height: 42 + (1 - popAnim) * 12),
          Paint()
            ..color = const Color(0xFFFACC15).withValues(alpha: popAnim * 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      }

      // Her parselde 3x2 yoğun başak/fide/elma fidanı kümesi: her kök teker teker sırayla büyür!
      int plantOrder = 0;
      for (double dx = -30; dx <= 30; dx += 20) {
        for (double dy = -16; dy <= 16; dy += 32) {
          final wx = spot.x + dx;
          final fy = spot.y + dy;
          final individualSway = sin(engine.worldTime * 3.4 + spot.index * 1.3 + plantOrder * 0.9) * 3.2;

          // Her bir kök/başak teker teker boy atar
          final double stalkGrowth = spot.isReady
              ? 1.0
              : ((growth * 1.45) - (plantOrder * 0.09)).clamp(0.05, 1.0);
          plantOrder++;

          if (!spot.isReady && stalkGrowth < 0.85) {
            final h = 4.0 + (14.0 * stalkGrowth);
            canvas.drawLine(
              Offset(wx, fy + 3),
              Offset(wx + individualSway * 0.4, fy + 3 - h),
              Paint()
                ..color = Color.lerp(const Color(0xFF4ADE80), const Color(0xFFEAB308), stalkGrowth)!
                ..strokeWidth = 2.6
                ..strokeCap = StrokeCap.round,
            );
            if (stalkGrowth > 0.45) {
              canvas.drawOval(
                Rect.fromCenter(center: Offset(wx + individualSway * 0.4, fy + 2 - h), width: 6.5 * stalkGrowth, height: 10.0 * stalkGrowth),
                Paint()..color = const Color(0xFF86EFAC),
              );
            }
            continue;
          }

          if (spot.productType == SimProductType.tomato) {
            // 🍅 3D Domates Fidesi ve Teker Teker Kızaran Parlak Domatesler
            canvas.drawCircle(Offset(wx + 2, fy + 2), 11.0, Paint()..color = Colors.black38);
            canvas.drawCircle(Offset(wx + individualSway * 0.3, fy - 4), 11.0, Paint()..color = const Color(0xFF15803D));
            canvas.drawCircle(Offset(wx - 4 + individualSway * 0.3, fy - 6), 5.4, Paint()..color = const Color(0xFFEF4444));
            canvas.drawCircle(Offset(wx + 4 + individualSway * 0.3, fy - 2), 5.0, Paint()..color = const Color(0xFFDC2626));
            canvas.drawCircle(Offset(wx + individualSway * 0.3, fy - 9), 4.4, Paint()..color = const Color(0xFFF87171));
          } else if (spot.productType == SimProductType.pepper) {
            // 🌶️ 3D Köy Biberi Fidesi ve Sallanan Sivri Yeşil Biberler
            canvas.drawCircle(Offset(wx + 2, fy + 2), 10.5, Paint()..color = Colors.black38);
            canvas.drawCircle(Offset(wx + individualSway * 0.3, fy - 4), 10.5, Paint()..color = const Color(0xFF166534));
            canvas.drawOval(Rect.fromCenter(center: Offset(wx - 4 + individualSway * 0.3, fy - 5), width: 6.5, height: 12.5), Paint()..color = const Color(0xFF22C55E));
            canvas.drawOval(Rect.fromCenter(center: Offset(wx + 4 + individualSway * 0.3, fy - 2), width: 6.5, height: 12.5), Paint()..color = const Color(0xFF4ADE80));
          } else if (spot.productType == SimProductType.apple) {
            // 🍎 3D Bodur Elma Ağacı / Fidanı ve Dalındaki Kırmızı Amasya Elmaları
            canvas.drawOval(Rect.fromCenter(center: Offset(wx + 2, fy + 4), width: 22, height: 10), Paint()..color = Colors.black38);
            canvas.drawLine(
              Offset(wx, fy + 4),
              Offset(wx, fy - 6),
              Paint()
                ..color = const Color(0xFF78350F)
                ..strokeWidth = 3.5,
            );
            canvas.drawCircle(Offset(wx + individualSway * 0.4, fy - 11), 11.5, Paint()..color = const Color(0xFF15803D));
            canvas.drawCircle(Offset(wx - 4 + individualSway * 0.4, fy - 14), 8.0, Paint()..color = const Color(0xFF22C55E));
            canvas.drawCircle(Offset(wx - 4 + individualSway * 0.4, fy - 12), 4.2, Paint()..color = const Color(0xFFDC2626));
            canvas.drawCircle(Offset(wx + 5 + individualSway * 0.4, fy - 9), 4.2, Paint()..color = const Color(0xFFEF4444));
          } else {
            // 🌾🥖 3D Altın Buğday Başakları (Her başak rüzgarda ayrı ayrı dalgalanır)
            final bounceY = popAnim > 0.01 ? sin(popAnim * pi) * 4.5 : 0.0;
            canvas.drawLine(
              Offset(wx, fy + 4),
              Offset(wx + individualSway, fy - 16 - bounceY),
              Paint()
                ..color = const Color(0xFFCA8A04)
                ..strokeWidth = 2.6,
            );
            canvas.drawOval(
              Rect.fromCenter(center: Offset(wx + individualSway, fy - 16 - bounceY), width: 9.5, height: 16),
              Paint()
                ..shader = const LinearGradient(
                  colors: [Color(0xFFFEF08A), Color(0xFFEAB308), Color(0xFFA16207)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(Rect.fromCenter(center: Offset(wx + individualSway, fy - 16 - bounceY), width: 9.5, height: 16)),
            );
          }
        }
      }

      String readyText = '🌾 CUT WITH SCYTHE';
      Color badgeColor = const Color(0xFFD97706);
      if (spot.productType == SimProductType.tomato) {
        readyText = '🍅 PICK TOMATOES';
        badgeColor = const Color(0xFFDC2626);
      } else if (spot.productType == SimProductType.pepper) {
        readyText = '🌶️ PICK PEPPERS';
        badgeColor = const Color(0xFF16A34A);
      } else if (spot.productType == SimProductType.apple) {
        readyText = '🍎 PICK APPLES';
        badgeColor = const Color(0xFFEA580C);
      } else if (spot.productType == SimProductType.bread) {
        readyText = '🥖 CUT WHEAT';
        badgeColor = const Color(0xFFB45309);
      }

      _drawSpotStatusBadge(
        canvas,
        spot: spot,
        readyLabel: readyText,
        activeLabel: '🌾 Harvesting',
        accentColor: badgeColor,
        offsetY: -34,
      );
    }

    if (hasWindmill) {
      // Sol Tarafta 3D DÖNER KANATLI YÜKSEK TAŞ YEL DEĞİRMENİ (Windmill)
      final millX = rect.left + 84;
      final millY = rect.top + 150;
      _drawSoftShadow(canvas, Rect.fromCircle(center: Offset(millX, millY), radius: 46), radius: 46, offsetX: 12, offsetY: 18, blur: 14, alpha: 0.5);

      final towerRect = Rect.fromCenter(center: Offset(millX, millY - 12), width: 84, height: 96);
      canvas.drawRRect(
        RRect.fromRectAndRadius(towerRect, const Radius.circular(42)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFF5F5F4), Color(0xFFA8A29E), Color(0xFF57534E), Color(0xFF292524)],
            stops: [0.0, 0.35, 0.75, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(towerRect),
      );

      final roofCenter = Offset(millX, millY - 28);
      canvas.drawCircle(
        roofCenter,
        32,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0xFFB45309), Color(0xFF78350F), Color(0xFF451A03)],
            center: const Alignment(-0.3, -0.3),
          ).createShader(Rect.fromCircle(center: roofCenter, radius: 32)),
      );

      // Dönen Kanatların Zemine Düşen Dinamik Gölgesi
      canvas.save();
      canvas.translate(millX + 14, millY + 10);
      canvas.rotate(engine.worldTime * 1.4);
      final bladeShadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.20);
      for (int b = 0; b < 4; b++) {
        canvas.rotate(pi / 2);
        canvas.drawRect(const Rect.fromLTWH(-3, -62, 16, 48), bladeShadowPaint);
      }
      canvas.restore();

      // Dönen 4 Kanatlı 3D Yel Değirmeni Pervanesi
      canvas.save();
      canvas.translate(roofCenter.dx, roofCenter.dy);
      canvas.rotate(engine.worldTime * 1.4);
      final bladePaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFDE68A)],
        ).createShader(const Rect.fromLTWH(0, -64, 18, 48));
      final framePaint = Paint()
        ..color = const Color(0xFF78350F)
        ..strokeWidth = 3.5;
      for (int b = 0; b < 4; b++) {
        canvas.rotate(pi / 2);
        canvas.drawLine(const Offset(0, 0), const Offset(0, -64), framePaint);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2, -60, 16, 46), const Radius.circular(3)), bladePaint);
        for (double gy = -54; gy < -18; gy += 9) {
          canvas.drawLine(Offset(2, gy), Offset(18, gy), Paint()..color = const Color(0xFFB45309)..strokeWidth = 1.2);
        }
      }
      canvas.restore();
      canvas.drawCircle(roofCenter, 7.5, Paint()..color = const Color(0xFF451A03));
      canvas.drawCircle(roofCenter, 3.5, Paint()..color = const Color(0xFFD97706));
    }

    final def = productCatalog[farm.primaryProduct]!;
    _drawFarmHeaderAndStatus(
      canvas,
      farm,
      '${def.emoji} ${farm.name.toUpperCase()}',
      def.primaryColor,
    );
  }

  // 2.C 3D TAVUK ÇİFTLİĞİ & KÜMES (İçeri Girip Kova ile Folluklardan Yumurta Toplama!)
  void _draw3DChickenCoop(Canvas canvas, FarmProducer farm) {
    final rect = farm.rect;

    if (farm.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(20)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5,
      );
    }

    _drawSoftShadow(canvas, rect, radius: 18, offsetX: 10, offsetY: 16, blur: 16, alpha: 0.45);

    final coopGround = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFB45309)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), coopGround);

    _draw3DWoodenFence(canvas, rect, gateMinX: farm.gateMinX, gateMaxX: farm.gateMaxX);

    // 3D Yükseltilmiş Ahşap Tavuk Kümesi Evi (Sağ Yarıda)
    final coopBase = Rect.fromLTWH(rect.right - 180, rect.top + 48, 154, rect.height - 96);
    _draw3DBox(
      canvas,
      baseRect: coopBase,
      height3D: 36,
      topColors: const [Color(0xFFD97706), Color(0xFFB45309), Color(0xFF78350F)],
      frontColors: const [Color(0xFF92400E), Color(0xFF78350F), Color(0xFF451A03)],
      sideColor: const Color(0xFF451A03),
      radius: 10,
      borderColor: const Color(0xFFFDE68A).withValues(alpha: 0.5),
    );

    // Kümes 3D Giriş Rampası (Basamaklı)
    final rampRect = Rect.fromLTWH(coopBase.left - 38, coopBase.center.dy - 22, 42, 26);
    canvas.drawRRect(RRect.fromRectAndRadius(rampRect.translate(2, 5), const Radius.circular(4)), Paint()..color = Colors.black38);
    canvas.drawRRect(RRect.fromRectAndRadius(rampRect, const Radius.circular(4)), Paint()..color = const Color(0xFFD97706));
    for (double rx = rampRect.left + 7; rx < rampRect.right - 4; rx += 9) {
      canvas.drawLine(Offset(rx, rampRect.top + 2), Offset(rx, rampRect.bottom - 2), Paint()..color = const Color(0xFF78350F)..strokeWidth = 2);
    }

    // 3D Yemlik ve Parlak Su Kabı
    _draw3DBox(
      canvas,
      baseRect: Rect.fromLTWH(rect.left + 26, rect.top + 48, 72, 22),
      height3D: 10,
      topColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
      frontColors: const [Color(0xFF92400E), Color(0xFF451A03)],
      radius: 6,
    );
    final drinkerCenter = Offset(rect.left + 218, rect.top + 56);
    canvas.drawCircle(drinkerCenter.translate(3, 5), 15, Paint()..color = Colors.black26);
    canvas.drawCircle(drinkerCenter, 15, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(drinkerCenter, 11, Paint()..color = const Color(0xFF38BDF8));

    // İçerideki 4 Ayrı Saman Folluk ve Teker Teker Yumurtlayan Canlı Tavuklar!
    for (int i = 0; i < farm.spots.length; i++) {
      final spot = farm.spots[i];
      final eggRatio = spot.isReady ? 1.0 : (spot.regrowTimer / spot.regrowDuration).clamp(0.0, 1.0);
      // Yuvadaki yumurta sayısı 1 -> 2 -> 3 şeklinde teker teker artar!
      final int visibleEggCount = spot.isReady ? 3 : (eggRatio * 3).floor();

      _draw3DEggNest(canvas, spot.x, spot.y, eggCount: visibleEggCount);

      // Her tavuğun kendine ait bağımsız gezinme ve yumurtlama animasyonu vardır
      final layAnim = spot.justProducedTimer; // 1.0 -> 0.0 yumurtlama anı!
      final phase = engine.worldTime * 4.2 + (i * 2.1);

      double henX;
      double henY;
      bool isLayingNow = layAnim > 0.05;

      if (isLayingNow) {
        // Yumurtlarken folluğun hemen üstüne zıplar ve altında taze yumurta (🥚) yuvarlanarak folluğa düşer!
        final jump = sin(layAnim * pi) * 9.0;
        henX = spot.x - 6;
        henY = spot.y - 12 - jump;

        // Tavuğun altından folluğun içine düşen taze 3D yumurta animasyonu!
        final dropProgress = (1.0 - layAnim).clamp(0.0, 1.0);
        final eggX = Offset.lerp(Offset(henX + 4, henY + 8), Offset(spot.x, spot.y - 2), dropProgress)!.dx;
        final eggY = Offset.lerp(Offset(henX + 4, henY + 8), Offset(spot.x, spot.y - 2), dropProgress)!.dy;

        canvas.drawCircle(
          Offset(spot.x, spot.y),
          16 + dropProgress * 12,
          Paint()
            ..color = const Color(0xFFFDE047).withValues(alpha: layAnim * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(eggX, eggY), width: 9.5, height: 12.5),
          Paint()..color = Colors.white,
        );
      } else {
        // Normal zamanda her tavuk kendi folluğunun etrafında ayrı ayrı yemlenir ve gezinir
        henX = spot.x - 24 + cos(phase * 0.6) * 7.0;
        henY = spot.y - 8 + sin(phase) * 3.5;
      }

      _draw3DChicken(canvas, henX, henY, index: i, isLaying: isLayingNow);

      _drawSpotStatusBadge(
        canvas,
        spot: spot,
        readyLabel: '🥚 COLLECT IN BUCKET',
        activeLabel: '🥚 Collecting',
        accentColor: const Color(0xFFF59E0B),
        offsetY: -30,
      );
    }

    _drawFarmHeaderAndStatus(canvas, farm, '🐔 COOP (🧺 TAKE A BUCKET & GO INSIDE TO COLLECT EGGS)', const Color(0xFFF59E0B));
  }

  void _draw3DEggNest(Canvas canvas, double x, double y, {required int eggCount}) {
    // 3D Saman Folluk Yuvası
    canvas.drawOval(Rect.fromCenter(center: Offset(x + 2, y + 6), width: 38, height: 22), Paint()..color = Colors.black38);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y + 2), width: 36, height: 20),
      Paint()..color = const Color(0xFFB45309),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: 30, height: 15),
      Paint()..color = const Color(0xFFFDE047),
    );
    if (eggCount > 0) {
      // Folluk içindeki taze 3D köy yumurtaları (teker teker 1, 2, 3 adet görünür)
      const eggOffsets = [Offset(-6, -1), Offset(5, -1), Offset(0, -4)];
      for (int e = 0; e < min(eggCount, eggOffsets.length); e++) {
        final off = eggOffsets[e];
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x + off.dx, y + off.dy), width: 8.5, height: 11),
          Paint()
            ..shader = const RadialGradient(
              colors: [Colors.white, Color(0xFFFEF3C7), Color(0xFFF59E0B)],
              center: Alignment(-0.3, -0.3),
            ).createShader(Rect.fromCenter(center: Offset(x + off.dx, y + off.dy), width: 8.5, height: 11)),
        );
      }
    }
  }

  void _drawSpotStatusBadge(
    Canvas canvas, {
    required FarmHarvestSpot spot,
    required String readyLabel,
    required String activeLabel,
    required Color accentColor,
    required double offsetY,
  }) {
    final bx = spot.x;
    final by = spot.y + offsetY;

    if (spot.harvestProgress > 0.01) {
      // Aktif tırpanla biçme / süt sağma / yumurta toplama ilerleme çubuğu
      final barRect = Rect.fromCenter(center: Offset(bx, by), width: 88, height: 18);
      canvas.drawRRect(RRect.fromRectAndRadius(barRect.translate(0, 2), const Radius.circular(9)), Paint()..color = Colors.black54);
      canvas.drawRRect(RRect.fromRectAndRadius(barRect, const Radius.circular(9)), Paint()..color = const Color(0xFF0F172A));
      final fillW = (barRect.width - 4) * spot.harvestProgress.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(barRect.left + 2, barRect.top + 2, fillW, barRect.height - 4), const Radius.circular(7)),
        Paint()..color = const Color(0xFF22C55E),
      );
      _drawText(canvas, '$activeLabel %${(spot.harvestProgress * 100).toInt()}', bx, by, fontSize: 8.5, color: Colors.white, isBold: true);
    } else if (spot.isReady) {
      final bob = sin(engine.worldTime * 4.0 + spot.index) * 2.2;
      final pill = Rect.fromCenter(center: Offset(bx, by + bob), width: 76, height: 16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(8)),
        Paint()..color = accentColor.withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(8)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      _drawText(canvas, readyLabel, bx, by + bob, fontSize: 8.0, color: Colors.white, isBold: true);
    } else {
      final ratio = (spot.regrowTimer / spot.regrowDuration).clamp(0.0, 1.0);
      final pill = Rect.fromCenter(center: Offset(bx, by), width: 56, height: 13);
      canvas.drawRRect(RRect.fromRectAndRadius(pill, const Radius.circular(6)), Paint()..color = Colors.black54);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(pill.left + 2, pill.top + 2, (pill.width - 4) * ratio, pill.height - 4), const Radius.circular(5)),
        Paint()..color = Colors.amberAccent,
      );
    }
  }

  void _draw3DChicken(Canvas canvas, double x, double y, {int index = 0, bool isLaying = false}) {
    final peck = isLaying ? 0.0 : sin(engine.worldTime * 7.0 + index * 2.4) * 2.5;
    final wingFlap = isLaying ? sin(engine.worldTime * 22.0) * 4.0 : 0.0;

    canvas.drawOval(Rect.fromCenter(center: Offset(x + 2, y + 9), width: 24, height: 11), Paint()..color = Colors.black38);
    final bodyRect = Rect.fromCenter(center: Offset(x, y), width: 22, height: 17);
    canvas.drawOval(
      bodyRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
          center: Alignment(-0.3, -0.3),
        ).createShader(bodyRect),
    );
    // Çırpınan Yan Kanat
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x - 2, y - 1 - wingFlap), width: 12, height: 8),
      Paint()..color = const Color(0xFFF1F5F9),
    );
    canvas.drawCircle(Offset(x + 8, y - 6 + peck), 6.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x + 8, y - 12.5 + peck), 4.0, Paint()..color = const Color(0xFFEF4444)); // Kırmızı İbik
    canvas.drawCircle(Offset(x + 14, y - 5 + peck), 3.0, Paint()..color = const Color(0xFFF59E0B)); // Sarı Gaga
    canvas.drawCircle(Offset(x + 9.5, y - 7 + peck), 1.4, Paint()..color = Colors.black); // Göz
  }

  void _draw3DWoodenFence(Canvas canvas, Rect rect, {double? gateMinX, double? gateMaxX}) {
    final railPaint = Paint()
      ..color = const Color(0xFF92400E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5;

    // Sol, Alt ve Sağ Çit Kenarları
    canvas.drawLine(Offset(rect.left, rect.top + 12), Offset(rect.left, rect.bottom - 12), railPaint);
    canvas.drawLine(Offset(rect.right, rect.top + 12), Offset(rect.right, rect.bottom - 12), railPaint);
    canvas.drawLine(Offset(rect.left + 12, rect.bottom), Offset(rect.right - 12, rect.bottom), railPaint);

    // Üst Çit Kenarı (Açık Giriş Kapısı Boşluğu Bırakır!)
    if (gateMinX != null && gateMaxX != null) {
      canvas.drawLine(Offset(rect.left + 12, rect.top), Offset(gateMinX, rect.top), railPaint);
      canvas.drawLine(Offset(gateMaxX, rect.top), Offset(rect.right - 12, rect.top), railPaint);

      // Giriş Kapısı Kemer Direkleri
      for (final gx in [gateMinX, gateMaxX]) {
        canvas.drawCircle(Offset(gx + 2, rect.top + 3), 8.0, Paint()..color = Colors.black45);
        canvas.drawCircle(Offset(gx, rect.top - 2), 8.0, Paint()..color = const Color(0xFF451A03));
        canvas.drawCircle(Offset(gx - 1, rect.top - 3), 4.0, Paint()..color = const Color(0xFFF59E0B));
      }
    } else {
      canvas.drawLine(Offset(rect.left + 12, rect.top), Offset(rect.right - 12, rect.top), railPaint);
    }

    for (double px = rect.left + 12; px < rect.right; px += 46) {
      if (gateMinX != null && gateMaxX != null && px > gateMinX - 8 && px < gateMaxX + 8) {
        // Üst kapı boşluğuna direk koyma
      } else {
        canvas.drawCircle(Offset(px + 2, rect.top + 3), 6.0, Paint()..color = Colors.black38);
        canvas.drawCircle(Offset(px, rect.top - 2), 6.0, Paint()..color = const Color(0xFF78350F));
        canvas.drawCircle(Offset(px - 1, rect.top - 3), 2.5, Paint()..color = const Color(0xFFD97706));
      }

      canvas.drawCircle(Offset(px + 2, rect.bottom + 3), 6.0, Paint()..color = Colors.black38);
      canvas.drawCircle(Offset(px, rect.bottom - 2), 6.0, Paint()..color = const Color(0xFF78350F));
      canvas.drawCircle(Offset(px - 1, rect.bottom - 3), 2.5, Paint()..color = const Color(0xFFD97706));
    }
  }

  void _drawFarmHeaderAndStatus(Canvas canvas, FarmProducer farm, String title, Color color) {
    final rect = farm.rect;

    // Tabela sol üstte kapıyı kapatmayacak şekilde konumlanır
    final headerRect = Rect.fromLTWH(rect.left + 14, rect.top - 12, (farm.gateMinX - rect.left - 24).clamp(180.0, rect.width - 32), 26);
    _draw3DBox(
      canvas,
      baseRect: headerRect,
      height3D: 6,
      topColors: [color, color.withValues(alpha: 0.85)],
      frontColors: [const Color(0xFF0F172A), const Color(0xFF1E293B)],
      radius: 7,
      borderColor: Colors.white,
    );
    _drawText(canvas, title, headerRect.center.dx, headerRect.center.dy - 6, fontSize: 9.0, color: Colors.white, isBold: true);

    final bottomBar = Rect.fromLTWH(rect.left + 16, rect.bottom - 34, rect.width - 32, 26);
    canvas.drawRRect(RRect.fromRectAndRadius(bottomBar.translate(0, 3), const Radius.circular(8)), Paint()..color = Colors.black45);
    canvas.drawRRect(RRect.fromRectAndRadius(bottomBar, const Radius.circular(8)), Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.92));

    final readyCount = farm.readySpotCount;
    final totalCount = farm.spots.length;
    final ratio = (readyCount / totalCount).clamp(0.0, 1.0);
    if (ratio > 0) {
      final fillRect = Rect.fromLTWH(bottomBar.left + 3, bottomBar.top + 3, (bottomBar.width - 6) * ratio, bottomBar.height - 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(6)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF15803D), Color(0xFF166534)],
          ).createShader(fillRect),
      );
    }

    String statusText;
    final def = productCatalog[farm.primaryProduct]!;
    if (readyCount > 0) {
      if (farm.zoneType == FarmZoneType.barn) {
        statusText = '🧺 TAKE A MILK BUCKET AT THE ENTRANCE & GO INSIDE TO MILK THE COWS (${readyCount}/${totalCount} Ready)';
      } else if (farm.zoneType == FarmZoneType.field) {
        statusText = '🌾 TAKE A SCYTHE & GO INSIDE TO HARVEST ${def.emoji} ${def.name.toUpperCase()} (${readyCount}/${totalCount} Ready)';
      } else {
        statusText = '🧺 TAKE AN EGG BUCKET AT THE ENTRANCE & COLLECT EGGS IN THE COOP (${readyCount}/${totalCount} Ready)';
      }
    } else {
      statusText = '⏳ NEW ${def.emoji} ${def.name.toUpperCase()} GROWING...';
    }
    final statusColor = readyCount > 0 ? const Color(0xFF4ADE80) : Colors.amberAccent;
    _drawText(canvas, statusText, rect.center.dx, bottomBar.center.dy, fontSize: 9.2, color: statusColor, isBold: true);
  }

  // =========================================================================
  // 3. LOJİSTİK KAMYONU (GERÇEKÇİ 3D DORSE, KABİN & FAR HÜZMELERİ)
  // =========================================================================
  void _drawTruck(Canvas canvas) {
    if (!engine.isTruckArriving && engine.truckX <= -260) return;

    final x = engine.truckX;
    const y = 38.0;

    // Far Işık Hüzmeleri
    final beamPath = Path()
      ..moveTo(x + 230, y + 18)
      ..lineTo(x + 360, y - 10)
      ..lineTo(x + 360, y + 85)
      ..lineTo(x + 230, y + 58)
      ..close();
    canvas.drawPath(
      beamPath,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFFFEF08A).withValues(alpha: 0.45), Colors.transparent],
        ).createShader(Rect.fromLTWH(x + 230, y - 10, 130, 95)),
    );

    // 3D Tekerlekler
    for (final wx in [x + 28, x + 125, x + 195]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(wx, y + 66), width: 26, height: 12), const Radius.circular(4)),
        Paint()..color = const Color(0xFF090D16),
      );
    }

    // 3D Kargo Dorsesi
    final dorseRect = Rect.fromLTWH(x, y, 168, 66);
    _draw3DBox(
      canvas,
      baseRect: dorseRect,
      height3D: 22,
      topColors: const [Color(0xFF60A5FA), Color(0xFF2563EB), Color(0xFF1D4ED8)],
      frontColors: const [Color(0xFF1E40AF), Color(0xFF172554)],
      radius: 8,
      borderColor: Colors.white54,
    );

    // 3D Çekici Kabini
    final cabRect = Rect.fromLTWH(x + 168, y + 8, 64, 56);
    _draw3DBox(
      canvas,
      baseRect: cabRect,
      height3D: 18,
      topColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
      frontColors: const [Color(0xFFC2410C), Color(0xFF7C2D12)],
      radius: 10,
    );

    // Ön Cam
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x + 202, y - 4, 24, 34), const Radius.circular(5)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(x + 202, y - 4, 24, 34)),
    );

    _drawText(canvas, '🚚 DELIVERY TRUCK', x + 84, y + 12, fontSize: 11, color: Colors.white, isBold: true);
  }

  // =========================================================================
  // 3.B 🛵 3D HIZLI KURYE DURAĞI & PAKET SERVİS MOTOSİKLETİ
  // =========================================================================
  void _drawCourierStationAndBike(Canvas canvas) {
    final station = engine.courierStation;

    if (engine.isCourierHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(station.inflate(8), const Radius.circular(16)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    // Kaldırım Üzeri 3D Kurye Park Platformu & Sarı-Siyah Şeritli Alan
    _drawSoftShadow(canvas, station, radius: 12, offsetX: 5, offsetY: 8, blur: 10, alpha: 0.38);
    final bayPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(station);
    canvas.drawRRect(RRect.fromRectAndRadius(station, const Radius.circular(12)), bayPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(station.deflate(3), const Radius.circular(10)),
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _drawText(canvas, '🛵 EXPRESS COURIER PARKING', station.center.dx, station.bottom - 14, fontSize: 10, color: const Color(0xFFFDE047), isBold: true);

    // Eğer Kurye Motoru Sahnedeyse 3D Motosiklet + Kasklı Sürücü Çiz
    if (engine.courierState != CourierState.away) {
      final bx = engine.courierX;
      const by = 166.0;
      final bounce = sin(engine.worldTime * 16.0) * 1.2;

      // Far Işık Hüzmesi (Sola Doğru)
      final beamPath = Path()
        ..moveTo(bx - 36, by - 4)
        ..lineTo(bx - 125, by - 26)
        ..lineTo(bx - 125, by + 24)
        ..lineTo(bx - 36, by + 10)
        ..close();
      canvas.drawPath(
        beamPath,
        Paint()
          ..shader = LinearGradient(
            colors: [const Color(0xFFFEF08A).withValues(alpha: 0.45), Colors.transparent],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ).createShader(Rect.fromLTWH(bx - 125, by - 26, 90, 50)),
      );

      // Motosiklet 3D Gölgesi (Blur filtresiz)
      canvas.drawOval(
        Rect.fromCenter(center: Offset(bx + 4, by + 18), width: 92, height: 24),
        Paint()..color = Colors.black.withValues(alpha: 0.34),
      );

      // Ön ve Arka 3D Tekerlekler
      for (final wx in [bx - 26.0, bx + 26.0]) {
        canvas.drawCircle(Offset(wx, by + 10), 12, Paint()..color = const Color(0xFF090D16));
        canvas.drawCircle(Offset(wx, by + 10), 6, Paint()..color = const Color(0xFF94A3B8));
      }

      // Scooter 3D Gövdesi (Parlak Mor/Sarı Getir-Tarzı Kurye Motoru)
      final scooterBody = Rect.fromCenter(center: Offset(bx, by + 2 + bounce), width: 58, height: 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(scooterBody, const Radius.circular(10)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF5B21B6), Color(0xFF3B0764)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(scooterBody),
      );

      // Arka 3D Termal Kurye Çantası (Sarı/Turuncu)
      final bagRect = Rect.fromCenter(center: Offset(bx + 22, by - 8 + bounce), width: 30, height: 24);
      _draw3DBox(
        canvas,
        baseRect: bagRect,
        height3D: 12,
        topColors: const [Color(0xFFFACC15), Color(0xFFEAB308)],
        frontColors: const [Color(0xFFCA8A04), Color(0xFFA16207)],
        radius: 5,
        castShadow: false,
      );
      _drawText(canvas, '⚡', bx + 22, by - 14 + bounce, fontSize: 11, isBold: true);

      // Kasklı 3D Kurye Sürücüsü
      final riderX = bx - 4;
      final riderY = by - 14 + bounce;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(riderX, riderY + 4), width: 18, height: 20), const Radius.circular(6)),
        Paint()..color = const Color(0xFF6D28D9),
      );
      // 3D Parlak Sarı Kask ve Vizör
      canvas.drawCircle(
        Offset(riderX, riderY - 10),
        10.5,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFEF08A), Color(0xFFFACC15), Color(0xFFCA8A04)],
            center: Alignment(-0.3, -0.3),
          ).createShader(Rect.fromCircle(center: Offset(riderX, riderY - 10), radius: 10.5)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(riderX - 5, riderY - 10), width: 9, height: 6), const Radius.circular(3)),
        Paint()..color = const Color(0xFF0F172A),
      );

      // Aktif Kurye Siparişi Balonu (Üstte 3D Kart)
      if (engine.courierState == CourierState.waitingForOrder && engine.activeCourierOrder != null) {
        final ord = engine.activeCourierOrder!;
        final def = productCatalog[ord.productType]!;
        final cardRect = Rect.fromCenter(center: Offset(station.center.dx, station.top - 34), width: 230, height: 48);

        _drawSoftShadow(canvas, cardRect, radius: 12, offsetX: 3, offsetY: 6, blur: 8, alpha: 0.45);
        canvas.drawRRect(
          RRect.fromRectAndRadius(cardRect, const Radius.circular(12)),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFF4C1D95), Color(0xFF1E1B4B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(cardRect),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cardRect, const Radius.circular(12)),
          Paint()
            ..color = const Color(0xFFFACC15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );

        final hasReadyPack = engine.carriedBox != null &&
            engine.carriedBox!.isCourierPackage &&
            engine.carriedBox!.productType == ord.productType;
        _drawText(
          canvas,
          '🛵 URGENT ORDER: ${ord.deliveredQty}/${ord.requiredQty} ${def.emoji} ${def.name}',
          cardRect.center.dx,
          cardRect.top + 15,
          fontSize: 10.8,
          color: Colors.white,
          isBold: true,
        );
        _drawText(
          canvas,
          hasReadyPack
              ? '✅ 📦 Deliver Courier Package (+\$${ord.rewardAmount.toStringAsFixed(0)}) [CLICK]'
              : '📦 Pack & Bring First • +\$${ord.rewardAmount.toStringAsFixed(0)} (${ord.remainingTime.toInt()}s) [CLICK]',
          cardRect.center.dx,
          cardRect.bottom - 13,
          fontSize: 9.4,
          color: hasReadyPack ? const Color(0xFF4ADE80) : const Color(0xFFFDE047),
          isBold: true,
        );
      }
    }
  }

  // =========================================================================
  // 4. YERDEKİ 3D TAHTA PALETLER & KARGO KOLİLERİ
  // =========================================================================
  void _drawDeliveryBoxes(Canvas canvas) {
    for (var box in engine.deliveryBoxes) {
      final x = box.x;
      final y = box.y;

      if (box.isHovered) {
        canvas.drawCircle(
          Offset(x, y),
          38,
          Paint()
            ..color = Colors.amberAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5,
        );
      }

      // 3D Ahşap Palet Altlığı
      final palletRect = Rect.fromCenter(center: Offset(x, y + 16), width: 60, height: 16);
      _drawSoftShadow(canvas, palletRect, radius: 4, offsetX: 5, offsetY: 7, blur: 6, alpha: 0.4);
      canvas.drawRRect(RRect.fromRectAndRadius(palletRect, const Radius.circular(3)), Paint()..color = const Color(0xFF78350F));

      // 3D Karton Koli Prizi
      final boxBase = Rect.fromCenter(center: Offset(x, y + 8), width: 52, height: 28);
      _draw3DBox(
        canvas,
        baseRect: boxBase,
        height3D: 18,
        topColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
        frontColors: const [Color(0xFFB45309), Color(0xFF78350F)],
        sideColor: const Color(0xFF451A03),
        radius: 5,
        castShadow: false,
      );

      // Koli Üst Bant Şeridi
      canvas.drawLine(
        Offset(x - 24, y - 10),
        Offset(x + 24, y - 10),
        Paint()
          ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.7)
          ..strokeWidth = 3.0,
      );

      final def = productCatalog[box.productType]!;
      _drawText(canvas, '${def.emoji} x${box.currentCount}', x, y - 2, fontSize: 11.5, isBold: true, color: Colors.white);
    }
  }

  // =========================================================================
  // 5. MAĞAZA MOBİLYALARI & GERÇEKÇİ 3D DERİNLİKLİ GONDOL RAFLAR
  // =========================================================================
  void _drawFurnitureAndShelves(Canvas canvas) {
    // Kilitli kasalar zeminde bilgi rozeti olarak çizilir (Açık 3D kasalar derinlik sıralamasında çizilir)
    for (int i = engine.unlockedCheckoutCount; i < engine.checkoutCounters.length; i++) {
      final cRect = engine.checkoutCounters[i];
      _drawLockedCheckoutZone(canvas, cRect, index: i + 1);
    }

    _draw3DTrashCan(canvas, engine.trashCan);

    // Kilitli reyonlar açılana kadar raf çizilmez; sadece zeminde "Burayı Aç" yazısı görünür!
    for (final shelf in engine.shelves) {
      if (!shelf.isUnlocked && engine.storeLevel >= shelf.zoneLevel) {
        _drawLockedShelf(canvas, shelf);
      }
    }
  }

  /// Roped-off, darkened parts of the store that are not bought yet.
  void _drawLockedExpansion(Canvas canvas) {
    const double top = 232;
    final double bottom = engine.worldHeight;
    final zones = <Rect>[
      if (engine.storeMinX > 95) Rect.fromLTRB(0, top, engine.storeMinX, bottom),
      if (engine.storeMaxX < engine.worldWidth - 95)
        Rect.fromLTRB(engine.storeMaxX, top, engine.worldWidth, bottom),
    ];
    if (zones.isEmpty) return;

    final nextCost = engine.nextLevelUpgradeCost.toStringAsFixed(0);
    for (final z in zones) {
      canvas.drawRect(z, Paint()..color = const Color(0xFF0B1020).withValues(alpha: 0.80));
      // Diagonal stripes
      final stripe = Paint()
        ..color = const Color(0xFFFBBF24).withValues(alpha: 0.07)
        ..strokeWidth = 14;
      canvas.save();
      canvas.clipRect(z);
      for (double k = -z.height; k < z.width + z.height; k += 46) {
        canvas.drawLine(Offset(z.left + k, z.top), Offset(z.left + k + z.height, z.bottom), stripe);
      }
      canvas.restore();
      // Rope edge
      final edgeX = z.left < 10 ? z.right : z.left;
      canvas.drawLine(
        Offset(edgeX, z.top),
        Offset(edgeX, z.bottom),
        Paint()
          ..color = const Color(0xFFFBBF24)
          ..strokeWidth = 4,
      );
      final cx = z.center.dx;
      final cy = (z.top + z.bottom) / 2;
      _drawText(canvas, '🔒 Locked Area', cx, cy - 16, fontSize: 15, color: Colors.white, isBold: true);
      if (engine.storeLevel < 3) {
        _drawText(canvas, 'Expand the store via 👔 Manager', cx, cy + 6, fontSize: 11, color: const Color(0xFFFDE68A), isBold: true);
        _drawText(canvas, '(\$$nextCost)', cx, cy + 22, fontSize: 11, color: const Color(0xFF4ADE80), isBold: true);
      }
    }
  }

  /// Henüz seviyesi gelmemiş (kilitli) 2. ve 3. kasalar için alanı boş bırakıp sadece zeminde şık yazı gösterir
  void _drawLockedCheckoutZone(Canvas canvas, Rect rect, {required int index}) {
    final center = rect.center;
    final pill = Rect.fromCenter(center: center, width: 174, height: 42);

    canvas.drawRRect(
      RRect.fromRectAndRadius(pill.translate(0, 2), const Radius.circular(12)),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(12)),
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.65),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(12)),
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    _drawText(
      canvas,
      '🔒 🛎️ Register ${index} Area',
      center.dx,
      center.dy - 7,
      fontSize: 10.2,
      color: Colors.white,
      isBold: true,
    );
    _drawText(
      canvas,
      '⭐ Unlocks at Store Level ${index}',
      center.dx,
      center.dy + 8,
      fontSize: 9.0,
      color: const Color(0xFF7DD3FC),
      isBold: true,
    );
  }

  void _drawSingleShelf3D(Canvas canvas, StoreShelf shelf) {
    if (!shelf.isUnlocked) return;

    if (shelf.assignedProduct == SimProductType.milk) {
      _draw3DMilkCoolerCabinet(canvas, shelf);
    } else if (shelf.assignedProduct == SimProductType.tomato ||
        shelf.assignedProduct == SimProductType.pepper ||
        shelf.assignedProduct == SimProductType.apple) {
      _draw3DFruitGreengrocerStand(canvas, shelf);
    } else {
      _draw3DRealisticGondolaShelf(canvas, shelf);
    }
  }

  void _drawLockedShelf(Canvas canvas, StoreShelf shelf) {
    final rect = shelf.rect;
    final def = productCatalog[shelf.assignedProduct]!;
    final bob = sin(engine.worldTime * 3.5 + rect.left * 0.01) * 2.5;
    final center = Offset(rect.center.dx, rect.center.dy + bob);

    // Açılmamış reyonlarda raf kesinlikle görünmez; sadece okunaklı kilit açma yazısı görünür
    final labelBg = Rect.fromCenter(center: center, width: 196, height: 48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelBg.translate(0, 3), const Radius.circular(14)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelBg, const Radius.circular(14)),
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: shelf.isHovered ? 0.92 : 0.78),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelBg, const Radius.circular(14)),
      Paint()
        ..color = const Color(0xFFFBBF24).withValues(alpha: shelf.isHovered ? 1.0 : 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shelf.isHovered ? 2.5 : 1.6,
    );

    _drawText(
      canvas,
      '${def.emoji} ${def.name}',
      center.dx,
      center.dy - 9,
      fontSize: 11.0,
      color: Colors.white,
      isBold: true,
    );
    _drawText(
      canvas,
      '🔒 ${engine.shelfLockReason(shelf)}',
      center.dx,
      center.dy + 9,
      fontSize: 10.2,
      color: const Color(0xFFFDE047),
      isBold: true,
    );
  }

  // 5.A TAM 3 BOYUTLU, İÇ DERİNLİĞİ & ÇIKINTILI RAF TABLALARI GÖRÜNEN SÜPERMARKET GONDOL REYONU
  void _draw3DRealisticGondolaShelf(Canvas canvas, StoreShelf shelf) {
    final rect = shelf.rect;
    final def = productCatalog[shelf.assignedProduct]!;

    const double height3D = 44.0;
    const double sideDepthX = 20.0;
    const double sideDepthY = 14.0;

    if (shelf.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(18)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    // 1. Derin 3D Zemin Gölgesi + Ambient Occlusion Temas Gölgesi
    _drawSoftShadow(
      canvas,
      rect,
      radius: 12,
      offsetX: sideDepthX + 7,
      offsetY: 22,
      blur: 18,
      alpha: 0.52,
    );

    final topFace = rect.translate(0, -height3D);

    // 2. Üst Tavan 3D Derinlik Yüzeyi (Arka Duvara Uzanan Üst Kalınlık)
    final roofDepthPath = Path()
      ..moveTo(topFace.left + 6, topFace.top)
      ..lineTo(topFace.right, topFace.top)
      ..lineTo(topFace.right + sideDepthX, topFace.top + sideDepthY)
      ..lineTo(topFace.left + sideDepthX, topFace.top + sideDepthY)
      ..close();
    canvas.drawPath(
      roofDepthPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF334155)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(topFace.left, topFace.top, topFace.width + sideDepthX, sideDepthY)),
    );

    // 3. Sağ 3D Yan Gövde Duvarı (Metal Kaburgalı & Perçinli Derinlik Yüzeyi)
    final rightSideWall = Path()
      ..moveTo(topFace.right, topFace.top)
      ..lineTo(topFace.right + sideDepthX, topFace.top + sideDepthY)
      ..lineTo(rect.right + sideDepthX, rect.bottom - 6)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(
      rightSideWall,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF334155), Color(0xFF1E293B), Color(0xFF090D16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(topFace.right, topFace.top, sideDepthX, rect.height + height3D)),
    );
    // Sağ yan duvar üzerindeki 3D yatay çelik destek profilleri
    for (double ry = topFace.top + 28; ry < rect.bottom - 16; ry += 34) {
      canvas.drawLine(
        Offset(topFace.right + 2, ry),
        Offset(topFace.right + sideDepthX - 2, ry + sideDepthY * 0.7),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..strokeWidth = 2.0,
      );
      canvas.drawLine(
        Offset(topFace.right + 2, ry + 2.5),
        Offset(topFace.right + sideDepthX - 2, ry + sideDepthY * 0.7 + 2.5),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.55)
          ..strokeWidth = 2.0,
      );
    }

    // 4. Alt 3D Baza & Tekmelik (Öne Doğru Çıkıntılı Ağır Metal Alt Tabla)
    final basePlinthRect = Rect.fromLTWH(rect.left - 2, rect.bottom - height3D, rect.width + 4, height3D);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        basePlinthRect,
        bottomLeft: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF475569), Color(0xFF1E293B), Color(0xFF090D16)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(basePlinthRect),
    );
    // Alt Baza Krom Tampon Şeridi & Havalandırma Izgarası
    canvas.drawLine(
      Offset(basePlinthRect.left + 8, basePlinthRect.top + 3),
      Offset(basePlinthRect.right - 8, basePlinthRect.top + 3),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 2.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(basePlinthRect.left + 12, basePlinthRect.top + 9, basePlinthRect.width - 24, 15),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF020617),
    );

    // 5. Ana Dış Çelik Çerçeve
    canvas.drawRRect(
      RRect.fromRectAndRadius(topFace, const Radius.circular(10)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(topFace),
    );

    // 6. DERİN İÇ OYUK (RECESSED 3D CAVITY: Sol İç Duvar, Üst İç Tavan ve Delikli Arka Pano)
    final cavity = Rect.fromLTWH(topFace.left + 8, topFace.top + 20, topFace.width - 16, topFace.height - 26);
    const double depthDX = 13.0; // İç duvarın sağ-arkaya doğru perspektif kayması
    const double depthDY = 10.0; // İç duvarın aşağı-arkaya doğru perspektif kayması

    // Arka Delikli Metal Panel (Pegboard Back Wall)
    canvas.drawRRect(
      RRect.fromRectAndRadius(cavity, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF090D16), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(cavity),
    );

    // Sol İç Yan Duvar (Perspektifli 3D İç Derinlik Yüzeyi - İçi Oyuk Hissini Veren Anahtar Katman!)
    final innerLeftWall = Path()
      ..moveTo(cavity.left, cavity.top)
      ..lineTo(cavity.left + depthDX, cavity.top + depthDY)
      ..lineTo(cavity.left + depthDX, cavity.bottom - 4)
      ..lineTo(cavity.left, cavity.bottom)
      ..close();
    canvas.drawPath(
      innerLeftWall,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF334155), Color(0xFF0F172A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(cavity.left, cavity.top, depthDX, cavity.height)),
    );

    // Üst İç Tavan Yüzeyi (Kanopi Altı Perspektif Tavanı)
    final innerCeiling = Path()
      ..moveTo(cavity.left, cavity.top)
      ..lineTo(cavity.right, cavity.top)
      ..lineTo(cavity.right - 3, cavity.top + depthDY)
      ..lineTo(cavity.left + depthDX, cavity.top + depthDY)
      ..close();
    canvas.drawPath(
      innerCeiling,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF090D16), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(cavity.left, cavity.top, cavity.width, depthDY)),
    );

    // İç Köşe Derinlik Çizgileri ve Delikli Arka Pano (Pegboard) Dokusu
    final cornerLinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.75)
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(cavity.left + depthDX, cavity.top + depthDY), Offset(cavity.left + depthDX, cavity.bottom - 4), cornerLinePaint);
    canvas.drawLine(Offset(cavity.left + depthDX, cavity.top + depthDY), Offset(cavity.right - 3, cavity.top + depthDY), cornerLinePaint);

    // Arka Duvar Dikey Raf Rayları ve Pegboard Delikleri
    final railPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.7)
      ..strokeWidth = 2.2;
    canvas.drawLine(Offset(cavity.left + depthDX + 14, cavity.top + depthDY), Offset(cavity.left + depthDX + 14, cavity.bottom - 6), railPaint);
    canvas.drawLine(Offset(cavity.right - 16, cavity.top + depthDY), Offset(cavity.right - 16, cavity.bottom - 6), railPaint);

    final holePaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    for (double py = cavity.top + depthDY + 8; py < cavity.bottom - 12; py += 12) {
      for (double px = cavity.left + depthDX + 24; px < cavity.right - 22; px += 16) {
        canvas.drawCircle(Offset(px, py), 1.3, holePaint);
      }
    }

    // 7. 3 KATLI ÖNE ÇIKINTILI 3D RAF TABLALARI VE ÜZERİNDEKİ 3D ÜRÜNLER
    const int numTiers = 3;
    final double usableH = cavity.height - 10;
    final double tierStep = usableH / numTiers;
    const double shelfDepthY = 16.0; // Her raf tablasının arkadan öne doğru 3D derinliği

    final int totalStock = shelf.assignedProduct == SimProductType.egg
        ? min(20, shelf.currentStock)
        : min(shelf.maxCapacity, shelf.currentStock);

    for (int t = 0; t < numTiers; t++) {
      // Rafın ön kenar Y koordinatı ve arka duvara değdiği Y koordinatı
      final double frontY = cavity.top + 28.0 + (t * tierStep);
      final double backY = frontY - shelfDepthY;

      // A) Raf Altı Derin Gölge (Alt kata düşen gerçekçi karanlık gölge)
      if (t < numTiers) {
        final underShadowPath = Path()
          ..moveTo(cavity.left + 2, frontY + 6)
          ..lineTo(cavity.right - 2, frontY + 6)
          ..lineTo(cavity.right - 4, frontY + 17)
          ..lineTo(cavity.left + depthDX, frontY + 17)
          ..close();
        canvas.drawPath(
          underShadowPath,
          Paint()..color = Colors.black.withValues(alpha: 0.55),
        );
      }

      // B) Sol ve Sağ Metal Raf Destek Kolları (3D Konsol Braketi)
      final leftBracket = Path()
        ..moveTo(cavity.left, frontY)
        ..lineTo(cavity.left + depthDX, backY)
        ..lineTo(cavity.left + depthDX, backY + 7)
        ..lineTo(cavity.left, frontY + 8)
        ..close();
      canvas.drawPath(leftBracket, Paint()..color = const Color(0xFF64748B));

      final rightBracket = Path()
        ..moveTo(cavity.right - 4, backY)
        ..lineTo(cavity.right, frontY)
        ..lineTo(cavity.right, frontY + 8)
        ..lineTo(cavity.right - 4, backY + 7)
        ..close();
      canvas.drawPath(rightBracket, Paint()..color = const Color(0xFF475569));

      // C) 3D RAF TABLASI ÜST DERİNLİK YÜZEYİ (Arkadan öne doğru uzanan perspektif tabla)
      final shelfTopSurface = Path()
        ..moveTo(cavity.left + depthDX, backY)
        ..lineTo(cavity.right - 4, backY)
        ..lineTo(cavity.right, frontY)
        ..lineTo(cavity.left + 1, frontY)
        ..close();

      canvas.drawPath(
        shelfTopSurface,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF64748B), Color(0xFFCBD5E1), Color(0xFFF8FAFC)],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(cavity.left, backY, cavity.width, shelfDepthY)),
      );

      // Raf tablası üzerinde perspektif derinlik ızgara çizgileri
      for (int g = 1; g <= 4; g++) {
        final ratio = g / 5.0;
        final bx = (cavity.left + depthDX) + (cavity.width - depthDX - 4) * ratio;
        final fx = (cavity.left + 1) + (cavity.width - 1) * ratio;
        canvas.drawLine(
          Offset(bx, backY + 1),
          Offset(fx, frontY - 1),
          Paint()
            ..color = const Color(0xFF475569).withValues(alpha: 0.32)
            ..strokeWidth = 1.0,
        );
      }

      // Arka duvar ile raf tablası birleşim oluğu (Ambient Occlusion)
      canvas.drawLine(
        Offset(cavity.left + depthDX, backY),
        Offset(cavity.right - 4, backY),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.65)
          ..strokeWidth = 2.0,
      );

      // D) Sıcak LED Raf İçi Aydınlatma Hüzmesi (Kapak açıldığında daha parlak yanar!)
      canvas.drawRect(
        Rect.fromLTWH(cavity.left + depthDX, backY - 8, cavity.width - depthDX - 4, 8),
        Paint()..color = const Color(0xFFFEF08A).withValues(alpha: 0.14 + shelf.doorOpenProgress * 0.18),
      );

      // E) BU RAF KATINDAKİ 3D HACİMLİ ÜRÜNLER (Yumurtalar tekli tekli, diğerleri derinlikli dizilim!)
      _drawTierProducts3D(
        canvas,
        shelf: shelf,
        tierIndex: t,
        totalStock: totalStock,
        leftX: cavity.left + depthDX + 10,
        rightX: cavity.right - 14,
        frontY: frontY,
        backY: backY,
      );

      // F) RAF ÖN KALINLIK KENARI, METAL BARI VE 3D FİYAT ETİKET RAYI
      final shelfFrontLip = Rect.fromLTWH(cavity.left, frontY, cavity.width, 7.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shelfFrontLip, const Radius.circular(2)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFF94A3B8), Color(0xFF475569)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(shelfFrontLip),
      );

      // Ürünlerin düşmesini önleyen ince krom ön tel korkuluk (Guard Rail)
      canvas.drawLine(
        Offset(cavity.left + 3, frontY - 3.5),
        Offset(cavity.right - 3, frontY - 3.5),
        Paint()
          ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.85)
          ..strokeWidth = 1.4,
      );

      // Renkli Fiyat Etiket Şeridi ve 3D Sarı Fiyat Etiketleri
      canvas.drawRect(
        Rect.fromLTWH(cavity.left + 2, frontY + 2.5, cavity.width - 4, 4.5),
        Paint()..color = def.primaryColor.withValues(alpha: 0.95),
      );
      for (double lx = cavity.left + 16; lx < cavity.right - 22; lx += 38) {
        canvas.drawRect(Rect.fromLTWH(lx + 1, frontY + 2.5, 14, 5), Paint()..color = Colors.black38);
        canvas.drawRect(Rect.fromLTWH(lx, frontY + 2.0, 14, 4.8), Paint()..color = const Color(0xFFFEF08A));
      }
    }

    // 8. Sol ve Sağ 3D Çelik Dikme Direkleri (Ön Yüzey + Yan Kalınlık Pahı)
    final leftPostFront = Rect.fromLTWH(topFace.left, topFace.top + 16, 8, topFace.height - 16);
    canvas.drawRect(leftPostFront, Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawRect(Rect.fromLTWH(leftPostFront.right, leftPostFront.top, 3.5, leftPostFront.height), Paint()..color = const Color(0xFF475569));

    final rightPostFront = Rect.fromLTWH(topFace.right - 8, topFace.top + 16, 8, topFace.height - 16);
    canvas.drawRect(rightPostFront, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawRect(Rect.fromLTWH(rightPostFront.left - 3, rightPostFront.top, 3, rightPostFront.height), Paint()..color = const Color(0xFF334155));

    // Dikme direkleri üzerindeki montaj delikleri
    for (double hy = topFace.top + 24; hy < topFace.bottom - 8; hy += 10) {
      canvas.drawRect(Rect.fromLTWH(topFace.left + 2.5, hy, 3, 4), Paint()..color = const Color(0xFF1E293B));
      canvas.drawRect(Rect.fromLTWH(topFace.right - 5.5, hy, 3, 4), Paint()..color = const Color(0xFF1E293B));
    }

    // 8.B 3D AÇILIR-KAPANIR CAM REYON / DOLAP KAPAKLARI (Ürün alırken ve dizerken 3D dışa doğru açılır!)
    _draw3DShelfGlassDoors(
      canvas,
      cavity,
      shelf.doorOpenProgress,
      accentColor: def.primaryColor,
    );

    // 9. 3D ÖNE ÇIKINTILI IŞIKLI ÜST KANOPİ TABELASI
    final canopyRect = Rect.fromLTWH(topFace.left - 4, topFace.top - 8, topFace.width + 8, 28);
    // Kanopinin altındaki rafa düşürdüğü derin gölge
    canvas.drawRect(
      Rect.fromLTWH(topFace.left + 4, canopyRect.bottom - 6, topFace.width - 8, 8),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    _draw3DBox(
      canvas,
      baseRect: canopyRect,
      height3D: 9,
      topColors: [def.primaryColor, Color.lerp(def.primaryColor, Colors.black, 0.25)!],
      frontColors: const [Color(0xFF1E293B), Color(0xFF090D16)],
      sideColor: const Color(0xFF020617),
      radius: 8,
      castShadow: false,
      borderColor: Colors.white.withValues(alpha: 0.8),
    );
    _drawText(
      canvas,
      '${def.emoji} ${shelf.name.toUpperCase()} • \$${def.retailPrice.toStringAsFixed(0)}',
      topFace.center.dx,
      canopyRect.center.dy - 9,
      fontSize: 10.2,
      color: Colors.white,
      isBold: true,
    );

    _drawShelfStockBar(canvas, rect, shelf.currentStock, shelf.maxCapacity);
  }

  /// Her bir 3D raf katının üzerine ürünleri dizer (Yumurtalar dörtlü koli yerine TEKLİ TEKLİ dizilir!)
  void _drawTierProducts3D(
    Canvas canvas, {
    required StoreShelf shelf,
    required int tierIndex,
    required int totalStock,
    required double leftX,
    required double rightX,
    required double frontY,
    required double backY,
  }) {
    // 🥚 YUMURTA REYONUNDA DÖRTLÜ PAKET YERİNE TEKLİ TEKLİ DİZİLİM (20 Adet Tekil Yumurta Yuvası: 7 + 7 + 6)
    if (shelf.assignedProduct == SimProductType.egg) {
      final int colsInTier = tierIndex < 2 ? 7 : 6;
      final int startIdx = tierIndex == 0 ? 0 : (tierIndex == 1 ? 7 : 14);
      final double spanX = rightX - leftX + 6.0;
      final double stepX = colsInTier > 1 ? spanX / (colsInTier - 1) : 0.0;
      final double baseLeft = leftX - 3.0;

      for (int c = 0; c < colsInTier; c++) {
        final int globalEggIdx = startIdx + c;
        final double ex = baseLeft + (c * stepX);
        final double ey = frontY - 6.5;

        // 1. Önce rafa sabit tekli saman/ahşap yumurta yuvasını çiz (boşken de yeri belli olsun)
        canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, ey + 4.5), width: 13.0, height: 5.5),
          Paint()..color = const Color(0xFF78350F).withValues(alpha: 0.75),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, ey + 3.8), width: 10.5, height: 3.8),
          Paint()..color = const Color(0xFFD97706).withValues(alpha: 0.65),
        );

        // 2. Bu yuvada yumurta varsa TEKLİ 3D YUMURTA çiz (son konulan yumurta canlıca zıplar!)
        if (totalStock > globalEggIdx) {
          final bool isNewest = (globalEggIdx == totalStock - 1) && shelf.lastPlacedBounceTimer > 0.01;
          final double bounceScale = isNewest
              ? 1.0 + sin(shelf.lastPlacedBounceTimer * pi) * 0.38
              : 1.0;
          final double bounceOffsetY = isNewest
              ? -sin(shelf.lastPlacedBounceTimer * pi) * 4.5
              : 0.0;

          // Eğer stok çoksa arkada derinlik için ikinci sıra tekli yumurta gölgesi
          if (totalStock > 10 && c.isEven) {
            _draw3DSingleEggItem(canvas, ex + 2.5, backY + 4.0, isBackRow: true);
          }
          _draw3DSingleEggItem(
            canvas,
            ex,
            ey + bounceOffsetY,
            scale: bounceScale,
          );
        }
      }
      return;
    }

    final int cols = shelf.rect.width > 180 ? 4 : 3;
    final int startIdx = tierIndex * cols;
    if (totalStock <= startIdx) return;

    final int countOnTier = min(cols, totalStock - startIdx);
    final double spanX = rightX - leftX;
    final double stepX = cols > 1 ? spanX / (cols - 1) : 0;

    // 1. ÖNCE ARKA SIRA ÜRÜNLER (Rafın derinliğinde, hafif gölgeli ikinci sıra - derinlik hissini katlar!)
    if (shelf.currentStock > 6) {
      for (int c = 0; c < countOnTier; c++) {
        final double bx = leftX + (c * stepX) + 5.0;
        final double by = backY + 2.0;
        canvas.save();
        if (shelf.assignedProduct == SimProductType.flour) {
          _draw3DFlourBagItem(canvas, bx, by, isBackRow: true);
        } else if (shelf.assignedProduct == SimProductType.cheese) {
          _draw3DCheeseWheelItem(canvas, bx, by, isBackRow: true);
        } else {
          _draw3DArtisanBreadItem(canvas, bx, by, isBackRow: true);
        }
        canvas.restore();
      }
    }

    // 2. SONRA ÖN SIRA ÜRÜNLER (Rafın ön kenarına yakın, tam aydınlık 3D ürünler)
    for (int c = 0; c < countOnTier; c++) {
      final int globalIdx = startIdx + c;
      final bool isNewest = (globalIdx == min(cols * 3, totalStock) - 1) && shelf.lastPlacedBounceTimer > 0.01;
      final double bounceY = isNewest ? -sin(shelf.lastPlacedBounceTimer * pi) * 4.0 : 0.0;
      final double px = leftX + (c * stepX);
      final double py = frontY - 8.5 + bounceY;

      if (shelf.assignedProduct == SimProductType.flour) {
        _draw3DFlourBagItem(canvas, px, py);
      } else if (shelf.assignedProduct == SimProductType.cheese) {
        _draw3DCheeseWheelItem(canvas, px, py);
      } else {
        _draw3DArtisanBreadItem(canvas, px, py);
      }
    }
  }

  /// 🥚 Rafa dörtlü paket yerine TEK TEK dizilen 3 Boyutlu Taze Köy Yumurtası
  void _draw3DSingleEggItem(Canvas canvas, double x, double y, {bool isBackRow = false, double scale = 1.0}) {
    final double effScale = (isBackRow ? 0.82 : 1.0) * scale;
    final double w = 11.2 * effScale;
    final double h = 14.5 * effScale;

    final eggRect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);

    // Raf tablası üzerindeki temas gölgesi
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 1.5, eggRect.bottom + 0.5), width: w + 2, height: 4.2 * effScale),
      Paint()..color = Colors.black.withValues(alpha: isBackRow ? 0.50 : 0.38),
    );

    // 3D Küresel/Oval Köy Yumurtası Gövdesi
    canvas.drawOval(
      eggRect,
      Paint()
        ..shader = RadialGradient(
          colors: isBackRow
              ? const [Color(0xFFFDE68A), Color(0xFFB45309)]
              : const [Color(0xFFFFFFFF), Color(0xFFFEF3C7), Color(0xFFF59E0B), Color(0xFFB45309)],
          stops: isBackRow ? null : const [0.0, 0.42, 0.82, 1.0],
          center: const Alignment(-0.32, -0.38),
        ).createShader(eggRect),
    );

    if (!isBackRow) {
      // Yumurta kabuğu üzeri parlak 3D ışık yansıması (Specular Highlight)
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x - w * 0.18, y - h * 0.22), width: w * 0.28, height: h * 0.32),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  void _draw3DFlourBagItem(Canvas canvas, double x, double y, {bool isBackRow = false}) {
    final double scale = isBackRow ? 0.88 : 1.0;
    final double w = 20.0 * scale;
    final double h = 22.0 * scale;
    final double sideW = 5.0 * scale;

    final bagRect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);

    // Raf tablası üzerindeki temas gölgesi
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 3, bagRect.bottom + 1), width: w + 6, height: 6),
      Paint()..color = Colors.black.withValues(alpha: isBackRow ? 0.55 : 0.42),
    );

    // Sağ 3D Yan Körük Derinliği (Paket Kalınlığı)
    final sideGusset = Path()
      ..moveTo(bagRect.right, bagRect.top + 2)
      ..lineTo(bagRect.right + sideW, bagRect.top - 1)
      ..lineTo(bagRect.right + sideW, bagRect.bottom - 2)
      ..lineTo(bagRect.right, bagRect.bottom)
      ..close();
    canvas.drawPath(
      sideGusset,
      Paint()..color = isBackRow ? const Color(0xFF78350F) : const Color(0xFFB45309),
    );

    // Üst 3D Katlanmış Paket Ağzı (Top Crimp)
    final topFold = Path()
      ..moveTo(bagRect.left + 1, bagRect.top + 2)
      ..lineTo(bagRect.left + 4, bagRect.top - 2)
      ..lineTo(bagRect.right + sideW - 1, bagRect.top - 2)
      ..lineTo(bagRect.right, bagRect.top + 2)
      ..close();
    canvas.drawPath(
      topFold,
      Paint()..color = isBackRow ? const Color(0xFFD97706) : const Color(0xFFFEF3C7),
    );

    // Ön 3D Paket Gövdesi
    canvas.drawRRect(
      RRect.fromRectAndRadius(bagRect, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: isBackRow
              ? const [Color(0xFFD6D3D1), Color(0xFFB45309)]
              : const [Color(0xFFFFFBEB), Color(0xFFFDE68A), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bagRect),
    );

    if (!isBackRow) {
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y + 1), width: w, height: 8), Paint()..color = const Color(0xFFB45309));
      _drawText(canvas, 'FLOUR', x, y + 1, fontSize: 6.5, color: Colors.white, isBold: true);
    }
  }

  void _draw3DCheeseWheelItem(Canvas canvas, double x, double y, {bool isBackRow = false}) {
    final double scale = isBackRow ? 0.88 : 1.0;
    final double w = 23.0 * scale;
    final double h = 13.0 * scale;
    const double cylinderHeight = 7.0;

    // Raf Üzeri Gölge
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 2.5, y + cylinderHeight + 2), width: w + 3, height: h),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // 3D Silindirik Peynir Tekeri Yan Gövdesi (Kalınlık Katmanı)
    final bodyRect = Rect.fromCenter(center: Offset(x, y + cylinderHeight * 0.5), width: w, height: h + cylinderHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(h * 0.6)),
      Paint()
        ..shader = LinearGradient(
          colors: isBackRow
              ? const [Color(0xFFB45309), Color(0xFF78350F)]
              : const [Color(0xFFEAB308), Color(0xFFCA8A04), Color(0xFF854D0E)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bodyRect),
    );

    // Üst 3D Dairesel Peynir Yüzeyi
    final topOval = Rect.fromCenter(center: Offset(x, y - 1), width: w, height: h);
    canvas.drawOval(
      topOval,
      Paint()
        ..shader = RadialGradient(
          colors: isBackRow
              ? const [Color(0xFFFACC15), Color(0xFFCA8A04)]
              : const [Color(0xFFFEF9C3), Color(0xFFFACC15), Color(0xFFEAB308)],
          center: const Alignment(-0.2, -0.3),
        ).createShader(topOval),
    );

    if (!isBackRow) {
      // Peynir gözenekleri ve kırmızı mum mühür şeridi
      canvas.drawCircle(Offset(x - 4.5, y - 1.5), 1.8, Paint()..color = const Color(0xFFA16207));
      canvas.drawCircle(Offset(x + 4.0, y + 0.5), 1.5, Paint()..color = const Color(0xFFA16207));
      canvas.drawCircle(Offset(x + 0.5, y - 2.5), 1.2, Paint()..color = const Color(0xFFA16207));
    }
  }

  void _draw3DArtisanBreadItem(Canvas canvas, double x, double y, {bool isBackRow = false}) {
    final double scale = isBackRow ? 0.88 : 1.0;
    final double w = 24.0 * scale;
    final double h = 14.0 * scale;

    final loafRect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
    // Alt Gölge
    canvas.drawRRect(
      RRect.fromRectAndRadius(loafRect.translate(2.5, 4), const Radius.circular(7)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    // Alt Kabuk Kalınlığı (3D Taban)
    canvas.drawRRect(
      RRect.fromRectAndRadius(loafRect.translate(0, 2.5), const Radius.circular(7)),
      Paint()..color = const Color(0xFF451A03),
    );
    // Üst Bombe Somun Gövdesi
    canvas.drawRRect(
      RRect.fromRectAndRadius(loafRect, const Radius.circular(7)),
      Paint()
        ..shader = RadialGradient(
          colors: isBackRow
              ? const [Color(0xFFD97706), Color(0xFF78350F)]
              : const [Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFF78350F)],
          center: const Alignment(-0.25, -0.35),
        ).createShader(loafRect),
    );
    if (!isBackRow) {
      // Ekmek Üzeri Bıçak Çizikleri & Un Dokusu
      final scorePaint = Paint()
        ..color = const Color(0xFFFEF3C7)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x - 5, y - 2.5), Offset(x - 2, y + 2.5), scorePaint);
      canvas.drawLine(Offset(x, y - 2.5), Offset(x + 3, y + 2.5), scorePaint);
      canvas.drawLine(Offset(x + 5, y - 2.0), Offset(x + 7, y + 2.0), scorePaint);
    }
  }

  // 5.B TAM 3 BOYUTLU DERİNLİKLİ SÜT & MANDIRA SOĞUTUCU CAMLI DOLAP
  void _draw3DMilkCoolerCabinet(Canvas canvas, StoreShelf shelf) {
    final rect = shelf.rect;
    const double height3D = 46.0;
    const double sideDepthX = 22.0;
    const double sideDepthY = 14.0;

    if (shelf.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(20)),
        Paint()
          ..color = Colors.cyanAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    // 1. Zemine Yayılan Soğuk Neon Mavi LED Işık Yansıması ve Derin Gölge (Blur filtresiz)
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(12).translate(4, 10), const Radius.circular(22)),
      Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.14),
    );
    _drawSoftShadow(
      canvas,
      rect,
      radius: 14,
      offsetX: sideDepthX + 8,
      offsetY: 22,
      blur: 18,
      alpha: 0.55,
    );

    final topFace = rect.translate(0, -height3D);

    // 2. Üst Tavan 3D Perspektif Yüzeyi ve Tepe Soğutucu Fan Ünitesi
    final roofPath = Path()
      ..moveTo(topFace.left + 6, topFace.top)
      ..lineTo(topFace.right, topFace.top)
      ..lineTo(topFace.right + sideDepthX, topFace.top + sideDepthY)
      ..lineTo(topFace.left + sideDepthX, topFace.top + sideDepthY)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF475569), Color(0xFF1E293B)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(topFace.left, topFace.top, topFace.width + sideDepthX, sideDepthY)),
    );

    // 3. Sağ 3D Yan Yalıtımlı Dolap Duvarı & Havalandırma Panjurları
    final sideWall = Path()
      ..moveTo(topFace.right, topFace.top)
      ..lineTo(topFace.right + sideDepthX, topFace.top + sideDepthY)
      ..lineTo(rect.right + sideDepthX, rect.bottom - 6)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(
      sideWall,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A), Color(0xFF020617)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(topFace.right, topFace.top, sideDepthX, rect.height + height3D)),
    );
    // Yan Duvar Soğutucu Izgaraları
    for (double vy = topFace.top + 30; vy < rect.bottom - 20; vy += 14) {
      canvas.drawLine(
        Offset(topFace.right + 4, vy),
        Offset(topFace.right + sideDepthX - 4, vy + sideDepthY * 0.55),
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)
          ..strokeWidth = 2.0,
      );
    }

    // 4. Alt 3D Kompresör Motor Bazası ( Izgaralı Alt Gövde )
    final compressorBase = Rect.fromLTWH(rect.left, rect.bottom - height3D, rect.width, height3D);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        compressorBase,
        bottomLeft: const Radius.circular(12),
        bottomRight: const Radius.circular(12),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF090D16)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(compressorBase),
    );
    for (double gy = compressorBase.top + 12; gy < compressorBase.bottom - 6; gy += 6) {
      canvas.drawLine(
        Offset(compressorBase.left + 14, gy),
        Offset(compressorBase.right - 14, gy),
        Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 2.0,
      );
    }

    // 5. Dolap Ana Dış Gövdesi
    canvas.drawRRect(
      RRect.fromRectAndRadius(topFace, const Radius.circular(12)),
      Paint()..color = const Color(0xFF1E293B),
    );

    // 6. DERİN SOĞUTUCU İÇ HAZNE (3D Perspektif Sol İç Duvar, Tavan ve Arka Soğutucu Panel)
    final innerChamber = Rect.fromLTWH(topFace.left + 9, topFace.top + 32, topFace.width - 18, topFace.height - 42);
    const double chDX = 14.0;
    const double chDY = 10.0;

    // Arka Soğuk LED Panel
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerChamber, const Radius.circular(8)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0369A1), Color(0xFF0284C7), Color(0xFF38BDF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(innerChamber),
    );

    // Sol İç Yan Soğutucu Duvarı (Derinlik Perspektifi)
    final innerLeftWall = Path()
      ..moveTo(innerChamber.left, innerChamber.top)
      ..lineTo(innerChamber.left + chDX, innerChamber.top + chDY)
      ..lineTo(innerChamber.left + chDX, innerChamber.bottom - 4)
      ..lineTo(innerChamber.left, innerChamber.bottom)
      ..close();
    canvas.drawPath(
      innerLeftWall,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0C4A6E), Color(0xFF075985)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(innerChamber.left, innerChamber.top, chDX, innerChamber.height)),
    );

    // Üst İç Tavan (Soğuk Buhar ve Neon Tüp)
    final innerCeiling = Path()
      ..moveTo(innerChamber.left, innerChamber.top)
      ..lineTo(innerChamber.right, innerChamber.top)
      ..lineTo(innerChamber.right - 3, innerChamber.top + chDY)
      ..lineTo(innerChamber.left + chDX, innerChamber.top + chDY)
      ..close();
    canvas.drawPath(innerCeiling, Paint()..color = const Color(0xFF082F49));

    // İç Derinlik Köşe Çizgisi
    canvas.drawLine(
      Offset(innerChamber.left + chDX, innerChamber.top + chDY),
      Offset(innerChamber.left + chDX, innerChamber.bottom - 4),
      Paint()
        ..color = const Color(0xFF082F49).withValues(alpha: 0.7)
        ..strokeWidth = 2.0,
    );

    // 7. 4 KATLI 3D CAM / KROM SOĞUTUCU RAF TABLALARI VE SÜT ŞİŞELERİ
    const int numTiers = 4;
    final double tierH = (innerChamber.height - 14) / numTiers;
    const double rackDepthY = 12.0;
    final int totalMilk = min(12, shelf.currentStock);

    for (int t = 0; t < numTiers; t++) {
      final double frontY = innerChamber.top + 28.0 + (t * tierH);
      final double backY = frontY - rackDepthY;

      // Raf Altı Gölgesi
      canvas.drawRect(
        Rect.fromLTWH(innerChamber.left + chDX, frontY + 4, innerChamber.width - chDX - 3, 7),
        Paint()..color = const Color(0xFF082F49).withValues(alpha: 0.48),
      );

      // 3D Cam/Krom Raf Tablası (Arkadan Öne Perspektifli Yüzey)
      final rackSurface = Path()
        ..moveTo(innerChamber.left + chDX, backY)
        ..lineTo(innerChamber.right - 3, backY)
        ..lineTo(innerChamber.right, frontY)
        ..lineTo(innerChamber.left + 1, frontY)
        ..close();
      canvas.drawPath(
        rackSurface,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFFE0F2FE).withValues(alpha: 0.45),
              const Color(0xFFFFFFFF).withValues(alpha: 0.85),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(innerChamber.left, backY, innerChamber.width, rackDepthY)),
      );

      // Raf Ön Krom Çıtası ve Mavi LED Çizgisi
      canvas.drawRect(
        Rect.fromLTWH(innerChamber.left + 1, frontY, innerChamber.width - 2, 4.5),
        Paint()..color = const Color(0xFFCBD5E1),
      );
      canvas.drawLine(
        Offset(innerChamber.left + 2, frontY + 1),
        Offset(innerChamber.right - 2, frontY + 1),
        Paint()
          ..color = const Color(0xFF38BDF8)
          ..strokeWidth = 1.5,
      );

      // Bu Kattaki 3D Süt Şişeleri (Arka Sıra + Ön Sıra Derinlikli!)
      final int startIdx = t * 3;
      if (totalMilk > startIdx) {
        final int countOnTier = min(3, totalMilk - startIdx);
        for (int c = 0; c < countOnTier; c++) {
          final int globalIdx = startIdx + c;
          final bool isNewest = (globalIdx == totalMilk - 1) && shelf.lastPlacedBounceTimer > 0.01;
          final double bounceY = isNewest ? -sin(shelf.lastPlacedBounceTimer * pi) * 4.0 : 0.0;
          final double sx = innerChamber.left + chDX + 14 + (c * 32.0);
          if (shelf.currentStock > 6) {
            _draw3DRealisticMilkBottle(canvas, sx + 4, backY + 1, isBackRow: true);
          }
          _draw3DRealisticMilkBottle(canvas, sx, frontY - 8.5 + bounceY);
        }
      }
    }

    // 8. 3D ÇİFT KANATLI AÇILIR CAM SOĞUTUCU KAPISI, METAL KOLLAR VE SOĞUK BUHAR EFEKTİ
    _draw3DShelfGlassDoors(
      canvas,
      innerChamber,
      shelf.doorOpenProgress,
      accentColor: const Color(0xFF38BDF8),
      isCooler: true,
    );

    // 9. 3D Üst Dijital Termometre & Başlık Kanopisi
    final headerBox = Rect.fromLTWH(topFace.left - 3, topFace.top - 6, topFace.width + 6, 28);
    _draw3DBox(
      canvas,
      baseRect: headerBox,
      height3D: 8,
      topColors: const [Color(0xFF0284C7), Color(0xFF0369A1)],
      frontColors: const [Color(0xFF0F172A), Color(0xFF020617)],
      radius: 8,
      castShadow: false,
      borderColor: const Color(0xFF38BDF8),
    );
    _drawText(canvas, '❄️ -2.4°C • MILK & DAIRY', topFace.center.dx, headerBox.center.dy - 8, fontSize: 9.2, color: Colors.white, isBold: true);

    _drawShelfStockBar(canvas, rect, shelf.currentStock, shelf.maxCapacity);
  }

  void _draw3DRealisticMilkBottle(Canvas canvas, double x, double y, {bool isBackRow = false}) {
    final double scale = isBackRow ? 0.86 : 1.0;
    final double w = 16.5 * scale;
    final double h = 21.0 * scale;

    final bottleRect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
    // Raf Üzeri Gölge
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 2, bottleRect.bottom + 1), width: w + 3, height: 5),
      Paint()..color = const Color(0xFF082F49).withValues(alpha: 0.55),
    );
    // 3D Silindirik Süt Şişesi Gövdesi
    canvas.drawRRect(
      RRect.fromRectAndRadius(bottleRect, const Radius.circular(5)),
      Paint()
        ..shader = LinearGradient(
          colors: isBackRow
              ? const [Color(0xFFCBD5E1), Color(0xFF94A3B8)]
              : const [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFCBD5E1)],
          stops: isBackRow ? null : const [0.0, 0.6, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bottleRect),
    );
    // Şişe Boynu ve 3D Mavi Kapak
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, bottleRect.top - 2.5), width: 9 * scale, height: 4 * scale), const Radius.circular(2)),
      Paint()..color = isBackRow ? const Color(0xFF0369A1) : const Color(0xFF0284C7),
    );
    if (!isBackRow) {
      // Mavi Mandıra Etiketi & Parlama Çizgisi
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y + 1.5), width: w, height: 6.5), Paint()..color = const Color(0xFF0284C7));
      canvas.drawLine(
        Offset(bottleRect.left + 3, bottleRect.top + 3),
        Offset(bottleRect.left + 3, bottleRect.bottom - 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
    }
  }

  // 5.C TAM 3 BOYUTLU DERİN AHŞAP KASALI & DİREKLİ TENTELİ MANAV REYONU
  void _draw3DFruitGreengrocerStand(Canvas canvas, StoreShelf shelf) {
    final rect = shelf.rect;
    final def = productCatalog[shelf.assignedProduct]!;

    const double height3D = 38.0;
    const double sideDepthX = 20.0;
    const double sideDepthY = 13.0;

    if (shelf.isHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(18)),
        Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
      );
    }

    // 1. Derin 3D Zemin Gölgesi
    _drawSoftShadow(
      canvas,
      rect,
      radius: 12,
      offsetX: sideDepthX + 7,
      offsetY: 20,
      blur: 18,
      alpha: 0.50,
    );

    final topFace = rect.translate(0, -height3D);

    // 2. Sağ 3D Yan Ahşap Kalas Duvarı (Kasa Yan Derinliği)
    final rightWoodWall = Path()
      ..moveTo(topFace.right, topFace.top + 12)
      ..lineTo(topFace.right + sideDepthX, topFace.top + 12 + sideDepthY)
      ..lineTo(rect.right + sideDepthX, rect.bottom - 6)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(
      rightWoodWall,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF78350F), Color(0xFF451A03), Color(0xFF290F02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(topFace.right, topFace.top, sideDepthX, rect.height + height3D)),
    );
    // Yan duvar ahşap birleşim derzleri
    for (double wy = topFace.top + 36; wy < rect.bottom - 14; wy += 26) {
      canvas.drawLine(
        Offset(topFace.right + 2, wy),
        Offset(topFace.right + sideDepthX - 2, wy + sideDepthY * 0.65),
        Paint()
          ..color = const Color(0xFF1C0A00)
          ..strokeWidth = 2.0,
      );
    }

    // 3. Alt 3D Ahşap İskelet Gövdesi ve Kalın Ayaklar
    final frontSkirt = Rect.fromLTWH(rect.left, rect.bottom - height3D, rect.width, height3D);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        frontSkirt,
        bottomLeft: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFF78350F), Color(0xFF451A03)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(frontSkirt),
    );
    // Alt İskelet Yatay Tahta Kirişleri ve Demir Köşebentler
    canvas.drawRect(
      Rect.fromLTWH(frontSkirt.left + 12, frontSkirt.top + 10, frontSkirt.width - 24, 16),
      Paint()..color = const Color(0xFF290F02),
    );

    // 4. Ana Ahşap Tezgah Çerçevesi
    canvas.drawRRect(
      RRect.fromRectAndRadius(topFace, const Radius.circular(10)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB45309), Color(0xFF78350F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(topFace),
    );

    // 5. 4x2 DERİN 3D AHŞAP MANAV KASALARI (İç Yan ve Üst Duvarları Görünen Oyuk Kasalar!)
    final crateArea = Rect.fromLTWH(topFace.left + 8, topFace.top + 24, topFace.width - 16, topFace.height - 34);
    const int cols = 4;
    const int rows = 2;
    final double cellW = crateArea.width / cols;
    final double cellH = crateArea.height / rows;
    const double crateDepthX = 8.0; // Kasa içi sol derinlik duvarı
    const double crateDepthY = 8.0; // Kasa içi üst derinlik duvarı

    final int totalStock = min(12, shelf.currentStock);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final cellRect = Rect.fromLTWH(
          crateArea.left + c * cellW + 2,
          crateArea.top + r * cellH + 2,
          cellW - 4,
          cellH - 4,
        );

        // A) Kasa Tabanı (Derin Koyu Ahşap Zemin)
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect, const Radius.circular(5)),
          Paint()..color = const Color(0xFF290F02),
        );

        // B) Kasa İçi Sol 3D Yan Tahta Duvar (Derinlik Yüzeyi)
        final innerLeft = Path()
          ..moveTo(cellRect.left, cellRect.top)
          ..lineTo(cellRect.left + crateDepthX, cellRect.top + crateDepthY)
          ..lineTo(cellRect.left + crateDepthX, cellRect.bottom - 3)
          ..lineTo(cellRect.left, cellRect.bottom)
          ..close();
        canvas.drawPath(innerLeft, Paint()..color = const Color(0xFF78350F));

        // C) Kasa İçi Üst/Arka 3D Tahta Duvar (Derinlik Yüzeyi)
        final innerTop = Path()
          ..moveTo(cellRect.left, cellRect.top)
          ..lineTo(cellRect.right, cellRect.top)
          ..lineTo(cellRect.right - 2, cellRect.top + crateDepthY)
          ..lineTo(cellRect.left + crateDepthX, cellRect.top + crateDepthY)
          ..close();
        canvas.drawPath(innerTop, Paint()..color = const Color(0xFF572408));

        // D) Kasa Taban Tahtası (İçerideki Aydınlık Zemin)
        final floorRect = Rect.fromLTRB(
          cellRect.left + crateDepthX,
          cellRect.top + crateDepthY,
          cellRect.right - 2,
          cellRect.bottom - 3,
        );
        canvas.drawRect(floorRect, Paint()..color = const Color(0xFF92400E));

        // E) Kasa İçindeki Katmanlı 3D Meyve / Sebzeler (Derin Alt Katman + Üst Parlak Katman)
        final int binIndex = r * cols + c;
        if (totalStock > binIndex) {
          // Kasa doluysa altında ve üstünde çoklu 3D meyve öbeği çiz!
          final bool hasExtraLayer = totalStock > (binIndex + 4);
          final List<Offset> fruitOffsets = hasExtraLayer
              ? const [Offset(-7, -2), Offset(7, -2), Offset(0, -6), Offset(-5, 6), Offset(6, 6), Offset(0, 2)]
              : const [Offset(-5, 0), Offset(6, 1), Offset(0, 5)];

          for (int fi = 0; fi < fruitOffsets.length; fi++) {
            final fo = fruitOffsets[fi];
            final fx = floorRect.center.dx + fo.dx;
            final fy = floorRect.center.dy + fo.dy;
            final bool isBottomLayer = hasExtraLayer && fi < 3;
            _draw3DProduceItem(
              canvas,
              product: shelf.assignedProduct,
              x: fx,
              y: fy,
              isBottomLayer: isBottomLayer,
            );
          }
        }

        // F) Kasa Ön 3D Kalın Ahşap Çıtası (Ürünlerin Önünü Tutan Kasa Kenarı)
        final frontSlat = Rect.fromLTWH(cellRect.left - 1, cellRect.bottom - 6, cellRect.width + 2, 6.5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(frontSlat, const Radius.circular(2)),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFD97706), Color(0xFF92400E), Color(0xFF451A03)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(frontSlat),
        );
        // Çıta çivileri
        canvas.drawCircle(Offset(frontSlat.left + 4, frontSlat.center.dy), 1.2, Paint()..color = const Color(0xFF1C0A00));
        canvas.drawCircle(Offset(frontSlat.right - 4, frontSlat.center.dy), 1.2, Paint()..color = const Color(0xFF1C0A00));
      }
    }

    // 6. ТENTEYİ TUTAN SOL VE SAĞ 3D AHŞAP DİREKLER (Dikey Pazar Standı Direkleri)
    for (final px in [topFace.left + 3, topFace.right - 7]) {
      final poleRect = Rect.fromLTWH(px, topFace.top - 10, 5.5, topFace.height + 6);
      canvas.drawRect(poleRect.translate(2, 2), Paint()..color = Colors.black38);
      canvas.drawRRect(
        RRect.fromRectAndRadius(poleRect, const Radius.circular(2)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFD97706), Color(0xFF78350F)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(poleRect),
      );
    }

    // 6.B 3D AÇILIR-KAPANIR ŞEFFAF MANAV VİTRİN KAPAKLARI
    _draw3DShelfGlassDoors(
      canvas,
      crateArea,
      shelf.doorOpenProgress,
      accentColor: def.primaryColor,
    );

    // 7. 3D ÇİZGİLİ & DALGALI SAÇAKLI PAZAR TENTESİ (AWNING)
    final awningRect = Rect.fromLTWH(topFace.left - 5, topFace.top - 12, topFace.width + 10, 28);
    // Tentenin kasaların üzerine düşürdüğü derin gölge
    canvas.drawRect(
      Rect.fromLTWH(topFace.left + 4, awningRect.bottom - 4, topFace.width - 8, 9),
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    _draw3DBox(
      canvas,
      baseRect: awningRect,
      height3D: 10,
      topColors: [def.primaryColor, Color.lerp(def.primaryColor, Colors.black, 0.25)!],
      frontColors: const [Color(0xFF1E293B), Color(0xFF0F172A)],
      sideColor: const Color(0xFF090D16),
      radius: 8,
      castShadow: false,
      borderColor: Colors.white70,
    );

    // Tente Ön Dalgalı Saçakları (Scalloped Valance)
    final awningTopFace = awningRect.translate(0, -10);
    const int stripeCount = 8;
    final double stripeW = awningRect.width / stripeCount;
    for (int s = 0; s < stripeCount; s++) {
      final sx = awningRect.left + s * stripeW;
      final isLight = s.isOdd;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(sx + 1, awningRect.bottom - 4, stripeW - 2, 6),
          bottomLeft: const Radius.circular(5),
          bottomRight: const Radius.circular(5),
        ),
        Paint()..color = isLight ? const Color(0xFFFFFBEB) : def.primaryColor,
      );
    }

    _drawText(
      canvas,
      '${def.emoji} ${def.name.toUpperCase()} • \$${def.retailPrice.toStringAsFixed(0)}',
      topFace.center.dx,
      awningTopFace.center.dy,
      fontSize: 10.2,
      color: Colors.white,
      isBold: true,
    );

    _drawShelfStockBar(canvas, rect, shelf.currentStock, shelf.maxCapacity);
  }

  /// 🚪 Reyonlardan ürün alınırken veya rafa ürün dizilirken 3D perspektifle dışa doğru açılan çift kanatlı cam kapaklar
  void _draw3DShelfGlassDoors(
    Canvas canvas,
    Rect chamberRect,
    double openProgress, {
    required Color accentColor,
    bool isCooler = false,
  }) {
    final double open = openProgress.clamp(0.0, 1.0);
    final double halfW = chamberRect.width / 2.0;

    // Kapak açıldığında içeriden dışarı yayılan sıcak/soğuk vitrin aydınlatması
    if (open > 0.04) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(chamberRect.inflate(4), const Radius.circular(8)),
        Paint()
          ..color = (isCooler ? const Color(0xFF38BDF8) : const Color(0xFFFEF08A))
              .withValues(alpha: open * 0.22),
      );
    }

    // 3D Perspektifli Sol ve Sağ Cam Kapı Kanatları:
    // Kapalıyken (open == 0) tam ortada birleşir; açıldıkça (open -> 1) menteşelerden dışa/öne doğru 3D açılır!
    final double leafProjectionW = halfW * (1.0 - open * 0.68);
    final double swingOutY = open * 24.0;
    final double sideFlareX = open * 14.0;

    // 1. SOL CAM KAPI KANADI (Sol dikmeye menteşeli)
    final double leftInnerX = chamberRect.left + leafProjectionW - sideFlareX;
    final Path leftDoorPath = Path()
      ..moveTo(chamberRect.left, chamberRect.top)
      ..lineTo(leftInnerX, chamberRect.top + swingOutY * 0.55)
      ..lineTo(leftInnerX, chamberRect.bottom + swingOutY)
      ..lineTo(chamberRect.left, chamberRect.bottom)
      ..close();

    // 2. SAĞ CAM KAPI KANADI (Sağ dikmeye menteşeli)
    final double rightInnerX = chamberRect.right - leafProjectionW + sideFlareX;
    final Path rightDoorPath = Path()
      ..moveTo(rightInnerX, chamberRect.top + swingOutY * 0.55)
      ..lineTo(chamberRect.right, chamberRect.top)
      ..lineTo(chamberRect.right, chamberRect.bottom)
      ..lineTo(rightInnerX, chamberRect.bottom + swingOutY)
      ..close();

    // Açılan kapakların zemine/rafa düşen gölgesi
    if (open > 0.05) {
      final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.24 * open);
      canvas.drawPath(leftDoorPath.shift(const Offset(2, 5)), shadowPaint);
      canvas.drawPath(rightDoorPath.shift(const Offset(-2, 5)), shadowPaint);
    }

    // Cam Dolgu Rengi (Saydam buzlu/parlak vitrin camı)
    final Color glassColor = isCooler
        ? const Color(0xFFBAE6FD).withValues(alpha: 0.20 + open * 0.12)
        : const Color(0xFFE2E8F0).withValues(alpha: 0.15 + open * 0.12);
    final Paint glassFill = Paint()..color = glassColor;
    canvas.drawPath(leftDoorPath, glassFill);
    canvas.drawPath(rightDoorPath, glassFill);

    // Cam Üzeri Çapraz Işık Yansıması (Specular Shine)
    final Paint shinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(chamberRect.left + 6, chamberRect.bottom - 14),
      Offset(leftInnerX - 4, chamberRect.top + 14 + swingOutY * 0.4),
      shinePaint,
    );
    canvas.drawLine(
      Offset(rightInnerX + 6, chamberRect.bottom - 14 + swingOutY * 0.6),
      Offset(chamberRect.right - 6, chamberRect.top + 14),
      shinePaint,
    );

    // Cam Kapı Metal/Krom Çerçeveleri
    final Paint frameStroke = Paint()
      ..color = isCooler
          ? const Color(0xFF7DD3FC).withValues(alpha: 0.85)
          : const Color(0xFFCBD5E1).withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(leftDoorPath, frameStroke);
    canvas.drawPath(rightDoorPath, frameStroke);

    // Sol ve Sağ Menteşeler (Hinges)
    final Paint hingePaint = Paint()..color = const Color(0xFF64748B);
    for (final hy in [chamberRect.top + 12.0, chamberRect.bottom - 16.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(chamberRect.left - 2, hy, 5, 8), const Radius.circular(2)),
        hingePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(chamberRect.right - 3, hy, 5, 8), const Radius.circular(2)),
        hingePaint,
      );
    }

    // 3D Krom Kapı Kolları (Kapakla birlikte dışa doğru hareket eder!)
    final double leftHandleX = leftInnerX - 6.0;
    final double leftHandleY = chamberRect.center.dy + swingOutY * 0.75;
    final double rightHandleX = rightInnerX + 2.5;
    final double rightHandleY = chamberRect.center.dy + swingOutY * 0.75;

    final Paint handleShadow = Paint()..color = Colors.black45;
    final Paint handleChrome = Paint()..color = const Color(0xFFF8FAFC);
    final Paint handleAccent = Paint()..color = accentColor;

    for (final hPos in [Offset(leftHandleX, leftHandleY), Offset(rightHandleX, rightHandleY)]) {
      final hRect = Rect.fromCenter(center: hPos, width: 4.0, height: 28.0);
      canvas.drawRRect(RRect.fromRectAndRadius(hRect.translate(1, 2), const Radius.circular(2)), handleShadow);
      canvas.drawRRect(RRect.fromRectAndRadius(hRect, const Radius.circular(2)), handleChrome);
      canvas.drawRect(Rect.fromCenter(center: hPos, width: 4.0, height: 8.0), handleAccent);
    }

    // Kapak tam veya yarı açıkken üstte canlı "🚪 KAPAK AÇIK" göstergesi (isteğe bağlı zarif rozet)
    if (open > 0.35) {
      final pill = Rect.fromCenter(
        center: Offset(chamberRect.center.dx, chamberRect.bottom + 8 + open * 4),
        width: 84,
        height: 14,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(7)),
        Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.78 * open),
      );
      _drawText(
        canvas,
        '🔓 Shelf Cover Open',
        pill.center.dx,
        pill.center.dy,
        fontSize: 7.5,
        color: const Color(0xFF4ADE80).withValues(alpha: open),
        isBold: true,
      );
    }
  }

  /// Manav kasalarının içindeki tekil 3D Domates, Biber veya Elmayı derinlikli çizer
  void _draw3DProduceItem(
    Canvas canvas, {
    required SimProductType product,
    required double x,
    required double y,
    bool isBottomLayer = false,
  }) {
    final double scale = isBottomLayer ? 0.85 : 1.0;
    final double r = 8.2 * scale;

    canvas.drawCircle(
      Offset(x + 1.8, y + 2.5),
      r,
      Paint()..color = Colors.black.withValues(alpha: isBottomLayer ? 0.55 : 0.38),
    );

    if (product == SimProductType.tomato) {
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: isBottomLayer
                ? const [Color(0xFFEF4444), Color(0xFF7F1D1D)]
                : const [Color(0xFFFECACA), Color(0xFFEF4444), Color(0xFF991B1B)],
            center: const Alignment(-0.35, -0.35),
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
      );
      if (!isBottomLayer) {
        canvas.drawCircle(Offset(x, y - r * 0.65), 2.6, Paint()..color = const Color(0xFF15803D));
      }
    } else if (product == SimProductType.pepper) {
      final pRect = Rect.fromCenter(center: Offset(x, y), width: 11.5 * scale, height: 16.0 * scale);
      canvas.drawOval(
        pRect,
        Paint()
          ..shader = RadialGradient(
            colors: isBottomLayer
                ? const [Color(0xFF16A34A), Color(0xFF052E16)]
                : const [Color(0xFFBBF7D0), Color(0xFF22C55E), Color(0xFF14532D)],
            center: const Alignment(-0.3, -0.3),
          ).createShader(pRect),
      );
      if (!isBottomLayer) {
        canvas.drawCircle(Offset(x, y - 6.5 * scale), 2.3, Paint()..color = const Color(0xFF052E16));
      }
    } else {
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: isBottomLayer
                ? const [Color(0xFFDC2626), Color(0xFF450A0A)]
                : const [Color(0xFFFECACA), Color(0xFFDC2626), Color(0xFF7F1D1D)],
            center: const Alignment(-0.35, -0.35),
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
      );
      if (!isBottomLayer) {
        canvas.drawCircle(Offset(x + 1.8, y - r * 0.7), 2.5, Paint()..color = const Color(0xFF22C55E));
      }
    }
  }

  // 5.D 3D KASA BANKOSU, BİLGİSAYAR VE ÇÖP KUTUSU (Doğal Görünümlü 3D Mobilya & Yumuşak Etiketler)
  void _draw3DCheckout(Canvas canvas, Rect rect, {int index = 1}) {
    _draw3DBox(
      canvas,
      baseRect: rect,
      height3D: 26,
      topColors: const [Color(0xFF475569), Color(0xFF334155)],
      frontColors: const [Color(0xFF334155), Color(0xFF1E293B)],
      sideColor: const Color(0xFF0F172A),
      radius: 12,
      borderColor: const Color(0xFF94A3B8).withValues(alpha: 0.5),
    );

    final topFace = rect.translate(0, -26);
    final beltRect = Rect.fromLTWH(topFace.left + 12, topFace.top + 14, topFace.width - 66, 48);
    canvas.drawRRect(RRect.fromRectAndRadius(beltRect, const Radius.circular(6)), Paint()..color = const Color(0xFF0F172A));

    // Hareketli Konveyör Bant Çizgileri
    final beltOffset = (engine.worldTime * 28) % 18;
    for (double bx = beltRect.left + beltOffset; bx < beltRect.right - 4; bx += 18) {
      canvas.drawLine(
        Offset(bx, beltRect.top + 3),
        Offset(bx, beltRect.bottom - 3),
        Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 1.5,
      );
    }

    // 3D Lazer Barkod Okuyucu Cam Tabla (Red Laser Barcode Scanner)
    final scannerWindow = Rect.fromCenter(
      center: Offset(beltRect.right - 26, beltRect.center.dy),
      width: 22,
      height: 36,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scannerWindow, const Radius.circular(4)),
      Paint()..color = const Color(0xFF1E1B4B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scannerWindow, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final laserPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.85)
      ..strokeWidth = 1.8;
    canvas.drawLine(
      Offset(scannerWindow.center.dx, scannerWindow.top + 3),
      Offset(scannerWindow.center.dx, scannerWindow.bottom - 3),
      laserPaint,
    );
    canvas.drawLine(
      Offset(scannerWindow.left + 3, scannerWindow.center.dy),
      Offset(scannerWindow.right - 3, scannerWindow.center.dy),
      laserPaint,
    );

    // 3D Dokunmatik POS Ekranı ve Para Çekmecesi
    final posRect = Rect.fromLTWH(beltRect.right + 8, topFace.top + 14, 38, 34);
    canvas.drawRRect(RRect.fromRectAndRadius(posRect.translate(2, 4), const Radius.circular(5)), Paint()..color = Colors.black38);
    canvas.drawRRect(RRect.fromRectAndRadius(posRect, const Radius.circular(5)), Paint()..color = const Color(0xFF1E293B));
    final bool isThisCheckoutScanning =
        engine.playerScanAnimTimer > 0.05 && engine.activePlayerCheckoutIndex == (index - 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(posRect.deflate(3), const Radius.circular(3)),
      Paint()..color = isThisCheckoutScanning ? const Color(0xFF22C55E) : const Color(0xFF38BDF8),
    );
    if (isThisCheckoutScanning && engine.currentScanningProduct != null) {
      final sDef = productCatalog[engine.currentScanningProduct!]!;
      _drawText(
        canvas,
        '${sDef.emoji}\$${sDef.retailPrice.toInt()}',
        posRect.center.dx,
        posRect.center.dy,
        fontSize: 7.5,
        color: Colors.white,
        isBold: true,
      );
    }

    // Bu kasada bekleyen müşteri varsa: Bant üzerindeki ürünleri, Barkod Okutma Lazerini ve 3D Market Poşetini çiz!
    final waitingHere = engine.customers
        .where((c) =>
            c.state == CustomerState.waitingAtCheckout &&
            c.checkoutIndex.clamp(0, engine.unlockedCheckoutCount - 1) == (index - 1))
        .toList();

    if (waitingHere.isNotEmpty) {
      final cust = waitingHere.first;
      // 1. Henüz poşetlenmemiş ürünleri konveyör bandı üzerinde çiz
      for (int bIdx = cust.packedCount; bIdx < cust.basket.length; bIdx++) {
        final prod = cust.basket[bIdx];
        final def = productCatalog[prod]!;
        final slot = bIdx - cust.packedCount;
        final ix = beltRect.left + 14.0 + (slot * 21.0);
        final iy = beltRect.center.dy;
        canvas.drawCircle(Offset(ix + 1, iy + 2), 8.5, Paint()..color = Colors.black45);
        canvas.drawCircle(Offset(ix, iy), 8.5, Paint()..color = def.primaryColor);
        _drawText(canvas, def.emoji, ix, iy, fontSize: 10.0);
      }

      // 2. Bandın sağ ucunda 3D Market Poşeti / Kese Kağıdı çiz (Ürün içine girdikçe zıplar ve şişer!)
      final isBaggingNow = cust.baggingProduct != null && cust.baggingAnimTimer > 0.0;
      final bagBounce = isBaggingNow && cust.baggingAnimTimer > 0.55
          ? sin(((cust.baggingAnimTimer - 0.55) / 0.45) * pi) * 5.0
          : 0.0;
      final bagCenter = Offset(beltRect.right - 6, beltRect.center.dy - bagBounce * 0.4);
      final bagRect = Rect.fromCenter(
        center: bagCenter,
        width: 24 + (cust.packedCount * 1.5) + bagBounce * 0.8,
        height: 28 + bagBounce,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bagRect.translate(1.5, 2.5), const Radius.circular(5)),
        Paint()..color = Colors.black45,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bagRect, const Radius.circular(5)),
        Paint()
          ..color = cust.isFullyPacked ? const Color(0xFF16A34A) : const Color(0xFFD97706),
      );
      // Poşetin içine konulmuş ürünlerin üstten görünmesi
      for (int pIdx = 0; pIdx < min(cust.packedCount, 3); pIdx++) {
        final packedType = cust.basket[pIdx];
        final pDef = productCatalog[packedType]!;
        canvas.drawCircle(
          Offset(bagCenter.dx - 5.0 + (pIdx * 5.0), bagRect.top + 3),
          4.5,
          Paint()..color = pDef.primaryColor,
        );
      }
      _drawText(canvas, cust.isFullyPacked ? '🛍️' : '🧺', bagCenter.dx, bagCenter.dy + 2, fontSize: 12.5);

      // 2.B DÜKKAN SAHİBİ BARKOD OKUTMA & POŞETE KOYMA 2 AŞAMALI CANLI ANİMASYON!
      // Aşama 1 (t < 0.55): Ürün kırmızı lazer barkod okuyucunun üstünden geçer, dükkan sahibinin elleri ürünü tutar ve "🔊 BİİP!" lazeri çakar!
      // Aşama 2 (t >= 0.55): Barkodu okunan ürün lazerden market poşetinin içine kavis çizerek girer!
      if (isBaggingNow) {
        final t = cust.baggingAnimTimer.clamp(0.0, 1.0);
        final flyDef = productCatalog[cust.baggingProduct!]!;
        final startPos = Offset(beltRect.left + 20, beltRect.center.dy);
        final scanPos = Offset(scannerWindow.center.dx, scannerWindow.center.dy - 6);
        final endPos = Offset(bagCenter.dx, bagRect.top + 4);

        late final double curX;
        late final double curY;

        if (t < 0.55) {
          final scanT = (t / 0.55).clamp(0.0, 1.0);
          curX = startPos.dx + (scanPos.dx - startPos.dx) * scanT;
          curY = startPos.dy + (scanPos.dy - startPos.dy) * scanT - sin(scanT * pi) * 10.0;

          // Kırmızı/Yeşil Lazer Tarama Hüzmesi ve Barkod Çizgileri
          final beamAlpha = sin(scanT * pi).clamp(0.0, 1.0);
          final laserFan = Path()
            ..moveTo(scannerWindow.left + 2, scannerWindow.bottom - 2)
            ..lineTo(curX - 14, curY - 12)
            ..lineTo(curX + 14, curY - 12)
            ..lineTo(scannerWindow.right - 2, scannerWindow.bottom - 2)
            ..close();
          canvas.drawPath(
            laserFan,
            Paint()
              ..color = (scanT > 0.45 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444))
                  .withValues(alpha: 0.42 * beamAlpha),
          );

          // Dükkan sahibinin (veya kasiyerin) ürünü barkoddan geçiren uzanan elleri!
          final handOrigin = Offset(rect.center.dx - 10, topFace.top + 4);
          canvas.drawLine(
            handOrigin,
            Offset(curX - 6, curY - 3),
            Paint()
              ..color = const Color(0xFFC2410C)
              ..strokeWidth = 5.5
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(curX - 6, curY - 3),
            4.2,
            Paint()..color = const Color(0xFFFBCFE8),
          );

          // Lazer üzerinde "🔊 BİİP!" Barkod Okuma Rozeti
          if (scanT > 0.25) {
            final beepBadge = Rect.fromCenter(
              center: Offset(scannerWindow.center.dx, scannerWindow.top - 16),
              width: 78,
              height: 16,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(beepBadge, const Radius.circular(8)),
              Paint()..color = const Color(0xFF16A34A),
            );
            _drawText(
              canvas,
              '🔊 BEEP! \$${flyDef.retailPrice.toInt()}',
              beepBadge.center.dx,
              beepBadge.center.dy,
              fontSize: 8.2,
              color: Colors.white,
              isBold: true,
            );
          }
        } else {
          final bagT = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
          curX = scanPos.dx + (endPos.dx - scanPos.dx) * bagT;
          curY = scanPos.dy + (endPos.dy - scanPos.dy) * bagT - sin(bagT * pi) * 22.0;

          // Yeşil onay halkası
          canvas.drawCircle(
            scannerWindow.center,
            15 * (1.0 - bagT),
            Paint()
              ..color = const Color(0xFF4ADE80).withValues(alpha: 0.5 * (1.0 - bagT))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        }

        // Havada okutulan 3D ürün ikonu + Barkod Etiketi
        canvas.drawCircle(Offset(curX, curY + 4), 11.5, Paint()..color = Colors.black38);
        canvas.drawCircle(Offset(curX, curY), 11.5, Paint()..color = flyDef.primaryColor);
        _drawText(canvas, flyDef.emoji, curX, curY - 1, fontSize: 13.5);
        // Ürün üzerindeki minik beyaz barkod etiketi (||| ||)
        final bcRect = Rect.fromCenter(center: Offset(curX, curY + 7.5), width: 12, height: 4.5);
        canvas.drawRRect(RRect.fromRectAndRadius(bcRect, const Radius.circular(1)), Paint()..color = Colors.white);
        for (double lx = bcRect.left + 2; lx < bcRect.right - 1; lx += 2.2) {
          canvas.drawLine(
            Offset(lx, bcRect.top + 0.8),
            Offset(lx, bcRect.bottom - 0.8),
            Paint()
              ..color = Colors.black87
              ..strokeWidth = 0.9,
          );
        }
      }

      // 3. Kasa üzerinde canlı Barkod Okutma / Teslim Etme rozeti
      final bob = sin(engine.worldTime * 5.0) * 2.5;
      final promptRect = Rect.fromCenter(
        center: Offset(topFace.center.dx, topFace.top - 14 + bob),
        width: 184,
        height: 24,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(promptRect.translate(0, 2), const Radius.circular(10)),
        Paint()..color = Colors.black54,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(promptRect, const Radius.circular(10)),
        Paint()
          ..color = cust.isFullyPacked ? const Color(0xFF15803D) : const Color(0xFFB45309),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(promptRect, const Radius.circular(10)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      _drawText(
        canvas,
        cust.isFullyPacked
            ? '✅ Hand Over Package & Take Payment [Click]'
            : '🔊 Scan Barcode (${cust.packedCount}/${cust.basket.length}) [Click]',
        promptRect.center.dx,
        promptRect.center.dy,
        fontSize: 9.0,
        color: Colors.white,
        isBold: true,
      );
    }

    // Doğal Yumuşak Kasa Etiketi
    _drawNaturalWorldButton(
      canvas,
      center: Offset(topFace.center.dx, topFace.bottom - 15),
      label: '🛎️ Register ${index}',
      width: 86,
      height: 20,
    );
  }

  /// 📦 3D KURYE SİPARİŞ PAKETLEME İSTASYONU (Kasalardan ayrı özel kurye paketleme bölgesi!)
  void _draw3DCourierPackingDesk(Canvas canvas) {
    final rect = engine.courierPackingDesk;

    // Kasalardan ayrı özel paketleme bölgesi zemin matı
    final zoneRect = rect.inflate(16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(zoneRect, const Radius.circular(14)),
      Paint()..color = const Color(0xFF3B0764).withValues(alpha: 0.22),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(zoneRect, const Radius.circular(14)),
      Paint()
        ..color = const Color(0xFFFACC15).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    if (engine.isCourierPackingDeskHovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(8), const Radius.circular(16)),
        Paint()
          ..color = const Color(0xFFFACC15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
    }

    _draw3DBox(
      canvas,
      baseRect: rect,
      height3D: 24,
      topColors: const [Color(0xFF5B21B6), Color(0xFF3B0764)],
      frontColors: const [Color(0xFF4C1D95), Color(0xFF2E1065)],
      sideColor: const Color(0xFF1E1B4B),
      radius: 10,
      borderColor: const Color(0xFFFACC15).withValues(alpha: 0.75),
    );

    final topFace = rect.translate(0, -24);

    // Paketleme Tezgahı Kesim Matı (Sarı Çizgili Çalışma Alanı)
    final matRect = Rect.fromLTWH(topFace.left + 12, topFace.top + 10, topFace.width - 58, topFace.height - 26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(matRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF1E1B4B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(matRect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFFFACC15).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Sağda 3D Koli Bandı Makinesi (Tape Dispenser) ve Etiket Yazıcısı
    final tapeRect = Rect.fromLTWH(matRect.right + 10, topFace.top + 14, 28, 22);
    canvas.drawRRect(RRect.fromRectAndRadius(tapeRect, const Radius.circular(5)), Paint()..color = const Color(0xFFF59E0B));
    canvas.drawCircle(tapeRect.center, 6.0, Paint()..color = const Color(0xFF78350F));
    _drawText(canvas, '🎗️', tapeRect.center.dx, tapeRect.center.dy - 1, fontSize: 10);

    // Masanın üzerindeki Kurye Kolisi (Boş açık koli veya paketlenen koli!)
    final boxCenter = matRect.center;
    final bool isPacking = engine.courierStagedCount > 0;
    final double prog = engine.courierPackingProgress.clamp(0.0, 1.0);
    final double bounce = isPacking ? sin(engine.worldTime * 18.0) * 2.0 : 0.0;

    final packBoxRect = Rect.fromCenter(
      center: Offset(boxCenter.dx, boxCenter.dy + bounce),
      width: 44,
      height: 28,
    );
    _draw3DBox(
      canvas,
      baseRect: packBoxRect,
      height3D: 12,
      topColors: isPacking
          ? const [Color(0xFFFACC15), Color(0xFFEAB308)]
          : const [Color(0xFFD97706), Color(0xFFB45309)],
      frontColors: const [Color(0xFF92400E), Color(0xFF78350F)],
      radius: 5,
      castShadow: false,
    );

    if (isPacking && engine.courierStagedProduct != null) {
      final sDef = productCatalog[engine.courierStagedProduct!]!;
      final ord = engine.activeCourierOrder;
      final bool isFull = ord != null && engine.courierStagedCount >= ord.remainingQty;
      // Koli kapanırken üstünden geçen sarı-mor kurye emniyet bandı
      if (isFull && prog > 0.25) {
        final tapeW = packBoxRect.width * ((prog - 0.25) / 0.75).clamp(0.0, 1.0);
        canvas.drawRect(
          Rect.fromLTWH(packBoxRect.left, packBoxRect.center.dy - 8, tapeW, 5),
          Paint()..color = const Color(0xFF7C3AED),
        );
      }
      _drawText(
        canvas,
        '${sDef.emoji}x${engine.courierStagedCount}',
        packBoxRect.center.dx,
        packBoxRect.center.dy - 7,
        fontSize: 10.0,
        color: Colors.white,
        isBold: true,
      );

      // Paketleme İlerleme Çubuğu veya Bekleyen Eksik Ürün Rozeti
      final barRect = Rect.fromCenter(center: Offset(topFace.center.dx, topFace.top - 14), width: 176, height: 22);
      canvas.drawRRect(RRect.fromRectAndRadius(barRect, const Radius.circular(10)), Paint()..color = const Color(0xFF0F172A));
      if (isFull) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barRect.left + 2, barRect.top + 2, (barRect.width - 4) * prog, barRect.height - 4),
            const Radius.circular(8),
          ),
          Paint()..color = const Color(0xFF22C55E),
        );
        _drawText(
          canvas,
          '📦 Taping Courier Package ${(prog * 100).toInt()}%',
          barRect.center.dx,
          barRect.center.dy,
          fontSize: 8.8,
          color: Colors.white,
          isBold: true,
        );
      } else if (ord != null) {
        final ratio = (engine.courierStagedCount / max(1, ord.remainingQty)).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barRect.left + 2, barRect.top + 2, (barRect.width - 4) * ratio, barRect.height - 4),
            const Radius.circular(8),
          ),
          Paint()..color = const Color(0xFFF59E0B),
        );
        _drawText(
          canvas,
          '📦 On Table: ${engine.courierStagedCount}/${ord.remainingQty} ${sDef.emoji} (${ord.remainingQty - engine.courierStagedCount} more)',
          barRect.center.dx,
          barRect.center.dy,
          fontSize: 8.6,
          color: Colors.white,
          isBold: true,
        );
      }
    } else if (engine.courierState == CourierState.waitingForOrder && engine.activeCourierOrder != null) {
      final ord = engine.activeCourierOrder!;
      final def = productCatalog[ord.productType]!;
      final heldMatch = engine.carriedBox != null &&
          !engine.carriedBox!.isCourierPackage &&
          engine.carriedBox!.productType == ord.productType;
      final totalWithHeld = engine.courierStagedCount + (heldMatch ? engine.carriedBox!.currentCount : 0);
      final isExcess = heldMatch && totalWithHeld > ord.remainingQty;
      final bob = sin(engine.worldTime * 4.5) * 2.2;
      final badgeRect = Rect.fromCenter(
        center: Offset(topFace.center.dx, topFace.top - 13 + bob),
        width: 184,
        height: 22,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(10)),
        Paint()..color = (isExcess ? const Color(0xFF991B1B) : const Color(0xFF4C1D95)).withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(10)),
        Paint()
          ..color = isExcess ? Colors.redAccent : const Color(0xFFFACC15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _drawText(
        canvas,
        isExcess
            ? '⚠️ TOO MANY! (${totalWithHeld}/${ord.remainingQty} ${def.emoji}) [Click]'
            : '📦 ${ord.requiredQty}x ${def.emoji} Courier Packing [Click]',
        badgeRect.center.dx,
        badgeRect.center.dy,
        fontSize: 8.8,
        color: isExcess ? Colors.white : const Color(0xFFFDE047),
        isBold: true,
      );
    }

    _drawNaturalWorldButton(
      canvas,
      center: Offset(topFace.center.dx, topFace.bottom - 12),
      label: '📦 Courier Packing',
      width: 118,
      height: 19,
    );
  }

  /// 🥚✨ Oyuncu, Stokçu veya Müşteri raflara tek tek ürün dizerken / alırken havada kavis çizen ürünler
  void _drawFlyingShelfItems(Canvas canvas) {
    for (final item in engine.flyingShelfItems) {
      final t = item.progress.clamp(0.0, 1.0);
      final def = productCatalog[item.productType]!;
      final curX = item.startPos.dx + (item.endPos.dx - item.startPos.dx) * t;
      final curY = item.startPos.dy + (item.endPos.dy - item.startPos.dy) * t - sin(t * pi) * 26.0;

      canvas.drawCircle(Offset(curX, curY + 4), 9.5, Paint()..color = Colors.black38);
      if (item.productType == SimProductType.egg) {
        _draw3DSingleEggItem(canvas, curX, curY, scale: 1.15);
      } else {
        canvas.drawCircle(Offset(curX, curY), 9.5, Paint()..color = def.primaryColor);
        _drawText(canvas, def.emoji, curX, curY, fontSize: 11.5);
      }
    }
  }

  void _draw3DDesk(Canvas canvas, Rect rect) {
    // Masa Arkası 3D Ofis Koltuğu
    final chairCenter = Offset(rect.center.dx, rect.top - 18);
    canvas.drawCircle(chairCenter.translate(2, 4), 18, Paint()..color = Colors.black38);
    canvas.drawCircle(chairCenter, 18, Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(chairCenter.dx, chairCenter.dy - 8), width: 28, height: 10), const Radius.circular(5)),
      Paint()..color = const Color(0xFF0F172A),
    );

    // Doğal Ahşap Ofis Masası
    _draw3DBox(
      canvas,
      baseRect: rect,
      height3D: 24,
      topColors: const [Color(0xFFB45309), Color(0xFF92400E)],
      frontColors: const [Color(0xFF78350F), Color(0xFF451A03)],
      sideColor: const Color(0xFF290F02),
      radius: 10,
      borderColor: const Color(0xFFD97706).withValues(alpha: 0.6),
    );

    final topFace = rect.translate(0, -24);

    // 3D Bilgisayar Monitörü, Standı, Klavye ve Mouse
    final monitorRect = Rect.fromCenter(center: Offset(topFace.center.dx - 10, topFace.top + 26), width: 64, height: 32);
    canvas.drawRRect(RRect.fromRectAndRadius(monitorRect.translate(2, 4), const Radius.circular(6)), Paint()..color = Colors.black38);
    canvas.drawRRect(RRect.fromRectAndRadius(monitorRect, const Radius.circular(6)), Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      RRect.fromRectAndRadius(monitorRect.deflate(3), const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(monitorRect),
    );
    // Klavye ve Mouse
    final kbRect = Rect.fromCenter(center: Offset(topFace.center.dx - 10, topFace.top + 50), width: 42, height: 11);
    canvas.drawRRect(RRect.fromRectAndRadius(kbRect, const Radius.circular(3)), Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawOval(Rect.fromCenter(center: Offset(topFace.center.dx + 22, topFace.top + 50), width: 8, height: 11), Paint()..color = const Color(0xFFE2E8F0));

    // Kahve Kupası
    canvas.drawCircle(Offset(topFace.right - 26, topFace.top + 28), 6.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(topFace.right - 26, topFace.top + 28), 4.5, Paint()..color = const Color(0xFF78350F));

    // Doğal Görünümlü "Bilgisayar" Tuşu Etiketi
    _drawNaturalWorldButton(
      canvas,
      center: Offset(topFace.center.dx, topFace.bottom - 14),
      label: '💻 Computer',
      width: 96,
      height: 21,
    );
  }

  /// Oyun içi nesnelerin üzerinde doğal, yumuşak kabartmalı tuş görünümü çizer
  void _drawNaturalWorldButton(
    Canvas canvas, {
    required Offset center,
    required String label,
    required double width,
    required double height,
  }) {
    final btnRect = Rect.fromCenter(center: center, width: width, height: height);
    // Alt 3D tuş kalınlığı (Bevel)
    canvas.drawRRect(
      RRect.fromRectAndRadius(btnRect.translate(0, 2.5), const Radius.circular(8)),
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.85),
    );
    // Doğal mat krem/taş tuş yüzeyi
    canvas.drawRRect(
      RRect.fromRectAndRadius(btnRect, const Radius.circular(8)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(btnRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(btnRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _drawText(canvas, label, center.dx, center.dy, fontSize: 9.8, color: const Color(0xFF1E293B), isBold: true);
  }

  void _draw3DTrashCan(Canvas canvas, Rect rect) {
    final center = rect.center;
    _drawSoftShadow(canvas, Rect.fromCircle(center: center, radius: 28), radius: 28, offsetX: 6, offsetY: 10, blur: 8);
    canvas.drawCircle(
      center,
      28,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF64748B), Color(0xFF334155), Color(0xFF0F172A)],
          center: Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: center, radius: 28)),
    );
    canvas.drawCircle(center, 19, Paint()..color = const Color(0xFF090D16));
    _drawText(canvas, '🗑️', center.dx, center.dy, fontSize: 18);
  }

  void _drawShelfStockBar(Canvas canvas, Rect rect, int current, int maxCap) {
    final ratio = (current / maxCap).clamp(0.0, 1.0);
    final bgRect = Rect.fromLTWH(rect.left + 12, rect.bottom - 18, rect.width - 24, 12);
    // 3D Yuvalı Gömme Stok Çubuğu
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect.inflate(1.5), const Radius.circular(6)),
      Paint()..color = const Color(0xFF475569),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF020617),
    );

    final barColors = ratio < 0.25
        ? const [Color(0xFFF87171), Color(0xFFDC2626)]
        : ratio < 0.6
            ? const [Color(0xFFFDE047), Color(0xFFD97706)]
            : const [Color(0xFF4ADE80), Color(0xFF16A34A)];

    if (ratio > 0) {
      final fillRect = Rect.fromLTWH(bgRect.left + 1.5, bgRect.top + 1.5, (bgRect.width - 3) * ratio, bgRect.height - 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            colors: barColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(fillRect),
      );
    }

    _drawText(
      canvas,
      'STOCK: ${current} / ${maxCap}',
      bgRect.center.dx,
      bgRect.center.dy,
      fontSize: 8.2,
      color: Colors.white,
      isBold: true,
    );
  }

  // =========================================================================
  // 6. DERİNLİK SIRALI (Y-SORTED) 3D RAFLAR & İNSAN KARAKTERLERİ
  // =========================================================================
  void _drawCharactersSorted(Canvas canvas) {
    final List<void Function()> drawables = [];
    final List<double> yCoords = [];

    void addDrawable(double y, void Function() fn) {
      int idx = 0;
      while (idx < yCoords.length && yCoords[idx] <= y) {
        idx++;
      }
      yCoords.insert(idx, y);
      drawables.insert(idx, fn);
    }

    // Sadece kilidi açılmış 3D Reyonlar ve Raflar ön taban hizasına göre Y-sıralamasına girer
    for (final shelf in engine.shelves) {
      if (shelf.isUnlocked) {
        addDrawable(shelf.rect.bottom - 10, () => _drawSingleShelf3D(canvas, shelf));
      }
    }

    // 3D Bilgisayar Masası, Kurye Paketleme Masası ve Açık Kasa Bankoları da derinlik sıralamasına girer
    addDrawable(engine.computerDesk.bottom - 8, () => _draw3DDesk(canvas, engine.computerDesk));
    addDrawable(engine.courierPackingDesk.bottom - 8, () => _draw3DCourierPackingDesk(canvas));

    // Otomatik Kasiyer Karakterleri (Açık Kasaların Arkasında)
    if (engine.hasAutoCashier) {
      final cashierNames = ['CASHIER AYŞE', 'CASHIER MERT', 'CASHIER ZEYNEP'];
      for (int i = 0; i < engine.unlockedCheckoutCount; i++) {
        final cRect = engine.checkoutCounters[i];
        final cName = cashierNames[i % cashierNames.length];
        addDrawable(cRect.top - 6, () {
          _draw3DHumanCharacter(
            canvas: canvas,
            x: cRect.center.dx - 10,
            y: cRect.top - 12,
            name: cName,
            shirtColor: const Color(0xFF0284C7),
            pantsColor: const Color(0xFF1E293B),
            hairColor: const Color(0xFF92400E),
            walkOffset: sin(engine.worldTime * 3.0 + i) * 0.2,
          );
        });
      }
    }

    for (int i = 0; i < engine.unlockedCheckoutCount; i++) {
      final cRect = engine.checkoutCounters[i];
      final idx = i + 1;
      addDrawable(cRect.bottom - 8, () => _draw3DCheckout(canvas, cRect, index: idx));
    }

    // 👷 3D Otomatik Reyon & Çiftlik Görevlisi (Stokçu Ali - Sadece Seviye 3'te işe alındığında görünür)
    if (engine.hasRestocker && engine.isRestockerHired) {
      addDrawable(engine.restocker.y, () => _drawRestockerWorker(canvas));
    }

    for (final c in engine.customers) {
      addDrawable(c.y, () => _drawSingleCustomer(canvas, c));
    }

    for (final t in engine.thieves) {
      addDrawable(t.y, () => _drawThief(canvas, t));
    }

    addDrawable(engine.playerY, () => _drawPlayer(canvas));

    for (final fn in drawables) {
      fn();
    }
  }

  void _drawRestockerWorker(Canvas canvas) {
    final w = engine.restocker;
    final walkCycle = sin(w.walkTimer);

    _draw3DHumanCharacter(
      canvas: canvas,
      x: w.x,
      y: w.y,
      name: '👷 STOCKER ALI',
      shirtColor: const Color(0xFF0891B2),
      pantsColor: const Color(0xFF0F172A),
      hairColor: const Color(0xFFF59E0B),
      walkOffset: walkCycle,
    );

    if (w.equippedTool != null) {
      _drawCharacterEquippedTool(
        canvas,
        x: w.x,
        y: w.y,
        tool: w.equippedTool!,
        actionAnimTimer: w.actionAnimTimer,
        isHarvesting: w.statusText.contains('Cutting') ||
            w.statusText.contains('Milking') ||
            w.statusText.contains('Collecting'),
        carriedBox: w.carriedBox,
      );
    }

    if (w.carriedBox != null) {
      _drawCarriedContainer(canvas, w.x, w.y - 48, w.carriedBox!);
    } else {
      _drawThoughtBubble(canvas, w.statusText, w.x, w.y - 58);
    }
  }

  void _drawSingleCustomer(Canvas canvas, SimCustomer c) {
    if (c.isVip || c.archetype == CustomerArchetype.chef) {
      // 👑 VIP veya 👨‍🍳 Gurme Şef Işıltı Halesi (Blur filtresiz)
      final haloColor = c.isVip ? const Color(0xFFFACC15) : const Color(0xFF38BDF8);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.x, c.y + 15), width: 54, height: 25),
        Paint()..color = haloColor.withValues(alpha: 0.22),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.x, c.y + 15), width: 48, height: 21),
        Paint()
          ..color = haloColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // Müşteri tipine özel kıyafet ve saç renkleri
    Color shirtColor;
    Color pantsColor = const Color(0xFF1E293B);
    Color hairColor = const Color(0xFF451A03);

    switch (c.archetype) {
      case CustomerArchetype.vip:
        shirtColor = const Color(0xFFCA8A04);
        pantsColor = const Color(0xFF090D16);
        hairColor = const Color(0xFF1E293B);
        break;
      case CustomerArchetype.chef:
        shirtColor = const Color(0xFFF8FAFC); // Beyaz aşçı ceketi
        pantsColor = const Color(0xFF334155);
        hairColor = const Color(0xFF292524);
        break;
      case CustomerArchetype.grandma:
        shirtColor = const Color(0xFF9333EA); // Mor hırka
        pantsColor = const Color(0xFF475569);
        hairColor = const Color(0xFFE2E8F0); // Gümüş/beyaz saç
        break;
      case CustomerArchetype.athlete:
        shirtColor = const Color(0xFFEF4444); // Kırmızı spor forma
        pantsColor = const Color(0xFF0F172A);
        hairColor = const Color(0xFF92400E);
        break;
      case CustomerArchetype.student:
        shirtColor = const Color(0xFF2563EB); // Mavi kapüşonlu
        pantsColor = const Color(0xFF1E3A8A);
        hairColor = const Color(0xFF78350F);
        break;
      case CustomerArchetype.family:
        shirtColor = const Color(0xFF059669); // Zümrüt yeşili
        pantsColor = const Color(0xFF1E293B);
        hairColor = const Color(0xFF451A03);
        break;
      case CustomerArchetype.regular:
        final palette = [
          const Color(0xFF0D9488),
          const Color(0xFFDB2777),
          const Color(0xFFD97706),
        ];
        shirtColor = palette[c.id.hashCode.abs() % palette.length];
        break;
    }

    final walkCycle = sin(engine.worldTime * 9.5 * c.speedMultiplier + c.id.hashCode);

    // 🎒 Öğrenci ise sırtta 3D çanta çiz
    if (c.archetype == CustomerArchetype.student) {
      final packRect = Rect.fromCenter(center: Offset(c.x - 11, c.y - 3), width: 12, height: 18);
      canvas.drawRRect(RRect.fromRectAndRadius(packRect, const Radius.circular(4)), Paint()..color = const Color(0xFFD97706));
    }

    _draw3DHumanCharacter(
      canvas: canvas,
      x: c.x,
      y: c.y,
      name: c.archetypeBadge,
      shirtColor: shirtColor,
      pantsColor: pantsColor,
      hairColor: hairColor,
      walkOffset: walkCycle,
      hasBasket: c.basket.isNotEmpty && c.state != CustomerState.leavingHappy,
    );

    // Müşteri kasadan paketini alıp çıkarken elinde paketlenmiş 3D Market Poşeti (🛍️) taşır!
    if (c.state == CustomerState.leavingHappy) {
      final bagX = c.x + 19;
      final bagY = c.y + 6;
      final bagRect = Rect.fromCenter(center: Offset(bagX, bagY), width: 16, height: 18);
      canvas.drawRRect(RRect.fromRectAndRadius(bagRect.translate(1.5, 2.5), const Radius.circular(4)), Paint()..color = Colors.black38);
      canvas.drawRRect(RRect.fromRectAndRadius(bagRect, const Radius.circular(4)), Paint()..color = const Color(0xFF16A34A));
      _drawText(canvas, '🛍️', bagX, bagY - 1, fontSize: 10.5);
    }

    // Arketipe Özel 3D Şapka / Baston / Aksesuar Çizimleri
    if (c.archetype == CustomerArchetype.chef) {
      // 👨‍🍳 Uzun Beyaz 3D Aşçı Şapkası (Toque)
      final hatRect = Rect.fromCenter(center: Offset(c.x, c.y - 35), width: 18, height: 14);
      canvas.drawRRect(RRect.fromRectAndRadius(hatRect, const Radius.circular(6)), Paint()..color = Colors.white);
      canvas.drawCircle(Offset(c.x - 4, c.y - 41), 6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(c.x + 4, c.y - 41), 6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(c.x, c.y - 43), 6.5, Paint()..color = const Color(0xFFF8FAFC));
    } else if (c.archetype == CustomerArchetype.grandma) {
      // 👵👴 Tonton Nine/Dede Elinde Ahşap Baston ve Gözlük
      canvas.drawLine(
        Offset(c.x - 17, c.y + 4),
        Offset(c.x - 19, c.y + 20),
        Paint()
          ..color = const Color(0xFF78350F)
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(c.x - 4, c.y - 20), 3.2, Paint()..color = Colors.amber.shade200..style = PaintingStyle.stroke..strokeWidth = 1.2);
      canvas.drawCircle(Offset(c.x + 4, c.y - 20), 3.2, Paint()..color = Colors.amber.shade200..style = PaintingStyle.stroke..strokeWidth = 1.2);
    } else if (c.archetype == CustomerArchetype.athlete) {
      // 🏃 Sporcu Kafa Bandı
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(c.x, c.y - 26), width: 24, height: 4.5), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFACC15),
      );
    } else if (c.archetype == CustomerArchetype.student) {
      // 🎒 Öğrenci Kep Şapkası
      canvas.drawArc(
        Rect.fromCircle(center: Offset(c.x, c.y - 23), radius: 13),
        pi,
        pi,
        true,
        Paint()..color = const Color(0xFFEA580C),
      );
    } else if (c.isVip) {
      _drawText(canvas, '👑', c.x, c.y - 36, fontSize: 14);
    }

    if (c.state == CustomerState.walkingToEntrance) {
      if (c.y >= 210 && c.y <= 285) {
        _drawThoughtBubble(canvas, '${c.avatar} Hello!', c.x, c.y - 62);
      } else {
        _drawThoughtBubble(canvas, '${c.avatar} Shopping', c.x, c.y - 62);
      }
    } else if (c.state == CustomerState.shopping && c.currentShoppingIndex < c.shoppingList.length) {
      final wanted = c.shoppingList[c.currentShoppingIndex];
      final def = productCatalog[wanted]!;
      _drawThoughtBubble(canvas, '${def.emoji} ${def.name}', c.x, c.y - 62);
    } else if (c.state == CustomerState.goingToCheckout) {
      _drawThoughtBubble(canvas, '🛍️ To Register', c.x, c.y - 62);
    } else if (c.state == CustomerState.waitingAtCheckout) {
      if (c.isFullyPacked) {
        _drawThoughtBubble(canvas, '💵 Payment Ready!', c.x, c.y - 62);
      } else {
        _drawThoughtBubble(canvas, '🛍️ Packing (${c.packedCount}/${c.basket.length})', c.x, c.y - 62);
      }
    } else if (c.state == CustomerState.leavingSad) {
      _drawThoughtBubble(canvas, '😞 Out of Stock', c.x, c.y - 62);
    } else if (c.state == CustomerState.leavingHappy) {
      _drawThoughtBubble(canvas, '🛍️ Thanks!', c.x, c.y - 62);
    }
  }

  void _drawPlayer(Canvas canvas) {
    final x = engine.playerX;
    final y = engine.playerY;

    // Oyuncu 3D Seçim Halesi (Blur filtresiz)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y + 14), width: 60, height: 29),
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.18),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y + 14), width: 54, height: 25),
      Paint()
        ..color = const Color(0xFFEA580C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );

    final isMoving = engine.moveDirX != 0 || engine.moveDirY != 0 || engine.targetMoveX != null;
    final walkCycle = isMoving ? sin(engine.walkAnimTime * 12) : 0.0;

    _draw3DHumanCharacter(
      canvas: canvas,
      x: x,
      y: y,
      name: '⭐ MANAGER',
      shirtColor: const Color(0xFFC2410C),
      pantsColor: const Color(0xFF0F172A),
      hairColor: const Color(0xFF1E293B),
      walkOffset: walkCycle,
      isPlayer: true,
    );

    if (engine.playerTool != null) {
      _drawCharacterEquippedTool(
        canvas,
        x: x,
        y: y,
        tool: engine.playerTool!,
        actionAnimTimer: engine.playerActionAnimTimer,
        isHarvesting: engine.activeHarvestSpot != null,
        carriedBox: engine.carriedBox,
      );
    }

    if (engine.carriedBox != null) {
      _drawCarriedContainer(canvas, x, y - 50, engine.carriedBox!);
    }

    _drawPlayerStick(canvas, x, y);
  }

  /// The wooden stick: held at night, swung when the player attacks.
  void _drawPlayerStick(Canvas canvas, double x, double y) {
    final swinging = engine.stickSwingTimer > 0;
    if (!engine.isNight && !swinging) return;

    final dir = swinging ? engine.stickHitDirX : (cos(engine.playerAngle) >= 0 ? 1.0 : -1.0);
    final t = 1.0 - engine.stickSwingTimer;
    final pivot = Offset(x + dir * 13, y + 2);
    const len = 42.0;

    void stickAt(double a, double alpha) {
      final tip = Offset(pivot.dx + dir * sin(a) * len, pivot.dy - cos(a) * len);
      canvas.drawLine(
        pivot,
        tip,
        Paint()
          ..color = const Color(0xFF92400E).withValues(alpha: alpha)
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(pivot.dx + dir * sin(a) * len * 0.55, pivot.dy - cos(a) * len * 0.55),
        tip,
        Paint()
          ..color = const Color(0xFFD97706).withValues(alpha: alpha)
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );
    }

    if (swinging) {
      final a = -0.6 + t * 2.6;
      stickAt(a - 0.5, 0.18);
      stickAt(a - 0.25, 0.32);
      stickAt(a, 1.0);
    } else {
      stickAt(0.35, 1.0);
    }
  }

  /// A masked thief: dark clothes, sack of loot, HP bar and hit flash.
  void _drawThief(Canvas canvas, Thief t) {
    final isStunned = t.state == ThiefState.stunned;
    final walk = (t.state == ThiefState.stealing || isStunned) ? 0.0 : sin(t.walkAnim);

    _draw3DHumanCharacter(
      canvas: canvas,
      x: t.x,
      y: t.y,
      name: '🦹 THIEF',
      shirtColor: const Color(0xFF1F2937),
      pantsColor: const Color(0xFF111827),
      hairColor: const Color(0xFF000000),
      walkOffset: walk,
    );

    // Eye mask
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(t.x, t.y - 29), width: 22, height: 6),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF020617),
    );

    if (t.hitFlash > 0) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(t.x, t.y - 10), width: 34, height: 62),
        Paint()..color = Colors.white.withValues(alpha: 0.6 * t.hitFlash),
      );
    }

    // HP bar
    final barRect = Rect.fromCenter(center: Offset(t.x, t.y - 62), width: 38, height: 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );
    final frac = (t.hp / t.maxHp).clamp(0.0, 1.0).toDouble();
    if (frac > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barRect.left, barRect.top, barRect.width * frac, barRect.height),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFFEF4444),
      );
    }

    if (t.carried > 0 && t.loot != null) {
      final emoji = productCatalog[t.loot!]?.emoji ?? '';
      _drawText(canvas, '🎒 $emoji x${t.carried}', t.x, t.y - 76, fontSize: 12, color: Colors.white, isBold: true);
    }
    if (isStunned) {
      _drawText(canvas, '💫', t.x, t.y - 50, fontSize: 16);
    }
  }

  /// Dark blue tint over the whole world at night, with warm lamp glows.
  void _drawNightOverlay(Canvas canvas) {
    final d = engine.nightDarkness;
    if (d <= 0.01) return;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, engine.worldWidth, engine.worldHeight),
      Paint()..color = const Color(0xFF0B1230).withValues(alpha: 0.6 * d),
    );

    void glow(double cx, double cy, double r, Color c, double a) {
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: a * d), Colors.transparent],
          ).createShader(rect),
      );
    }

    for (final lx in [420.0, 780.0, 1140.0, 1520.0]) {
      for (final ly in [390.0, 650.0, 880.0]) {
        glow(lx, ly, 170, const Color(0xFFFDE68A), 0.22);
      }
    }
    // Lantern around the player
    glow(engine.playerX, engine.playerY, 130, const Color(0xFFFFEDD5), 0.20);
  }

  /// Karakterin Elindeki Süt Kovası, Tırpan veya Yumurta Kovasını Çizer
  void _drawCharacterEquippedTool(
    Canvas canvas, {
    required double x,
    required double y,
    required FarmToolType tool,
    required double actionAnimTimer,
    required bool isHarvesting,
    required CarriedBox? carriedBox,
  }) {
    if (tool == FarmToolType.scythe) {
      final swing = isHarvesting ? sin(actionAnimTimer) * 0.95 : -0.25;
      // Tırpan sallanırken altın biçme izi efekti
      if (isHarvesting) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(x + 12, y - 2), width: 52, height: 34),
          -0.8,
          1.6,
          false,
          Paint()
            ..color = const Color(0xFFFDE047).withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );
      }
      _draw3DScytheIcon(canvas, x + 22, y + 2, angle: swing, scale: 1.15);
    } else if (tool == FarmToolType.milkBucket) {
      final bob = isHarvesting ? sin(actionAnimTimer) * 2.5 : 0.0;
      final hasMilk = carriedBox != null && carriedBox.productType == SimProductType.milk && carriedBox.currentCount > 0;
      _draw3DMilkBucketIcon(canvas, x + 21, y + 6 + bob, scale: 1.05, hasMilk: hasMilk);
    } else if (tool == FarmToolType.eggBucket) {
      final bob = isHarvesting ? sin(actionAnimTimer) * 2.5 : 0.0;
      final hasEggs = carriedBox != null && carriedBox.productType == SimProductType.egg && carriedBox.currentCount > 0;
      _draw3DEggBucketIcon(canvas, x + 21, y + 6 + bob, scale: 1.05, hasEggs: hasEggs);
    }
  }

  /// Karakterin Taşıdığı Biçilmiş Buğday Demeti, Süt, Yumurta, Peynir, Kurye Paketi veya Koliyi Çizer
  void _drawCarriedContainer(Canvas canvas, double bx, double by, CarriedBox box) {
    final def = productCatalog[box.productType]!;

    if (box.isCourierPackage) {
      // 📦 Karakterin Elinde Mühürlü ve Bantlı 3D Kurye Sipariş Paketi
      final handY = by + 50;
      final pkgRect = Rect.fromCenter(center: Offset(bx, handY + 2), width: 32, height: 22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pkgRect.translate(2, 3), const Radius.circular(5)),
        Paint()..color = Colors.black38,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pkgRect, const Radius.circular(5)),
        Paint()..color = const Color(0xFF7C3AED),
      );
      // Sarı Kurye Bandı (Yatay & Dikey Şerit)
      canvas.drawRect(
        Rect.fromCenter(center: Offset(bx, handY + 2), width: 32, height: 5),
        Paint()..color = const Color(0xFFFACC15),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(bx, handY + 2), width: 5, height: 22),
        Paint()..color = const Color(0xFFFACC15),
      );
      _drawText(canvas, '🛵', bx, handY + 1, fontSize: 11);

      // Baş Üstü Kurye Paketi Bilgi Rozeti
      final badgeRect = Rect.fromCenter(center: Offset(bx, by), width: 122, height: 26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect.translate(0, 3), const Radius.circular(8)),
        Paint()..color = const Color(0xFF4C1D95),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFF6D28D9),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
        Paint()
          ..color = const Color(0xFFFACC15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      _drawText(
        canvas,
        '📦 Courier Package (${box.currentCount} ${def.emoji})',
        bx,
        by,
        fontSize: 9.5,
        color: Colors.white,
        isBold: true,
      );
      return;
    }

    if (box.isPickedFromShelf) {
      // 🖐️ Dolaptan tek tek alınmış elde taşınan ürünler
      final handY = by + 50;
      final basketRect = Rect.fromCenter(center: Offset(bx, handY + 2), width: 28, height: 15);
      canvas.drawRRect(
        RRect.fromRectAndRadius(basketRect.translate(1, 2), const Radius.circular(5)),
        Paint()..color = Colors.black38,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(basketRect, const Radius.circular(5)),
        Paint()..color = def.primaryColor,
      );
      _drawText(canvas, def.emoji, bx, handY + 1, fontSize: 12);

      final pillRect = Rect.fromCenter(center: Offset(bx, by - 4), width: 72, height: 22);
      canvas.drawRRect(RRect.fromRectAndRadius(pillRect.translate(0, 2), const Radius.circular(11)), Paint()..color = Colors.black45);
      canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(11)), Paint()..color = const Color(0xFF0F172A));
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(11)),
        Paint()
          ..color = const Color(0xFF38BDF8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _drawText(
        canvas,
        '${def.emoji} x${box.currentCount}',
        bx,
        by - 4,
        fontSize: 11.0,
        isBold: true,
        color: Colors.white,
      );
      return;
    }

    if (box.isFromFarm) {
      // Karakterin kucağında / ellerinde 3D ürün demeti çizimi (Tırpan/kova bırakıldıktan sonra elde görünür!)
      final handY = by + 50;
      if (box.productType == SimProductType.flour) {
        // 🌾 Karakterin Elinde 3D Altın Buğday Demeti (Sapları ve Başakları Bağlanmış)
        for (final angle in [-0.45, -0.22, 0.0, 0.22, 0.45]) {
          canvas.save();
          canvas.translate(bx, handY + 2);
          canvas.rotate(angle);
          canvas.drawLine(
            const Offset(0, 10),
            const Offset(0, -14),
            Paint()
              ..color = const Color(0xFFCA8A04)
              ..strokeWidth = 2.8
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawOval(
            Rect.fromCenter(center: const Offset(0, -14), width: 7.5, height: 13),
            Paint()..color = const Color(0xFFFACC15),
          );
          canvas.restore();
        }
        // Buğday demetini ortadan bağlayan kırmızı kuşak
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, handY + 2), width: 18, height: 5), const Radius.circular(3)),
          Paint()..color = const Color(0xFFDC2626),
        );
      } else if (box.productType == SimProductType.milk) {
        // 🥛 Elde Taze Süt Şişeleri Kasası
        final crate = Rect.fromCenter(center: Offset(bx, handY + 2), width: 28, height: 14);
        canvas.drawRRect(RRect.fromRectAndRadius(crate, const Radius.circular(4)), Paint()..color = const Color(0xFF0284C7));
        for (final ox in [-7.0, 0.0, 7.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx + ox, handY - 3), width: 5.5, height: 11), const Radius.circular(2)),
            Paint()..color = Colors.white,
          );
        }
      } else if (box.productType == SimProductType.egg) {
        // 🥚 Elde Köy Yumurtası Sepeti
        final basket = Rect.fromCenter(center: Offset(bx, handY + 3), width: 26, height: 13);
        canvas.drawRRect(RRect.fromRectAndRadius(basket, const Radius.circular(5)), Paint()..color = const Color(0xFFB45309));
        for (final ox in [-6.0, 0.0, 6.0]) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(bx + ox, handY - 2), width: 6.5, height: 8.5),
            Paint()..color = const Color(0xFFFEF3C7),
          );
        }
      } else if (box.productType == SimProductType.cheese) {
        // 🧀 Elde Tulum Peyniri Tekerleri
        final board = Rect.fromCenter(center: Offset(bx, handY + 4), width: 28, height: 8);
        canvas.drawRRect(RRect.fromRectAndRadius(board, const Radius.circular(3)), Paint()..color = const Color(0xFF78350F));
        canvas.drawCircle(Offset(bx - 5, handY - 1), 7.5, Paint()..color = const Color(0xFFFACC15));
        canvas.drawCircle(Offset(bx + 5, handY - 1), 7.5, Paint()..color = const Color(0xFFEAB308));
      } else {
        // 🍅🌶️🍎🥖 Elde Taze Meyve / Sebze / Ekmek Hasat Kasası
        final crate = Rect.fromCenter(center: Offset(bx, handY + 3), width: 28, height: 13);
        canvas.drawRRect(RRect.fromRectAndRadius(crate, const Radius.circular(4)), Paint()..color = const Color(0xFF92400E));
        for (final ox in [-6.5, 0.0, 6.5]) {
          canvas.drawCircle(Offset(bx + ox, handY - 3), 5.2, Paint()..color = def.primaryColor);
        }
      }

      // Baş Üstü Sayı Rozeti
      final pillRect = Rect.fromCenter(center: Offset(bx, by - 4), width: 78, height: 22);
      Color bgColor = const Color(0xFF0284C7);
      if (box.productType == SimProductType.egg || box.productType == SimProductType.cheese) {
        bgColor = const Color(0xFFD97706);
      } else if (box.productType != SimProductType.milk) {
        bgColor = const Color(0xFF15803D);
      }

      canvas.drawRRect(RRect.fromRectAndRadius(pillRect.translate(0, 2), const Radius.circular(11)), Paint()..color = Colors.black45);
      canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(11)), Paint()..color = bgColor);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(11)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _drawText(
        canvas,
        '${def.emoji} ${box.currentCount}/${box.maxCount}',
        bx,
        by - 4,
        fontSize: 11.0,
        isBold: true,
        color: Colors.white,
      );
      return;
    }

    final carriedRect = Rect.fromCenter(center: Offset(bx, by), width: 52, height: 25);
    _draw3DBox(
      canvas,
      baseRect: carriedRect,
      height3D: 11,
      topColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
      frontColors: const [Color(0xFFB45309), Color(0xFF78350F)],
      radius: 5,
      castShadow: false,
    );
    _drawText(canvas, '${def.emoji} x${box.currentCount}', bx, by - 6, fontSize: 11.0, isBold: true, color: Colors.white);
  }

  void _draw3DHumanCharacter({
    required Canvas canvas,
    required double x,
    required double y,
    required String name,
    required Color shirtColor,
    required Color pantsColor,
    required Color hairColor,
    required double walkOffset,
    bool isPlayer = false,
    bool hasBasket = false,
  }) {
    final double bob = walkOffset.abs() * 1.6;

    // 3D Yumuşak Çift Katmanlı Yer Gölgesi (Ortam + Ayak Altı AO, blur filtresiz)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 3.5, y + 19.5), width: 42, height: 18),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x + 1, y + 18), width: 26, height: 10),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    // 3D Silindirik Bacaklar & Beyaz Tabanlı Spor Ayakkabılar
    final leftLegY = y + 9 + (walkOffset * 5.0);
    final rightLegY = y + 9 - (walkOffset * 5.0);

    for (final legData in [
      [-6.5, leftLegY],
      [6.5, rightLegY]
    ]) {
      final lx = x + legData[0];
      final ly = legData[1];
      final legRect = Rect.fromCenter(center: Offset(lx, ly), width: 9.0, height: 17.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(legRect, const Radius.circular(4.5)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(pantsColor, Colors.white, 0.16)!,
              pantsColor,
              Color.lerp(pantsColor, Colors.black, 0.45)!,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(legRect),
      );
      // 3D Ayakkabı Tabanı + Üst Yüzeyi
      final soleRect = Rect.fromCenter(center: Offset(lx, ly + 9.2), width: 11.0, height: 5.5);
      canvas.drawOval(soleRect, Paint()..color = const Color(0xFFE2E8F0));
      final shoeRect = Rect.fromCenter(center: Offset(lx, ly + 8.0), width: 10.4, height: 5.8);
      canvas.drawOval(
        shoeRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF334155), Color(0xFF090D16)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(shoeRect),
      );
    }

    // 3D Gövde (Hacimli Omuz, Kemer, Yaka & Önlük)
    final bodyRect = Rect.fromCenter(center: Offset(x, y - 3 - bob), width: 28, height: 26);
    // Gövde sağ 3D yan derinlik katmanı
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect.translate(2.2, 1.5), const Radius.circular(9)),
      Paint()..color = Color.lerp(shirtColor, Colors.black, 0.52)!,
    );
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(shirtColor, Colors.white, 0.22)!,
          shirtColor,
          Color.lerp(shirtColor, Colors.black, 0.38)!,
        ],
        stops: const [0.0, 0.45, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bodyRect);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(9)), bodyPaint);

    // Omuz Üst 3D Parlama Hattı
    canvas.drawLine(
      Offset(bodyRect.left + 6, bodyRect.top + 1.5),
      Offset(bodyRect.right - 6, bodyRect.top + 1.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // 3D Yaka Detayı
    final collarPath = Path()
      ..moveTo(x - 5.5, bodyRect.top + 1)
      ..lineTo(x, bodyRect.top + 6.5)
      ..lineTo(x + 5.5, bodyRect.top + 1)
      ..close();
    canvas.drawPath(collarPath, Paint()..color = Colors.white.withValues(alpha: 0.85));

    if (isPlayer) {
      // Yönetici 3D Mavi Market Önlüğü, Askıları ve Yaka Kartı
      final apronRect = Rect.fromCenter(center: Offset(x, y - 0.5 - bob), width: 16.5, height: 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(apronRect.translate(1, 1.5), const Radius.circular(4)),
        Paint()..color = const Color(0xFF075985),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(apronRect, const Radius.circular(4)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF38BDF8), Color(0xFF0284C7), Color(0xFF0369A1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(apronRect),
      );
      // Altın Yönetici Rozeti
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + 4, y - 5 - bob), width: 5.5, height: 3.5), const Radius.circular(1)),
        Paint()..color = const Color(0xFFFACC15),
      );
    }

    // Sallanan 3D Silindirik Kollar ve Küresel Eller
    final leftArmY = y - 1 - bob - (walkOffset * 3.8);
    final rightArmY = y - 1 - bob + (walkOffset * 3.8);
    for (final armData in [
      [-15.2, leftArmY],
      [15.2, rightArmY]
    ]) {
      final ax = x + armData[0];
      final ay = armData[1];
      final armRect = Rect.fromCenter(center: Offset(ax, ay), width: 7.5, height: 15.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(armRect, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(shirtColor, Colors.white, 0.18)!,
              shirtColor,
              Color.lerp(shirtColor, Colors.black, 0.35)!,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(armRect),
      );
      final handCenter = Offset(ax, ay + 8.2);
      canvas.drawCircle(
        handCenter,
        4.2,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFF1F2), Color(0xFFFBCFE8), Color(0xFFF472B6)],
            center: Alignment(-0.3, -0.3),
          ).createShader(Rect.fromCircle(center: handCenter, radius: 4.2)),
      );
    }

    if (hasBasket) {
      final bRect = Rect.fromCenter(center: Offset(x + 20, rightArmY + 9), width: 18, height: 13.5);
      _draw3DBox(
        canvas,
        baseRect: bRect,
        height3D: 6,
        topColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
        frontColors: const [Color(0xFFC2410C), Color(0xFF7C2D12)],
        radius: 3,
        castShadow: false,
      );
      canvas.drawCircle(Offset(bRect.center.dx - 3, bRect.top - 4), 3.2, Paint()..color = const Color(0xFFFEF08A));
      canvas.drawCircle(Offset(bRect.center.dx + 3, bRect.top - 4), 3.2, Paint()..color = const Color(0xFF38BDF8));
    }

    // 3D Boyun Silindiri
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y - 12 - bob), width: 8, height: 6), const Radius.circular(3)),
      Paint()..color = const Color(0xFFF9A8D4),
    );

    // 3D Küresel Kafa, Kulaklar, Yüz Gölgelendirmesi ve Hacimli Saç
    final headCenter = Offset(x, y - 21.5 - bob);
    canvas.drawCircle(headCenter.translate(1.8, 3.2), 12.8, Paint()..color = Colors.black26);
    // Kulaklar
    canvas.drawCircle(Offset(headCenter.dx - 12.2, headCenter.dy + 1), 2.8, Paint()..color = const Color(0xFFF9A8D4));
    canvas.drawCircle(Offset(headCenter.dx + 12.2, headCenter.dy + 1), 2.8, Paint()..color = const Color(0xFFF9A8D4));

    canvas.drawCircle(
      headCenter,
      12.8,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF1F2), Color(0xFFFBCFE8), Color(0xFFF472B6)],
          stops: [0.0, 0.68, 1.0],
          center: Alignment(-0.32, -0.38),
        ).createShader(Rect.fromCircle(center: headCenter, radius: 12.8)),
    );

    // 3D Hacimli Saç Kubbesi + Üst Parlama
    final hairRect = Rect.fromCircle(center: headCenter, radius: 13.6);
    final hairPath = Path()
      ..addArc(hairRect, pi * 0.92, pi * 1.16)
      ..close();
    canvas.drawPath(
      hairPath,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(hairColor, Colors.white, 0.25)!,
            hairColor,
            Color.lerp(hairColor, Colors.black, 0.45)!,
          ],
          center: const Alignment(-0.3, -0.5),
        ).createShader(hairRect),
    );

    // Gözler, Göz Bebeği Parlaması, Yanaklar ve Tebessüm
    for (final ex in [-4.2, 4.2]) {
      canvas.drawCircle(Offset(headCenter.dx + ex, headCenter.dy + 1), 1.9, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(Offset(headCenter.dx + ex - 0.6, headCenter.dy + 0.4), 0.7, Paint()..color = Colors.white);
    }
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx - 6.5, headCenter.dy + 3.5), width: 3.6, height: 2.0),
      Paint()..color = const Color(0xFFF43F5E).withValues(alpha: 0.28),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx + 6.5, headCenter.dy + 3.5), width: 3.6, height: 2.0),
      Paint()..color = const Color(0xFFF43F5E).withValues(alpha: 0.28),
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(headCenter.dx, headCenter.dy + 4.2), width: 5.5, height: 3.2),
      0.1,
      pi - 0.2,
      false,
      Paint()
        ..color = const Color(0xFF881337)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Doğal Yarı Saydam Karakter İsim Etiketi
    final nameBg = Rect.fromCenter(center: Offset(x, y + 30), width: isPlayer ? 64 : 58, height: 14.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(nameBg, const Radius.circular(7)),
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );
    _drawText(canvas, isPlayer ? '⭐ Manager' : name, x, y + 30, fontSize: 8.8, color: Colors.white.withValues(alpha: 0.95), isBold: true);
  }

  // =========================================================================
  // 7. ATMOSFERİK IŞIKLANDIRMA & TAVAN 3D LED SPOT PANELLERİ (Picture Cache)
  // =========================================================================
  void _drawAtmosphericLighting(Canvas canvas) {
    if (_cachedLightingPicture == null) {
      final recorder = ui.PictureRecorder();
      final rec = Canvas(recorder);

      // Market Tavan Spot Işık Hüzmeleri + 3D Asma Tavan LED Armatür Yansımaları
      for (final lx in [420.0, 780.0, 1140.0, 1520.0]) {
        for (final ly in [390.0, 650.0, 880.0]) {
          final lightRect = Rect.fromCircle(center: Offset(lx, ly), radius: 145);
          rec.drawCircle(
            Offset(lx, ly),
            145,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  const Color(0xFFFFFBEB).withValues(alpha: 0.16),
                  const Color(0xFFFEF08A).withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ).createShader(lightRect),
          );
          final panelReflect = Rect.fromCenter(center: Offset(lx, ly), width: 64, height: 14);
          rec.drawRRect(
            RRect.fromRectAndRadius(panelReflect, const Radius.circular(7)),
            Paint()..color = Colors.white.withValues(alpha: 0.08),
          );
        }
      }

      // Ön Cam Vitrinden İçeri Süzülen 3D Güneş Işığı Hüzmeleri (Sunbeams)
      final doorCenter = engine.worldWidth / 2;
      for (final sx in [280.0, 560.0, doorCenter, 1440.0, 1720.0]) {
        final sunPath = Path()
          ..moveTo(sx - 45, 232)
          ..lineTo(sx + 45, 232)
          ..lineTo(sx + 85, 360)
          ..lineTo(sx - 5, 360)
          ..close();
        rec.drawPath(
          sunPath,
          Paint()
            ..shader = LinearGradient(
              colors: [
                const Color(0xFFFEF9C3).withValues(alpha: 0.16),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(Rect.fromLTWH(sx - 45, 232, 130, 130)),
        );
      }

      _cachedLightingPicture = recorder.endRecording();
    }
    canvas.drawPicture(_cachedLightingPicture!);
  }

  void _drawMouseTarget(Canvas canvas) {
    if (engine.targetMoveX == null || engine.targetMoveY == null) return;
    final tx = engine.targetMoveX!;
    final ty = engine.targetMoveY!;

    final pulse = 12.0 + sin(engine.worldTime * 8.0) * 3.0;
    canvas.drawCircle(
      Offset(tx, ty),
      pulse,
      Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
    canvas.drawCircle(Offset(tx, ty), 4.0, Paint()..color = Colors.white);
  }

  void _drawParticles(Canvas canvas) {
    for (var p in engine.particles) {
      final rawAlpha = (p.life / p.maxLife).clamp(0.0, 1.0);
      final alpha = (rawAlpha * 8).round() / 8.0;
      if (alpha <= 0) continue;
      _drawText(
        canvas,
        p.text,
        p.x,
        p.y,
        fontSize: p.size,
        color: p.color.withValues(alpha: alpha),
        isBold: true,
      );
    }
  }

  TextPainter _getCachedTextPainter(String text, double fontSize, Color color, bool isBold) {
    final key = '$text|$fontSize|${color.toARGB32()}|$isBold';
    var textPainter = _textCache[key];
    if (textPainter == null) {
      if (_textCache.length > 1200) {
        _textCache.clear();
      }
      textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      _textCache[key] = textPainter;
    }
    return textPainter;
  }

  void _drawThoughtBubble(Canvas canvas, String text, double x, double y) {
    final textPainter = _getCachedTextPainter(text, 11.5, const Color(0xFF0F172A), true);

    final bubbleWidth = max(58.0, textPainter.width + 20.0);
    const bubbleHeight = 26.0;
    final bubbleRect = Rect.fromCenter(center: Offset(x, y), width: bubbleWidth, height: bubbleHeight);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect.translate(2, 4), const Radius.circular(12)),
      Paint()..color = Colors.black26,
    );

    canvas.drawRRect(RRect.fromRectAndRadius(bubbleRect, const Radius.circular(12)), Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(12)),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    textPainter.paint(canvas, Offset(x - (textPainter.width / 2), y - (textPainter.height / 2)));
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, Color color = Colors.black87, bool isBold = false}) {
    final textPainter = _getCachedTextPainter(text, fontSize, color, isBold);
    textPainter.paint(canvas, Offset(x - (textPainter.width / 2), y - (textPainter.height / 2)));
  }

  @override
  bool shouldRepaint(covariant SimulationPainter oldDelegate) => true;
}
