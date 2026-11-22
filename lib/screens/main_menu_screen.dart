import 'dart:math';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Text;
import '../widgets/pixel_ui.dart';
import '../widgets/tutorial_overlay.dart';
import '../audio/audio_service.dart';
import '../settings/settings_service.dart';
import '../widgets/settings_dialog.dart';
import '../save/save_service.dart';
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
    SettingsService.instance.load();
    _refreshSave();
    AudioService.instance.playMusic('menu');
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _save;

  Future<void> _refreshSave() async {
    final s = await SaveService.load();
    if (mounted) setState(() => _save = s);
  }

  void _play({bool replayTutorial = false, Map<String, dynamic>? saveData}) async {
    AudioService.instance.sfx('click');
    if (replayTutorial) {
      await TutorialPrefs.resetAll();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SimulationScreen(forceTutorial: replayTutorial, saveData: saveData),
      ),
    );
    _refreshSave();
    AudioService.instance.playMusic('menu');
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => PixelDialog(
        title: const Text('Quit the game?'),
        content: const Text('Your progress is saved automatically at the start of every day.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text('Quit'),
          ),
        ],
      ),
    );
  }

  void _newGame() {
    if (_save == null) {
      _play();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => PixelDialog(
        title: const Text('Start a new game?'),
        content: Text('Your saved game (Day ${_save!['day']}) will be replaced as soon as the new game reaches its first dawn.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _play();
            },
            child: const Text('New game'),
          ),
        ],
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
            '• Customers walk in, pick items and queue at a register. Stand at the register (or use Cashier View) and scan their items, then take the payment.\n'
            '• {computer} Computer: order wholesale boxes. The truck drops them at the back door.\n'
            '• Boxes on the floor: press ACT next to one to pick it up, walk to a matching shelf and keep pressing ACT to stack the items. DROP puts what you hold on the floor.\n'
            '• Shelves: with empty hands, ACT takes one item from a shelf you are standing at.\n'
            '• {bike} Courier: when a courier order appears, bring the items to the packing desk, tape the package and hand it to the courier before time runs out.\n'
            '• {case} Manager: upgrade the store, hire a cashier and a stocker. Staff are paid every dawn.\n'
            '• The ACT button turns green when something is within reach.\n\n'
            '{moon} NIGHT\n'
            '• Thieves sneak in from the front or the back and steal from your shelves.\n'
            '• Walk up to them and use SWING (or F) to hit them. The stick only works at night.\n'
            '• Driven-off thieves drop their loot and pay you a bounty.\n\n'
            'CONTROLS\n'
            '• Phone: D-pad (left) to move, ACT (right) to interact, DROP to put things down, SWING at night.\n'
            '• Keyboard: WASD / arrows, E / Space to interact, F to swing the stick.\n'
            '• Settings: D-pad style, button size, left-handed mode, volume.',
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
    return PixelPress(
      onTap: onTap,
      child: Container(
        width: 250,
        height: 48,
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
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth > box.maxHeight * 1.25;
                final titleBlock = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        Transform.translate(
                          offset: const Offset(4, 4),
                          child: Text(
                            'VILLAGE\nMARKET',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF14100E),
                              fontSize: wide ? 44 : 46,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        Text(
                          'VILLAGE\nMARKET',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFFF1D48A),
                            fontSize: wide ? 44 : 46,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Run the shop by day.\nDefend it by night.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFB9B09C), fontSize: 14),
                    ),
                  ],
                );
                final buttons = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_save != null) ...[
                      _menuButton('CONTINUE (DAY ${_save!['day']})', () => _play(saveData: _save), primary: true),
                      const SizedBox(height: 10),
                      _menuButton('NEW GAME', _newGame),
                    ] else
                      _menuButton('PLAY', () => _play(), primary: true),
                    const SizedBox(height: 10),
                    _menuButton('HOW TO PLAY', _showHowToPlay),
                    const SizedBox(height: 10),
                    _menuButton('SETTINGS', () => showDialog(context: context, builder: (_) => const SettingsDialog())),
                    const SizedBox(height: 10),
                    _menuButton('EXIT', _confirmExit),
                  ],
                );
                return Center(
                  child: SingleChildScrollView(
                    child: wide
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [titleBlock, const SizedBox(width: 64), buttons],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [titleBlock, const SizedBox(height: 26), buttons],
                          ),
                  ),
                );
              },
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
