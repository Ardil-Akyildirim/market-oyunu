import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../widgets/pixel_ui.dart';
import '../widgets/tutorial_overlay.dart';
import '../audio/audio_service.dart';
import 'simulation_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _play({bool replayTutorial = false}) async {
    AudioService.instance.sfx('click');
    if (replayTutorial) {
      await TutorialPrefs.resetAll();
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SimulationScreen(forceTutorial: replayTutorial),
      ),
    );
  }

  void _showHowToPlay() {
    showDialog(
      context: context,
      builder: (ctx) => PixelDialog(
        backgroundColor: const Color(0xFF2A221C),
        title: const Text('How to Play', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const SingleChildScrollView(
          child: Text(
            '{sun} DAY\n'
            '• Keep the shelves stocked ({computer} Computer -> order -> carry the box to a shelf).\n'
            '• Customers pay at the register: tap the counter to open Cashier View.\n'
            '• Upgrade your store with {case} Manager.\n\n'
            '{moon} NIGHT\n'
            '• Thieves sneak in and steal from your shelves.\n'
            '• Walk up to them and press F (or tap {bat} SWING) to hit them with your stick.\n'
            '• Driven-off thieves drop their loot and pay you a bounty.\n\n'
            'CONTROLS\n'
            '• WASD / arrows or tap to move • E / Space to interact • F to swing the stick.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _play(replayTutorial: true);
            },
            child: const Text('Replay tutorial'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _menuButton(String label, VoidCallback onTap, {bool primary = false}) {
    final face = primary ? const Color(0xFFD9A441) : const Color(0xFF4A3C30);
    final edge = primary ? const Color(0xFF8A5A1E) : const Color(0xFF2A221C);
    final textColor = primary ? const Color(0xFF1C1209) : const Color(0xFFEDE6D6);
    return GestureDetector(
      onTap: () {
        AudioService.instance.sfx('click');
        onTap();
      },
      child: Container(
        width: 270,
        height: 54,
        decoration: BoxDecoration(
          color: face,
          border: Border.all(color: const Color(0xFF14100E), width: 4),
          boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 6), blurRadius: 0)],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1230),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(painter: _MenuBackdropPainter(_anim.value)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        Transform.translate(
                          offset: const Offset(4, 4),
                          child: const Text(
                            'VILLAGE\nMARKET',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF14100E),
                              fontSize: 46,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const Text(
                          'VILLAGE\nMARKET',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFF1D48A),
                            fontSize: 46,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Run the shop by day. Defend it by night.',
                      style: TextStyle(color: Color(0xFFB9B09C), fontSize: 13),
                    ),
                    const SizedBox(height: 34),
                    _menuButton('PLAY', () => _play(), primary: true),
                    const SizedBox(height: 12),
                    _menuButton('HOW TO PLAY', _showHowToPlay),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Music',
                          onPressed: () async {
                            await AudioService.instance.setMusicOn(!AudioService.instance.musicOn);
                            if (mounted) setState(() {});
                          },
                          icon: PixelIcon('note', size: 24, slash: !AudioService.instance.musicOn),
                        ),
                        IconButton(
                          tooltip: 'Sound effects',
                          onPressed: () async {
                            await AudioService.instance.setSfxOn(!AudioService.instance.sfxOn);
                            if (mounted) setState(() {});
                          },
                          icon: PixelIcon('speaker', size: 24, slash: !AudioService.instance.sfxOn),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('v0.1 prototype', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuBackdropPainter extends CustomPainter {
  final double t;
  _MenuBackdropPainter(this.t);

  static const double px = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    void r(double x, double y, double w, double h, Color c) {
      p.color = c;
      canvas.drawRect(Rect.fromLTWH((x / px).floor() * px, (y / px).floor() * px, (w / px).ceil() * px, (h / px).ceil() * px), p);
    }

    // banded night sky (pixel gradient)
    const bands = [Color(0xFF0A1214), Color(0xFF0D191B), Color(0xFF11201F), Color(0xFF16282A), Color(0xFF1B3030), Color(0xFF223A36)];
    final bandH = size.height * 0.8 / bands.length;
    for (int i = 0; i < bands.length; i++) {
      r(0, i * bandH, size.width, bandH + px, bands[i]);
    }

    // twinkling stars
    final rnd = Random(11);
    for (int i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height * 0.55;
      final on = (sin(t * 2 * pi * 2 + i * 1.7) > -0.2);
      if (on) r(x, y, px, px, i % 5 == 0 ? const Color(0xFFFFE9A8) : const Color(0xFF9FB2B0));
    }

    // pixel moon
    final mx = size.width * 0.8, my = size.height * 0.2;
    for (int dy = -5; dy <= 5; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        if (dx * dx + dy * dy <= 27) {
          final shade = (dx + 2) * (dx + 2) + (dy - 1) * (dy - 1) <= 20;
          r(mx + dx * px, my + dy * px, px, px, shade ? const Color(0xFFF4E7B8) : const Color(0xFFD9C98F));
        }
      }
    }

    // village silhouettes with lit windows
    final groundTop = size.height * 0.80;
    final hr = Random(5);
    double x = -px * 2;
    while (x < size.width) {
      final w = (7 + hr.nextInt(8)) * px;
      final h = (6 + hr.nextInt(9)) * px;
      r(x, groundTop - h, w, h, const Color(0xFF121A1B));
      r(x, groundTop - h, w, px, const Color(0xFF1E2A2B));
      // roof
      r(x - px, groundTop - h - px, w + px * 2, px, const Color(0xFF0B1011));
      for (double wy = groundTop - h + px * 2; wy < groundTop - px * 2; wy += px * 3) {
        for (double wx = x + px; wx < x + w - px * 2; wx += px * 3) {
          if (hr.nextDouble() < 0.45) r(wx, wy, px, px * 1.5, const Color(0xFFE2B04A));
        }
      }
      x += w + px * 2;
    }

    // ground: cobblestones
    r(0, groundTop, size.width, size.height - groundTop, const Color(0xFF2B2824));
    final gr = Random(9);
    for (double gy = groundTop; gy < size.height; gy += px * 2) {
      for (double gx = ((gy / px).floor() % 4 == 0) ? 0 : px * 2; gx < size.width; gx += px * 4) {
        r(gx, gy, px * 3, px, gr.nextBool() ? const Color(0xFF3A3630) : const Color(0xFF34302B));
      }
    }
    r(0, groundTop, size.width, px, const Color(0xFF4A4439));
  }

  @override
  bool shouldRepaint(covariant _MenuBackdropPainter oldDelegate) => oldDelegate.t != t;
}
