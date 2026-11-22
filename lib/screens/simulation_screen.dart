import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../widgets/pixel_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
  const SimulationScreen({super.key, this.forceTutorial = false});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> with SingleTickerProviderStateMixin {
  late final SimulationEngine _engine;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

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
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;

      if (dt > 0.1) return;

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

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _ticker.dispose();
    _engine.onSfx = null;
    AudioService.instance.stopMusic();
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
                'Controls: WASD / arrows or tap to move, E / Space to interact, F to swing the stick at night.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              PixelToggle(
                label: 'Music',
                value: AudioService.instance.musicOn,
                onChanged: (v) async {
                  await AudioService.instance.setMusicOn(v);
                  setLocal(() {});
                },
              ),
              PixelToggle(
                label: 'Sound effects',
                value: AudioService.instance.sfxOn,
                onChanged: (v) async {
                  await AudioService.instance.setSfxOn(v);
                  setLocal(() {});
                },
              ),
            ],
          ),
        ),
        actions: [
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('{bag} Package delivered and +\$${earned.toStringAsFixed(0)} collected! '),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
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
                builder: (context, _) => _buildTopHUD(),
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

                                // Tıklanan yer Çiftlik Üretim Alanı (Ahır, Tarla, Kümes) veya Kova/Tırpan Standı ise
                                for (var farm in _engine.farmProducers) {
                                  if (!farm.isUnlocked) continue;
                                  if ((worldPos - farm.toolStandPos).distance < 48 ||
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
                                    child: const Row(
                                      children: [
                                        Text('Click to walk  •  WASD / arrows  •  E interact  •  F swing stick (night)',
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
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
                                        final persistentDelivery = _engine.deliveryBoxes.isNotEmpty;
                                        final showToast = _engine.toastTimer > 0 && _engine.toastText != null;
                                        if (!showToast && !persistentDelivery) return const SizedBox.shrink();
                                        final isDelivery = showToast ? _engine.toastKind == 1 : true;
                                        final text = showToast
                                            ? _engine.toastText!
                                            : 'Boxes waiting at the BACK DOOR (south)';
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
                                  bottom: 14,
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
                                  bottom: 14,
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

                                // Night: big swing button (bottom-right)
                                Positioned(
                                  bottom: 14,
                                  right: 14,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) {
                                      if (!_engine.isNight) return const SizedBox.shrink();
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (_) => _engine.swingStick(),
                                        child: Container(
                                          width: 84,
                                          height: 84,
                                          decoration: pixelDeco(const Color(0xFFB45309), border: kGold, bw: 4, shadow: 4),
                                          child: const Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text('{bat}', style: TextStyle(fontSize: 30)),
                                              Text('SWING (F)',
                                                  style: TextStyle(
                                                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // Doğal Durum / Etkileşim Bilgilendirmesi
                                Positioned(
                                  top: 48,
                                  left: 0,
                                  right: 0,
                                  child: ListenableBuilder(
                                    listenable: _hudRevision,
                                    builder: (context, _) {
                                      if (_engine.activeInteractionText == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Center(
                                        child: GestureDetector(
                                          onTap: _executeActiveAction,
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xDD2A221C),
                                              borderRadius: BorderRadius.zero,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.25),
                                                  blurRadius: 0,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                              border: Border.all(color: Colors.white24, width: 1.2),
                                            ),
                                            child: Text(
                                              _engine.activeInteractionText!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                                color: Colors.white,
                                              ),
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
    );
  }

  Widget _buildNaturalButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
    Color surfaceColor = const Color(0xFFF4EBD3),
    Color bevelColor = const Color(0xFFCDBF9F),
    Color textColor = const Color(0xFF2A221C),
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AudioService.instance.sfx('click');
          onTap();
        },
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: pixelDeco(surfaceColor, border: kInk, bw: 3, shadow: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
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
      ),
    );
  }

  Widget _buildTopHUD() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF2A221C),
        border: Border(bottom: BorderSide(color: Color(0xFF14100E), width: 4)),
      ),
      child: Row(
        children: [
          // Kasa Parası
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: pixelDeco(const Color(0xFF17120F), border: kInk, bw: 3, shadow: 0),
            child: Row(
              children: [
                const Text('{coin}', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Text(
                  '\$${_engine.cash.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Day / night clock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            onPressed: _showPauseMenu,
            icon: PixelIcon('menu', size: 24),
          ),
          const SizedBox(width: 4),

          // Elindeki Kova / Tırpan / Koli Göstergesi
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    _engine.carriedBox != null ? '{box}' : '{hand}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _engine.carriedBox != null
                          ? 'Carrying: ${_engine.carriedBox!.containerName} (${_engine.carriedBox!.currentCount}/${_engine.carriedBox!.maxCount})'
                          : (_engine.playerTool != null
                              ? 'Equipment: ${_engine.playerTool!.name} (Walk Inside to Harvest)'
                              : 'Hands Empty (Pick Up a Delivery Box)'),
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
                  if (_engine.carriedBox != null && _engine.carriedBox!.isPickedFromShelf) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        final box = _engine.carriedBox!;
                        _engine.returnItemsToShelfOrBox(box.productType, box.currentCount);
                        _engine.carriedBox = null;
                        _engine.spawnParticle(
                          _engine.playerX,
                          _engine.playerY - 28,
                          '{undo} Returned to Shelf',
                          Colors.lightBlueAccent,
                          size: 14,
                        );
                      },
                      borderRadius: BorderRadius.zero,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17120F),
                          borderRadius: BorderRadius.zero,
                          border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.7)),
                        ),
                        child: const Text(
                          '{undo} Returned to Shelf',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
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
                  label: hasSealedPkg
                      ? 'Hand Package to Courier (${ord.remainingTime.toInt()}s)'
                      : (isPackingNow
                          ? 'Pack (${(_engine.courierPackingProgress * 100).toInt()}%) (${ord.remainingTime.toInt()}s)'
                          : '${ord.deliveredQty}/${ord.requiredQty} ${def.ico} Pack & Send (${ord.remainingTime.toInt()}s)'),
                  surfaceColor: hasSealedPkg ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  bevelColor: hasSealedPkg ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  textColor: hasSealedPkg ? const Color(0xFF14532D) : const Color(0xFF78350F),
                  onTap: () => _engine.deliverToCourier(),
                );
              },
            ),
            const SizedBox(width: 10),
          ],

          // 1. Şahıs Kasiyer Bakış Açısı Tuşu
          _buildNaturalButton(
            icon: '{register}',
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
          const SizedBox(width: 10),

          // Bilgisayar (Toptan Sipariş) Doğal Tuşu
          _buildNaturalButton(
            icon: '{computer}',
            label: 'Computer',
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => OrderComputerDialog(engine: _engine),
              );
            },
          ),
          const SizedBox(width: 10),

          // Yönetici & Market Yönetimi Doğal Tuşu
          _buildNaturalButton(
            icon: '{case}',
            label: 'Manager (Lv.${_engine.storeLevel})',
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
    );
  }
}
