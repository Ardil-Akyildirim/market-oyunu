import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../simulation/simulation_engine.dart';

/// One page of a tutorial. If [isTask] is true the game keeps running and the
/// step completes by itself once [isDone] returns true; otherwise it is an
/// info card the player dismisses with "Next".
class TutorialStep {
  final String icon;
  final String title;
  final String body;
  final bool Function(SimulationEngine engine)? isDone;

  const TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
    this.isDone,
  });

  bool get isTask => isDone != null;
}

class TutorialPrefs {
  static const dayKey = 'tutorial_day_done';
  static const nightKey = 'tutorial_night_done';

  static Future<bool> isDone(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setDone(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  static Future<void> resetAll() async {
    await setDone(dayKey, false);
    await setDone(nightKey, false);
  }
}

/// Step lists ---------------------------------------------------------------

List<TutorialStep> buildDayTutorial(double startX, double startY) {
  return [
    const TutorialStep(
      icon: '🏪',
      title: 'Welcome to Village Market!',
      body: 'You run a little village market. By day you serve customers and keep the shelves '
          'full. By night, thieves sneak in to steal your stock. This quick tour covers the basics.',
    ),
    TutorialStep(
      icon: '🚶',
      title: 'Try walking around',
      body: 'Move with WASD / arrow keys, or tap / click anywhere on the floor and your '
          'character will walk there.',
      isDone: (e) {
        final dx = e.playerX - startX;
        final dy = e.playerY - startY;
        return (dx * dx + dy * dy) > 150 * 150;
      },
    ),
    const TutorialStep(
      icon: '📦',
      title: 'Keep the shelves stocked',
      body: 'Customers buy products from the shelves. When one runs low, open the 💻 Computer '
          'to order stock. When the delivery arrives, pick up the box and tap a shelf to fill it.',
    ),
    const TutorialStep(
      icon: '🛒',
      title: 'Customers and the register',
      body: 'Shoppers line up at a register when they are done. Tap the counter (or walk behind it) '
          'to switch to Cashier View, scan their items and collect the payment.',
    ),
    const TutorialStep(
      icon: '👔',
      title: 'Grow your store',
      body: 'Use the 👔 Manager button to upgrade your store, unlock new products and hire help. '
          'Reinvest your profit wisely!',
    ),
    const TutorialStep(
      icon: '🌙',
      title: 'Watch the clock',
      body: 'The clock in the top bar counts down to nightfall. When the sun sets the shop closes '
          'and thieves arrive. Have your shelves stocked and your stick ready!',
    ),
  ];
}

List<TutorialStep> buildNightTutorial() {
  return [
    const TutorialStep(
      icon: '🌙',
      title: 'Night has fallen!',
      body: 'The shop is closed to customers. Masked thieves are sneaking in to grab products '
          'off your shelves. Do not let them get away with it!',
    ),
    const TutorialStep(
      icon: '🏏',
      title: 'Fight back with your stick',
      body: 'Walk up to a thief and press F, or tap the 🏏 SWING button, to hit everyone close to you. '
          'Tapping directly on a thief also runs you to him and attacks.',
    ),
    TutorialStep(
      icon: '💥',
      title: 'Hit a thief!',
      body: 'Get close to a thief and swing your stick (F / 🏏 button).',
      isDone: (e) => e.totalThiefHits > 0 || !e.isNight,
    ),
    const TutorialStep(
      icon: '🦹',
      title: 'Stolen goods',
      body: 'Every hit knocks a thief back. Enough hits drive him off: he drops his loot back on the '
          'shelf and you earn a bounty. Thieves who escape through the door keep what they stole.',
    ),
    const TutorialStep(
      icon: '☀️',
      title: 'Survive until sunrise',
      body: 'Hold out until dawn. Each night brings more (and tougher) thieves, so keep your shelves '
          'stocked and your cash growing.',
    ),
  ];
}

/// Overlay widget ------------------------------------------------------------

class TutorialOverlay extends StatelessWidget {
  final TutorialStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const TutorialOverlay({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;

    if (step.isTask) {
      // Small banner on top: the game keeps running
      return Positioned(
        top: 64,
        left: 0,
        right: 0,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xEE2A221C),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.amberAccent, width: 1.6),
              ),
              child: Row(
                children: [
                  Text(step.icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TASK: ${step.title}',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          step.body,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Full info card (game is paused behind a dim layer)
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A221C),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.amberAccent, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(step.icon, style: const TextStyle(fontSize: 34)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    step.body,
                    style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '${index + 1} / $total',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onSkip,
                        child: const Text('Skip tutorial', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onNext,
                        child: Text(isLast ? 'Got it!' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
