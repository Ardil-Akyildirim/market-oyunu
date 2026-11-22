import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../widgets/pixel_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../save/save_service.dart';
import '../settings/settings_service.dart';
import '../widgets/settings_dialog.dart';
import '../simulation/simulation_engine.dart';
import '../simulation/simulation_models.dart';
import '../simulation/pixel_painter.dart';
import '../simulation/dialogs/order_dialog.dart';
import '../simulation/dialogs/checkout_dialog.dart';
import '../simulation/dialogs/manage_dialog.dart';
import '../simulation/dialogs/courier_packing_dialog.dart';
import '../widgets/tutorial_overlay.dart';
import '../audio/audio_service.dart';

class SimulationScreen extends StatefulWidget {
  final bool forceTutorial;
  final Map<String, dynamic>? saveData;
  const SimulationScreen({super.key, this.forceTutorial = false, this.saveData});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> with SingleTickerProviderStateMixin {
  late final SimulationEngine _engine;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _smoothDt = 0;

  bool _keyUp = false;
  bool _keyDown = false;
  bool _keyLeft = false;
  bool _keyRight = false;
  bool _isPackingDialogOpen = false;

  // 1. Şahıs Kasiyer Kamera Modu (Tam ekran kamera açısı geçişi)
  bool _isCashierViewOpen = false;
  bool _cashierAutoExitLock = false;
  SimCustomer? _activeCashierCustomer;
  int _activeCashierCounterIndex = 0;
  String? _lastInteractionText;
  double _lastHudZoom = 1.0;
  double _hudAccum = 0.0;
  final ValueNotifier<int> _hudRevision = ValueNotifier<int>(0);

  final FocusNode _focusNode = FocusNode();

  // Tutorials (day basics + first night)
  List<TutorialStep>? _tutorialSteps;
  int _tutorialIndex = 0;
  String? _tutorialPrefKey;
  bool _nightTutorialDone = false;
  bool _dayTutorialDone = false;
  bool _isDawnDialogOpen = false;
  bool _musicIsNight = false;

  @override
  void initState() {
    super.initState();
    _engine = SimulationEngine();
    if (widget.saveData != null) _engine.loadSave(widget.saveData!);
    _engine.onAutosave = () => SaveService.save(_engine.toSave());
    SettingsService.instance.load();
    SettingsService.instance.addListener(_onSettingsChanged);

    // Global donanım klavyesi dinleyicisi
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    _engine.onSfx = AudioService.instance.sfx;
    AudioService.instance.playMusic('day');
    _loadTutorialState();

    _ticker = createTicker((elapsed) {
      if (_lastElapsed == Duration.zero) {
        _lastElapsed = elapsed;
        return;
      }
      final rawDt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;
      if (rawDt <= 0) return;
      // A long frame (GC, dialog opening) must not freeze or teleport the game:
      // cap it, and smooth frame-to-frame timing noise so movement stays even.
      final capped = rawDt > 0.1 ? 0.1 : rawDt;
      _smoothDt = _smoothDt == 0 ? capped : _smoothDt + (capped - _smoothDt) * 0.4;
      final dt = _smoothDt;

      // Kasiyer kamerasında müşteriyle ilgilenirken arka plan simülasyonunu beklet;
      // müşteri bekleniyorsa simülasyonu çalıştır ve gelen müşteriyi otomatik kasaya al
      if (_isCashierViewOpen && _activeCashierCustomer != null) return;

      if (!_isCashierViewOpen) {
        _updateMovementFromHardware();
      }
      _engine.update(dt);

      // Kasa arkasındaki alana yürüyünce otomatik olarak 1. Şahıs Kasiyer Bakışına geç
      if (!_isCashierViewOpen && !_isPackingDialogOpen && !_engine.isNight) {
        final cashierZoneIdx = _engine.getCheckoutTriggerZoneIndex();
        if (cashierZoneIdx != null) {
          if (!_cashierAutoExitLock) {
            _enterCashierView(null, cashierZoneIdx);
          }
        } else {
          _cashierAutoExitLock = false;
        }
      }

      if (_isCashierViewOpen && _activeCashierCustomer == null) {
        final waitingAtCounter = _engine.customers.where((c) =>
            c.state == CustomerState.waitingAtCheckout &&
            c.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1) == _activeCashierCounterIndex);
        final fallbackWaiting = _engine.customers.where((c) => c.state == CustomerState.waitingAtCheckout);
        final next = waitingAtCounter.isNotEmpty
            ? waitingAtCounter.first
            : (fallbackWaiting.isNotEmpty ? fallbackWaiting.first : null);
        if (next != null && mounted) {
          setState(() {
            _activeCashierCustomer = next;
            _activeCashierCounterIndex = next.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1);
          });
        }
      }

      // HUD widget ağacını saniyede 60 kez yerine sadece gerektiğinde / ~8 Hz güncelle
      _hudAccum += dt;
      if (_hudAccum >= 0.12 ||
          _engine.activeInteractionText != _lastInteractionText ||
          _engine.cameraZoom != _lastHudZoom) {
        _hudAccum = 0.0;
        _lastInteractionText = _engine.activeInteractionText;
        _lastHudZoom = _engine.cameraZoom;
        _hudRevision.value++;
      }

      _updateTutorials();

      if (_engine.isNight != _musicIsNight) {
        _musicIsNight = _engine.isNight;
        AudioService.instance.playMusic(_musicIsNight ? 'night' : 'day');
      }

      if (_engine.dawnReportPending && !_isDawnDialogOpen && mounted) {
        _engine.dawnReportPending = false;
        _showDawnReport();
      }

      if (_engine.shouldOpenCourierPackingDialog && !_isPackingDialogOpen && mounted) {
        _engine.shouldOpenCourierPackingDialog = false;
        _openCourierPackingDialog();
      }
    });

    _ticker.start();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _tap(VoidCallback fn) {
    if (SettingsService.instance.haptics) HapticFeedback.lightImpact();
    fn();
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _ticker.dispose();
    _engine.onSfx = null;
    _focusNode.dispose();
    _hudRevision.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _updateMovementFromHardware() {
    double dx = 0;
    double dy = 0;

    final hw = HardwareKeyboard.instance;
    final up = _keyUp ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.keyW) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.keyW) ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.arrowUp) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.arrowUp);

    final down = _keyDown ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.keyS) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.keyS) ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.arrowDown) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.arrowDown);

    final left = _keyLeft ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.keyA) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.keyA) ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.arrowLeft);

    final right = _keyRight ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.keyD) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.keyD) ||
        hw.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight) ||
        hw.isPhysicalKeyPressed(PhysicalKeyboardKey.arrowRight);

    if (left) dx -= 1;
    if (right) dx += 1;
    if (up) dy -= 1;
    if (down) dy += 1;

    if (dx != 0 || dy != 0) {
      final len = sqrt(dx * dx + dy * dy);
      dx /= len;
      dy /= len;
    }

    _engine.setMovement(dx, dy);
  }

  bool _isUpKey(KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    return event.logicalKey == LogicalKeyboardKey.keyW ||
        event.physicalKey == PhysicalKeyboardKey.keyW ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.physicalKey == PhysicalKeyboardKey.arrowUp ||
        label == 'w';
  }

  bool _isDownKey(KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    return event.logicalKey == LogicalKeyboardKey.keyS ||
        event.physicalKey == PhysicalKeyboardKey.keyS ||
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.physicalKey == PhysicalKeyboardKey.arrowDown ||
        label == 's';
  }

  bool _isLeftKey(KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    return event.logicalKey == LogicalKeyboardKey.keyA ||
        event.physicalKey == PhysicalKeyboardKey.keyA ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.physicalKey == PhysicalKeyboardKey.arrowLeft ||
        label == 'a';
  }

  bool _isRightKey(KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    return event.logicalKey == LogicalKeyboardKey.keyD ||
        event.physicalKey == PhysicalKeyboardKey.keyD ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.physicalKey == PhysicalKeyboardKey.arrowRight ||
        label == 'd';
  }

  bool _isActionKey(KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    return event.logicalKey == LogicalKeyboardKey.keyE ||
        event.physicalKey == PhysicalKeyboardKey.keyE ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        label == 'e';
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_isCashierViewOpen) {
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          _exitCashierView();
          return true;
        }
        return false;
      }
      if (_isUpKey(event)) _keyUp = true;
      if (_isDownKey(event)) _keyDown = true;
      if (_isLeftKey(event)) _keyLeft = true;
      if (_isRightKey(event)) _keyRight = true;
      if (_isActionKey(event)) _executeActiveAction();
      if (event.logicalKey == LogicalKeyboardKey.keyF || event.logicalKey == LogicalKeyboardKey.keyJ) {
        _engine.swingStick();
      }
    } else if (event is KeyUpEvent) {
      if (_isUpKey(event)) _keyUp = false;
      if (_isDownKey(event)) _keyDown = false;
      if (_isLeftKey(event)) _keyLeft = false;
      if (_isRightKey(event)) _keyRight = false;
    }
    return false;
  }

  void _handleKeyEvent(KeyEvent event) {
    _handleGlobalKeyEvent(event);
  }

  // ===============================================================
  // TUTORIALS
  // ===============================================================
  Future<void> _loadTutorialState() async {
    _dayTutorialDone = await TutorialPrefs.isDone(TutorialPrefs.dayKey);
    _nightTutorialDone = await TutorialPrefs.isDone(TutorialPrefs.nightKey);
    if (!mounted) return;
    if (widget.forceTutorial || !_dayTutorialDone) {
      _startTutorial(
        buildDayTutorial(_engine.playerX, _engine.playerY),
        TutorialPrefs.dayKey,
      );
    }
  }

  void _startTutorial(List<TutorialStep> steps, String prefKey) {
    setState(() {
      _tutorialSteps = steps;
      _tutorialIndex = 0;
      _tutorialPrefKey = prefKey;
    });
    _engine.tutorialFreeze = !steps.first.isTask;
  }

  void _finishTutorial() {
    final key = _tutorialPrefKey;
    if (key != null) {
      TutorialPrefs.setDone(key, true);
      if (key == TutorialPrefs.dayKey) _dayTutorialDone = true;
      if (key == TutorialPrefs.nightKey) _nightTutorialDone = true;
    }
    _engine.tutorialFreeze = false;
    if (mounted) {
      setState(() {
        _tutorialSteps = null;
        _tutorialPrefKey = null;
      });
      _focusNode.requestFocus();
    }
  }

  void _nextTutorialStep() {
    final steps = _tutorialSteps;
    if (steps == null) return;
    if (_tutorialIndex >= steps.length - 1) {
      _finishTutorial();
      return;
    }
    setState(() => _tutorialIndex++);
    _engine.tutorialFreeze = !steps[_tutorialIndex].isTask;
  }

  void _updateTutorials() {
    final steps = _tutorialSteps;
    if (steps != null) {
      final step = steps[_tutorialIndex];
      if (step.isTask && step.isDone!(_engine)) {
        _nextTutorialStep();
      }
      return;
    }
    // First night ever: show the night tutorial
    if (_engine.isNight && !_nightTutorialDone && _dayTutorialDone && _engine.phaseTimer > 0.8) {
      _startTutorial(buildNightTutorial(), TutorialPrefs.nightKey);
    }
  }

  // ===============================================================
  // DAWN REPORT & PAUSE MENU
  // ===============================================================
  void _showDawnReport() {
    _isDawnDialogOpen = true;
    _engine.tutorialFreeze = true;
    final e = _engine;
    final survivedDay = e.reportDay;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PixelDialog(
        backgroundColor: const Color(0xFF2A221C),
        title: Text(
          '{sun} Dawn of Day ${survivedDay + 1}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You survived night $survivedDay!',
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('{thief} Thieves driven off: ${e.nightThievesRepelled}',
                style: const TextStyle(color: Colors.white70)),
            Text('{coin} Bounty earned: \$${e.nightBounty.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.greenAccent)),
            Text('{box} Items stolen: ${e.nightStolenItems} (worth \$${e.nightStolenValue.toStringAsFixed(0)})',
                style: const TextStyle(color: Colors.redAccent)),
            Text('{undo} Items recovered: ${e.nightRecoveredItems}',
                style: const TextStyle(color: Colors.lightBlueAccent)),
            if (e.lastWageTotal > 0)
              Text('{coin} Wages paid: -\$${e.lastWageTotal.toStringAsFixed(0)} (${e.lastWageLines.join(', ')})',
                  style: const TextStyle(color: Colors.orangeAccent)),
            if (e.dawnUnlocks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('{star} New on sale today: ${e.dawnUnlocks.join(', ')}',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Open the shop'),
          ),
        ],
      ),
    ).then((_) {
      _isDawnDialogOpen = false;
      _engine.tutorialFreeze = _tutorialSteps != null && !_tutorialSteps![_tutorialIndex].isTask;
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _showPauseMenu() {
    _engine.tutorialFreeze = true;
    showDialog(
      context: context,
      builder: (ctx) => PixelDialog(
        backgroundColor: const Color(0xFF2A221C),
        title: const Text('Paused', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Controls: D-pad to move, ACT to interact, DROP puts down what you hold, SWING hits thieves (night only). Keyboard: WASD, E / Space, F.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                'Staff wages: \$${_engine.dailyWages.toStringAsFixed(0)} per day, paid at dawn. The game saves itself at the start of every day.',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showDialog(context: ctx, builder: (_) => const SettingsDialog()),
            child: const Text('Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _startTutorial(
                buildDayTutorial(_engine.playerX, _engine.playerY),
                TutorialPrefs.dayKey,
              );
            },
            child: const Text('Replay tutorial'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _engine.tutorialFreeze = false;
              Navigator.of(context).pop();
            },
            child: const Text('Main menu'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Resume'),
          ),
        ],
      ),
    ).then((_) {
      if (_tutorialSteps == null) _engine.tutorialFreeze = false;
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _openCourierPackingDialog() {
    if (_isPackingDialogOpen) return;
    _isPackingDialogOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => CourierPackingDialog(engine: _engine),
    ).then((_) {
      _isPackingDialogOpen = false;
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _enterCashierView(SimCustomer? customer, int checkoutIndex) {
    final safeIdx = checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1);
    SimCustomer? target = customer;
    if (target == null) {
      final atCounter = _engine.customers.where((c) =>
          c.state == CustomerState.waitingAtCheckout &&
          c.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1) == safeIdx);
      final anyWaiting = _engine.customers.where((c) => c.state == CustomerState.waitingAtCheckout);
      if (atCounter.isNotEmpty) {
        target = atCounter.first;
      } else if (anyWaiting.isNotEmpty) {
        target = anyWaiting.first;
      }
    }
    setState(() {
      _keyUp = false;
      _keyDown = false;
      _keyLeft = false;
      _keyRight = false;
      _engine.setMovement(0, 0);
      _isCashierViewOpen = true;
      _activeCashierCounterIndex = safeIdx;
      _activeCashierCustomer = target;
    });
    _hudRevision.value++;
  }

  void _exitCashierView() {
    if (!_isCashierViewOpen) return;
    _cashierAutoExitLock = true;
    setState(() {
      _isCashierViewOpen = false;
      _activeCashierCustomer = null;
    });
    _hudRevision.value++;
    if (mounted) _focusNode.requestFocus();
  }

  void _onCashierPaymentCollected(double earned) {
    final counterIdx = _activeCashierCounterIndex;
    if (mounted) {
      showTopToast(context, '{bag} +\$${earned.toStringAsFixed(0)} collected!');
    }

    // Aynı kasada sırada bekleyen başka müşteri varsa doğrudan ona geç; yoksa kasada beklemeye devam et
    final nextWaiting = _engine.customers
        .where((c) =>
            c.state == CustomerState.waitingAtCheckout &&
            c.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1) == counterIdx)
        .toList();
    setState(() {
      _activeCashierCustomer = nextWaiting.isNotEmpty ? nextWaiting.first : null;
    });
    _hudRevision.value++;
  }

  void _executeActiveAction() {
    if (_engine.activeInteractionText != null) {
      if (_engine.activeInteractionText!.contains('Computer')) {
        showDialog(
          context: context,
          builder: (ctx) => OrderComputerDialog(engine: _engine),
        );
      } else if (_engine.activeInteractionText!.contains('Open Register')) {
        final waiting = _engine.customers.where((c) => c.state == CustomerState.waitingAtCheckout).toList();
        if (waiting.isNotEmpty) {
          final cust = waiting.first;
          _enterCashierView(cust, cust.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1));
        }
      } else {
        _engine.activeInteractionAction?.call();
      }
    }
  }

  // Mouse Ekran Koordinatını Kamera Takipli Oyun Dünyasına Çevirme
  Offset? _screenToWorld(Offset screenPos, Size screenSize) {
    final scale = _engine.getEffectiveScale(screenSize);
    final camTopLeft = _engine.getCameraTopLeft(screenSize);

    final wx = camTopLeft.dx + (screenPos.dx / scale);
    final wy = camTopLeft.dy + (screenPos.dy / scale);

    if (wx >= 0 && wx <= _engine.worldWidth && wy >= 0 && wy <= _engine.worldHeight) {
      return Offset(wx, wy);
    }
    return null;
  }

  bool _useTouch(BuildContext context) {
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    return mobile || MediaQuery.of(context).size.width < 1000;
  }

  void _onBackPressed() {
    if (_isCashierViewOpen) {
      _exitCashierView();
    } else {
      _showPauseMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    final touch = _useTouch(context);
    final st = SettingsService.instance;
    final lefty = st.leftHanded;
    final cs = st.controlScale;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF17120F),
        body: SafeArea(
          child: Stack(
            children: [
          Column(
            children: [
              // Üst Simülatör HUD Paneli (Sadece HUD gerektiğinde güncellenir)
              ListenableBuilder(
                listenable: _hudRevision,
                builder: (context, _) => _buildTopHUD(touch),
              ),

              // Oyun Alanı veya Tam Ekran 1. Şahıs Kasiyer Kamera Açısı
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _isCashierViewOpen
                      ? CashierFirstPersonView(
                          key: ValueKey('cashier_${_activeCashierCounterIndex}_${_activeCashierCustomer?.id ?? 'waiting'}'),
                          engine: _engine,
                          customer: _activeCashierCustomer,
                          counterIndex: _activeCashierCounterIndex,
                          onClose: _exitCashierView,
                          onPaymentCollected: _onCashierPaymentCollected,
                        )
                      : LayoutBuilder(
                          key: const ValueKey('market_world_view'),
                          builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);

                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onHover: (event) {
                            final worldPos = _screenToWorld(event.localPosition, size);
                            if (worldPos != null) {
                              _engine.setMousePosition(worldPos.dx, worldPos.dy);
                            }
                          },
                          child: GestureDetector(
                            onTapDown: (details) {
                              _focusNode.requestFocus();
                              if (touch) {
                                final lp = details.localPosition;
                                final padSideX = lefty ? lp.dx > size.width - 200 * cs : lp.dx < 200 * cs;
                                final actSideX = lefty ? lp.dx < 280 * cs : lp.dx > size.width - 280 * cs;
                                final inPad = padSideX && lp.dy > size.height - 200 * cs;
                                final inActions = actSideX && lp.dy > size.height - 290 * cs;
                                if (inPad || inActions) return;
                              }
                              final worldPos = _screenToWorld(details.localPosition, size);
                              if (worldPos != null) {
                                // Night: tapping a thief runs at him / swings the stick
                                if (_engine.isNight) {
                                  final thief = _engine.thiefNear(worldPos.dx, worldPos.dy, radius: 46);
                                  if (thief != null) {
                                    _engine.attackThiefAt(thief);
                                    return;
                                  }
                                }
                                // Tıklanan yer bilgisayar masası ise doğrudan aç
                                if (_engine.computerDesk.inflate(15).contains(worldPos)) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => OrderComputerDialog(engine: _engine),
                                  );
                                  return;
                                }
                                // Tıklanan yer açık kasalardan biri (veya üstündeki Paketle butonu) ise (Sadece müşteri kasası — kurye paketi yapılmaz!)
                                for (int i = 0; i < _engine.unlockedCheckoutCount; i++) {
                                  final r = _engine.checkoutCounters[i];
                                  final hitRect = Rect.fromLTRB(r.left - 18, r.top - 54, r.right + 18, r.bottom + 18);
                                  if (hitRect.contains(worldPos)) {
                                    final waitingAtThis = _engine.customers
                                        .where((c) =>
                                            c.state == CustomerState.waitingAtCheckout &&
                                            c.checkoutIndex.clamp(0, _engine.unlockedCheckoutCount - 1) == i)
                                        .toList();
                                    if (waitingAtThis.isNotEmpty) {
                                      _enterCashierView(waitingAtThis.first, i);
                                      return;
                                    }
                                    if (_engine.carriedBox != null && !_engine.carriedBox!.isCourierPackage) {
                                      _engine.spawnParticle(
                                        r.center.dx,
                                        r.top - 16,
                                        '{redx} No courier packages at the register! {box} Go to the Packing Station!',
                                        Colors.orangeAccent,
                                        size: 14,
                                      );
                                      return;
                                    }
                                    // Boş kasaya tıklandığında da 1. Şahıs Kasiyer Bakış Açısına geç!
                                    _enterCashierView(null, i);
                                    return;
                                  }
                                }

                                // Tıklanan yer {box} Kurye Paketleme Masası ise
                                if (_engine.courierPackingDesk.inflate(16).contains(worldPos)) {
                                  _engine.handleCourierPackingDeskClick();
                                  return;
                                }

                                // Tıklanan yer {bike} Hızlı Kurye Durağı ise
                                if (_engine.courierStation.inflate(35).contains(worldPos)) {
                                  _engine.deliverToCourier();
                                  return;
                                }

                                // Tıklanan yer 🧀 3D Peynir Yapma Makinesi ise
                                if (_engine.isCheeseUnlocked &&
                                    _engine.cheeseMachineRect.inflate(20).contains(worldPos)) {
                                  _engine.handleCheeseMachineClick();
                                  return;
                                }

                                // Tıklanan yer Çiftlik Üretim Alanı (açık veya kilitli) ya da Alet Standı ise
                                for (var farm in _engine.farmProducers) {
                                  if ((farm.isUnlocked && (worldPos - farm.toolStandPos).distance < 48) ||
                                      farm.rect.inflate(10).contains(worldPos)) {
                                    _engine.handleFarmZoneOrToolClick(farm, worldPos);
                                    return;
                                  }
                                }

                                // Tıklanan yer Market Rafı / Dolap ise (Her basışta 1 adet al veya eldeki koliyi diz!)
                                for (var shelf in _engine.shelves) {
                                  if (shelf.rect.inflate(10).contains(worldPos)) {
                                    _engine.handleShelfClick(shelf);
                                    return;
                                  }
                                }

                                // Aksi halde karakter tıklanan yere koşsun!
                                _engine.setTargetMove(worldPos.dx, worldPos.dy);
                              }
                            },
                            child: Stack(
                              children: [
                                // 2.5D/3D Canvas Çizimi (RepaintBoundary ile izole edildi — widget ağacı rebuild olmaz)
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: ClipRect(
                                      child: CustomPaint(
                                        painter: PixelPainter(engine: _engine),
                                      ),
                                    ),
                                  ),
                                ),

                                // Sol Üst: Mouse & Klavye İpuçları Rozeti
                                if (!touch)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.zero,
                                      border: Border.all(color: Colors.white24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.4),
                                          offset: const Offset(3, 4), blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: const Text('Click to walk  •  WASD / arrows  •  E interact  •  F swing stick (night)',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),

                                // Sağ Üst: Kamera Yakınlaştırma / Uzaklaştırma
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.zero,
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            icon: PixelIcon('minus', size: 16),
                                            onPressed: () => _engine.adjustZoom(-0.10),
                                            tooltip: 'Zoom Out (down to 50%)',
                                          ),
                                          Text(
                                            '{magnifier} ${(100 * _engine.cameraZoom).round()}%',
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            icon: PixelIcon('plus', size: 16),
                                            onPressed: () => _engine.adjustZoom(0.10),
                                            tooltip: 'Zoom In',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Toasts: customer at register / delivery at back door
                                Positioned(
                                  top: 70,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: ListenableBuilder(
                                      listenable: _hudRevision,
                                      builder: (context, _) {
                                        // Only a short alert when something arrives, nothing permanent.
                                        final showToast = _engine.toastTimer > 0 && _engine.toastText != null;
                                        if (!showToast) return const SizedBox.shrink();
                                        final isDelivery = _engine.toastKind == 1;
                                        final text = _engine.toastText!;
                                        final col = isDelivery ? const Color(0xFFFFD640) : const Color(0xFF7CE0A0);
                                        return Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xEE17120F),
                                              border: Border.all(color: col, width: 3),
                                            ),
                                            child: Text(
                                              '${isDelivery ? '\u{1F4E6}' : '\u{1F6D2}'} $text',
                                              style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w900),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                // Closing-time banner
                                Positioned(
                                  top: touch ? 8 : null,
                                  bottom: touch ? null : 14,
                                  left: 14,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) {
                                      if (!_engine.closingTime) return const SizedBox.shrink();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xEE17120F),
                                          border: Border.all(color: const Color(0xFFFFB347), width: 3),
                                        ),
                                        child: const Text(
                                          'Closing time! Waiting for the last customers to leave...\nThe night begins once the shop is empty.',
                                          style: TextStyle(color: Color(0xFFFFB347), fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // Night status banner (bottom-left)
                                Positioned(
                                  top: touch ? 8 : null,
                                  bottom: touch ? null : 14,
                                  left: 14,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) {
                                      if (!_engine.isNight) return const SizedBox.shrink();
                                      final left = _engine.phaseTimeLeft.ceil();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xDD0B1230),
                                          borderRadius: BorderRadius.zero,
                                          border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.6)),
                                        ),
                                        child: Text(
                                          '{moon} Night ${_engine.day} • Dawn in ${left}s\n'
                                          '{thief} On the prowl: ${_engine.thieves.length} • Driven off: ${_engine.nightThievesRepelled} • Stolen: ${_engine.nightStolenItems}',
                                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // Optional CRT scan-lines
                                if (st.scanlines)
                                  const Positioned.fill(
                                    child: IgnorePointer(
                                      child: RepaintBoundary(child: CustomPaint(painter: _ScanlinePainter())),
                                    ),
                                  ),

                                // Touch controls: D-pad and action buttons (swap sides when left-handed)
                                if (touch)
                                  Positioned(
                                    left: lefty ? null : 16,
                                    right: lefty ? 16 : null,
                                    bottom: 14,
                                    child: Transform.scale(
                                      scale: cs,
                                      alignment: lefty ? Alignment.bottomRight : Alignment.bottomLeft,
                                      child: _DPad(
                                        style: st.dpadStyle,
                                        onChanged: (u, d, l, r) {
                                          _keyUp = u;
                                          _keyDown = d;
                                          _keyLeft = l;
                                          _keyRight = r;
                                        },
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 14,
                                  left: lefty ? 14 : null,
                                  right: lefty ? null : 14,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) {
                                      final night = _engine.isNight;
                                      final carrying = _engine.carriedBox != null || _engine.playerTool != null;
                                      final swing = _ActionButton(
                                        size: touch ? 78 : 84,
                                        color: const Color(0xFFB45309),
                                        icon: '{bat}',
                                        label: touch ? 'SWING' : 'SWING (F)',
                                        onDown: () => _tap(_engine.swingStick),
                                      );
                                      final act = _ActionButton(
                                        size: 92,
                                        color: _engine.activeInteractionText != null
                                            ? const Color(0xFF2F8F4E)
                                            : const Color(0xFF4A3C30),
                                        icon: '{hand}',
                                        label: 'ACT',
                                        onDown: () => _tap(_executeActiveAction),
                                      );
                                      final drop = _ActionButton(
                                        size: 62,
                                        color: const Color(0xFF3D5A80),
                                        icon: '{undo}',
                                        label: 'DROP',
                                        onDown: () => _tap(_engine.quickDrop),
                                      );
                                      return Transform.scale(
                                        scale: cs,
                                        alignment: lefty ? Alignment.bottomLeft : Alignment.bottomRight,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: lefty ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                          children: [
                                            if (carrying) drop,
                                            if (carrying) const SizedBox(height: 10),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: lefty
                                                  ? [
                                                      if (touch) act,
                                                      if (touch && night) const SizedBox(width: 14),
                                                      if (night) swing,
                                                    ]
                                                  : [
                                                      if (night) swing,
                                                      if (touch && night) const SizedBox(width: 14),
                                                      if (touch) act,
                                                    ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // (No on-screen interaction hints: the ACT button turns green when something is in reach.)
                                ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                ],
              ),
              if (_tutorialSteps != null)
                TutorialOverlay(
                  step: _tutorialSteps![_tutorialIndex],
                  index: _tutorialIndex,
                  total: _tutorialSteps!.length,
                  onNext: _nextTutorialStep,
                  onSkip: _finishTutorial,
                ),
            ],
          ),
            ),
          ),
      ),
    );
  }

  Widget _buildNaturalButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
    Color surfaceColor = const Color(0xFFF4EBD3),
    Color bevelColor = const Color(0xFFCDBF9F),
    Color textColor = const Color(0xFF2A221C),
    bool compact = false,
  }) {
    return PixelPress(
      onTap: onTap,
      child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 13, vertical: compact ? 5 : 7),
          decoration: pixelDeco(surfaceColor, border: kInk, bw: 3, shadow: compact ? 2 : 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 15)),
              SizedBox(width: compact && label.length > 12 ? 4 : 6),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
      ),
    );
  }

  String _carryLabel(bool compact) {
    final box = _engine.carriedBox!;
    final def = productCatalog[box.productType]!;
    final insideFarm = _engine.farmProducers.any(
      (f) => f.rect.inflate(10).contains(Offset(_engine.playerX, _engine.playerY)),
    );
    if (insideFarm && box.isFromFarm) {
      if (box.productType == SimProductType.milk) {
        return 'Süt Kovası ${box.currentCount}/${box.maxCount}';
      } else if (box.productType == SimProductType.egg) {
        return 'Tavuk Kovası ${box.currentCount}/${box.maxCount}';
      } else if (box.productType == SimProductType.flour) {
        return 'Un ${box.currentCount}/${box.maxCount}';
      }
    }
    final head = box.isCourierPackage ? 'Package' : (compact ? '' : 'Carrying');
    final body = '${def.name} ${box.currentCount}/${box.maxCount}';
    return head.isEmpty ? body : '$head: $body';
  }

  Widget _buildTopHUD(bool compact) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16, vertical: compact ? 5 : 10),
      decoration: const BoxDecoration(
        color: Color(0xFF2A221C),
        border: Border(bottom: BorderSide(color: Color(0xFF14100E), width: 4)),
      ),
      // Everything scales down together if it does not fit (no overflow on any phone).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
        children: [
          // Kasa Parası
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 4 : 7),
            decoration: pixelDeco(const Color(0xFF17120F), border: kInk, bw: 3, shadow: 0),
            child: Row(
              children: [
                const Text('{coin}', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Text(
                  '\$${_engine.cash.toStringAsFixed(compact ? 0 : 1)}',
                  style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 12),

          // Day / night clock
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 7),
            decoration: pixelDeco(
              _engine.isNight ? const Color(0xFF1E2431) : const Color(0xFF17120F),
              border: _engine.isNight ? const Color(0xFF6FA2DD) : kInk,
              bw: 3,
              shadow: 0,
            ),
            child: Text(
              '${_engine.isNight ? '{moon}' : '{sun}'} Day ${_engine.day} • '
              '${_engine.closingTime ? 'CLOSING 0:00' : '${_engine.phaseTimeLeft.ceil() ~/ 60}:${(_engine.phaseTimeLeft.ceil() % 60).toString().padLeft(2, '0')}'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Menu',
            visualDensity: VisualDensity.compact,
            onPressed: _showPauseMenu,
            icon: PixelIcon('menu', size: 24),
          ),
          const SizedBox(width: 2),

          // Elindeki Kova / Tırpan / Koli Göstergesi
          SizedBox(
            width: compact ? 190 : 260,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4A3C30),
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: (_engine.carriedBox != null || _engine.playerTool != null)
                      ? Colors.amberAccent.withValues(alpha: 0.7)
                      : Colors.white12,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _engine.playerTool != null
                        ? _engine.playerTool!.ico
                        : (_engine.carriedBox != null ? '{box}' : '{hand}'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _engine.carriedBox != null
                          ? (_engine.playerTool != null
                              ? '${_engine.playerTool!.name} • ${_carryLabel(compact)}'
                              : _carryLabel(compact))
                          : (_engine.playerTool != null
                              ? 'Elde: ${_engine.playerTool!.name} (Hasat Et)'
                              : (compact ? 'Hands empty' : 'Hands Empty (Farm / Box)')),
                      style: TextStyle(
                        fontSize: 12,
                        color: (_engine.carriedBox == null && _engine.playerTool == null)
                            ? Colors.white70
                            : Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // {bike} Aktif Kurye Siparişi Rozeti (Paketleme & Hızlı Teslimat Butonu)
          if (_engine.courierState == CourierState.waitingForOrder && _engine.activeCourierOrder != null) ...[
            Builder(
              builder: (context) {
                final ord = _engine.activeCourierOrder!;
                final def = productCatalog[ord.productType]!;
                final hasSealedPkg = _engine.carriedBox != null &&
                    _engine.carriedBox!.productType == ord.productType &&
                    _engine.carriedBox!.isCourierPackage;
                final isPackingNow = _engine.courierStagedCount > 0 &&
                    _engine.courierStagedProduct == ord.productType;
                return _buildNaturalButton(
                  icon: hasSealedPkg ? '{bike}' : '{box}',
                  compact: compact,
                  label: hasSealedPkg
                      ? (compact ? 'Give (${ord.remainingTime.toInt()}s)' : 'Hand Package to Courier (${ord.remainingTime.toInt()}s)')
                      : (isPackingNow
                          ? 'Pack (${(_engine.courierPackingProgress * 100).toInt()}%) (${ord.remainingTime.toInt()}s)'
                          : (compact
                              ? '${ord.deliveredQty}/${ord.requiredQty} ${def.ico} ${ord.remainingTime.toInt()}s'
                              : '${ord.deliveredQty}/${ord.requiredQty} ${def.ico} Pack & Send (${ord.remainingTime.toInt()}s)')),
                  surfaceColor: hasSealedPkg ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  bevelColor: hasSealedPkg ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  textColor: hasSealedPkg ? const Color(0xFF14532D) : const Color(0xFF78350F),
                  onTap: () => _engine.deliverToCourier(),
                );
              },
            ),
            SizedBox(width: compact ? 6 : 10),
          ],

          // 1. Şahıs Kasiyer Bakış Açısı Tuşu
          _buildNaturalButton(
            icon: '{register}',
            compact: compact,
            label: _isCashierViewOpen ? 'Back to Store' : 'Cashier View',
            surfaceColor: _isCashierViewOpen ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
            bevelColor: _isCashierViewOpen ? const Color(0xFF16A34A) : const Color(0xFF8A5A33),
            textColor: _isCashierViewOpen ? const Color(0xFF14532D) : const Color(0xFF0C4A6E),
            onTap: () {
              if (_isCashierViewOpen) {
                _exitCashierView();
              } else {
                _enterCashierView(null, 0);
              }
            },
          ),
          SizedBox(width: compact ? 6 : 10),

          // Bilgisayar (Toptan Sipariş) Doğal Tuşu
          _buildNaturalButton(
            icon: '{computer}',
            compact: compact,
            label: 'Computer',
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => OrderComputerDialog(engine: _engine),
              );
            },
          ),
          SizedBox(width: compact ? 6 : 10),

          // Yönetici & Market Yönetimi Doğal Tuşu
          _buildNaturalButton(
            icon: '{case}',
            compact: compact,
            label: compact ? 'Lv.${_engine.storeLevel}' : 'Manager (Lv.${_engine.storeLevel})',
            surfaceColor: const Color(0xFFEDE9FE),
            bevelColor: const Color(0xFFC4B5FD),
            textColor: const Color(0xFF3B0764),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => ManageStoreDialog(engine: _engine),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}

// ===================================================================
// Touch controls
// ===================================================================

/// Pixel-style D-pad. Slide the thumb across it to change direction; diagonals work.
class _DPad extends StatefulWidget {
  final int style; // 0 = cross, 1 = round
  final void Function(bool up, bool down, bool left, bool right) onChanged;
  const _DPad({required this.onChanged, this.style = 0});

  @override
  State<_DPad> createState() => _DPadState();
}

class _DPadState extends State<_DPad> {
  static const double _size = 156;
  int? _pointer;
  bool _u = false, _d = false, _l = false, _r = false;

  void _update(Offset p) {
    const c = Offset(_size / 2, _size / 2);
    final v = p - c;
    final dist = v.distance;
    bool u = false, d = false, l = false, r = false;
    if (dist > 16) {
      final thr = dist * 0.38;
      l = v.dx < -thr;
      r = v.dx > thr;
      u = v.dy < -thr;
      d = v.dy > thr;
    }
    if (u != _u || d != _d || l != _l || r != _r) {
      setState(() {
        _u = u;
        _d = d;
        _l = l;
        _r = r;
      });
      widget.onChanged(u, d, l, r);
    }
  }

  void _release() {
    _pointer = null;
    if (_u || _d || _l || _r) {
      setState(() {
        _u = _d = _l = _r = false;
      });
    }
    widget.onChanged(false, false, false, false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointer ??= e.pointer;
        if (_pointer == e.pointer) _update(e.localPosition);
      },
      onPointerMove: (e) {
        if (_pointer == e.pointer) _update(e.localPosition);
      },
      onPointerUp: (e) {
        if (_pointer == e.pointer) _release();
      },
      onPointerCancel: (e) {
        if (_pointer == e.pointer) _release();
      },
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(painter: _DPadPainter(_u, _d, _l, _r, widget.style)),
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  final bool u, d, l, r;
  final int style;
  _DPadPainter(this.u, this.d, this.l, this.r, this.style);

  void _paintRound(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    const cell = 6.0;
    final c = Offset(size.width / 2, size.height / 2);
    final R = size.width / 2 - 2;
    void disc(double radius, Color col) {
      p.color = col;
      for (double y = -radius; y < radius; y += cell) {
        final yy = y + cell / 2;
        final hw = (radius * radius - yy * yy);
        if (hw <= 0) continue;
        final half = (sqrt(hw) / cell).floor() * cell;
        canvas.drawRect(Rect.fromLTWH(c.dx - half, c.dy + y, half * 2, cell), p);
      }
    }

    disc(R + 6, const Color(0x55000000));
    disc(R, const Color(0xFF14100E));
    disc(R - 6, const Color(0xFF3A2E24));
    disc(R - 30, const Color(0xFF2A221C));
    // direction marks
    void mark(double dx, double dy, bool on) {
      final q = Rect.fromCenter(center: c + Offset(dx, dy) * (R * 0.66), width: 24, height: 24);
      p.color = const Color(0xFF14100E);
      canvas.drawRect(q.inflate(3), p);
      p.color = on ? const Color(0xFFF2CF4A) : const Color(0xFF5A4A3C);
      canvas.drawRect(q, p);
      p.color = on ? const Color(0xFF3A2A10) : const Color(0xFFEDE6D6);
      const a = 4.0;
      for (final o in [const Offset(0, 0), const Offset(-1, 1), const Offset(1, 1), const Offset(0, -1), const Offset(-2, 2), const Offset(2, 2)]) {
        // arrow pointing "up", rotated to the mark direction
        double ox = o.dx, oy = o.dy;
        if (dx == 0 && dy == 1) {
          oy = -oy;
        } else if (dx == -1) {
          final t = ox;
          ox = oy;
          oy = t;
        } else if (dx == 1) {
          final t = ox;
          ox = -oy;
          oy = t;
        }
        canvas.drawRect(Rect.fromCenter(center: q.center + Offset(ox * a, oy * a - (dy == 0 ? 0 : 0)), width: a, height: a), p);
      }
    }

    mark(0, -1, u);
    mark(0, 1, d);
    mark(-1, 0, l);
    mark(1, 0, r);
    // thumb nub moves toward the pressed direction
    final nx = ((r ? 1 : 0) - (l ? 1 : 0)).toDouble();
    final ny = ((d ? 1 : 0) - (u ? 1 : 0)).toDouble();
    final on = nx != 0 || ny != 0;
    final nc = c + Offset(nx, ny) * 16;
    p.color = const Color(0xFF14100E);
    canvas.drawRect(Rect.fromCenter(center: nc, width: 34, height: 34), p);
    p.color = on ? const Color(0xFFF2CF4A) : const Color(0xFF75634F);
    canvas.drawRect(Rect.fromCenter(center: nc, width: 28, height: 28), p);
    p.color = on ? const Color(0xFFFFE98A) : const Color(0xFF8D7A62);
    canvas.drawRect(Rect.fromLTWH(nc.dx - 14, nc.dy - 14, 28, 5), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (style == 1) {
      _paintRound(canvas, size);
      return;
    }
    final p = Paint()..isAntiAlias = false;
    final w = size.width;
    final arm = w / 3; // thickness of each arm
    void rect(Rect rc, Color c) {
      p.color = c;
      canvas.drawRect(rc, p);
    }

    void btn(Rect rc, bool on, List<Offset> arrowPx) {
      rect(rc.inflate(4), const Color(0xFF14100E));
      rect(rc, on ? const Color(0xFFF2CF4A) : const Color(0xFF5A4A3C));
      rect(Rect.fromLTWH(rc.left, rc.top, rc.width, 4), on ? const Color(0xFFFFE98A) : const Color(0xFF75634F));
      // arrow made of squares
      final col = on ? const Color(0xFF3A2A10) : const Color(0xFFEDE6D6);
      final u8 = 5.0;
      for (final a in arrowPx) {
        rect(Rect.fromLTWH(rc.center.dx + a.dx * u8 - u8 / 2, rc.center.dy + a.dy * u8 - u8 / 2, u8, u8), col);
      }
    }

    // shadow plate
    rect(Rect.fromLTWH(w / 2 - arm / 2 - 2, 6, arm + 4, w - 4), const Color(0x66000000));
    rect(Rect.fromLTWH(6, w / 2 - arm / 2 - 2, w - 4, arm + 4), const Color(0x66000000));

    final upR = Rect.fromLTWH(arm, 0, arm, arm);
    final dnR = Rect.fromLTWH(arm, 2 * arm, arm, arm);
    final lfR = Rect.fromLTWH(0, arm, arm, arm);
    final rtR = Rect.fromLTWH(2 * arm, arm, arm, arm);
    rect(Rect.fromLTWH(arm - 4, arm - 4, arm + 8, arm + 8), const Color(0xFF14100E));
    rect(Rect.fromLTWH(arm, arm, arm, arm), const Color(0xFF3A2E24));

    btn(upR.deflate(2), u, const [Offset(0, -1), Offset(-1, 0), Offset(0, 0), Offset(1, 0), Offset(-2, 1), Offset(2, 1)]);
    btn(dnR.deflate(2), d, const [Offset(0, 1), Offset(-1, 0), Offset(0, 0), Offset(1, 0), Offset(-2, -1), Offset(2, -1)]);
    btn(lfR.deflate(2), l, const [Offset(-1, 0), Offset(0, -1), Offset(0, 0), Offset(0, 1), Offset(1, -2), Offset(1, 2)]);
    btn(rtR.deflate(2), r, const [Offset(1, 0), Offset(0, -1), Offset(0, 0), Offset(0, 1), Offset(-1, -2), Offset(-1, 2)]);
  }

  @override
  bool shouldRepaint(covariant _DPadPainter o) => o.u != u || o.d != d || o.l != l || o.r != r || o.style != style;
}

/// Big square pixel action button (fires on touch-down, multi-touch friendly).
class _ActionButton extends StatefulWidget {
  final double size;
  final Color color;
  final String icon;
  final String label;
  final VoidCallback onDown;
  const _ActionButton({
    required this.size,
    required this.color,
    required this.icon,
    required this.label,
    required this.onDown,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        setState(() => _down = true);
        widget.onDown();
      },
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: Transform.translate(
        offset: Offset(0, _down ? 3 : 0),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: pixelDeco(_down ? Color.lerp(widget.color, Colors.white, 0.3)! : widget.color,
              border: kGold, bw: 4, shadow: _down ? 1 : 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.icon, style: TextStyle(fontSize: widget.size < 70 ? 20 : 26)),
                  Text(widget.label,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint horizontal lines for the optional CRT look.
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x22000000)
      ..isAntiAlias = false;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => false;
}
