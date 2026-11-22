import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player preferences that are not audio (audio keeps its own settings).
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// 0 = cross D-pad, 1 = round D-pad
  int dpadStyle = 0;

  /// 0 = small, 1 = medium, 2 = large
  int controlSize = 1;

  /// Swap the D-pad and the action buttons.
  bool leftHanded = false;

  /// Vibrate a tiny bit when pressing ACT / SWING / DROP.
  bool haptics = true;

  /// Faint CRT scan-lines over the game view.
  bool scanlines = false;

  bool _loaded = false;

  double get controlScale => const [0.82, 1.0, 1.2][controlSize.clamp(0, 2)];

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      dpadStyle = p.getInt('set_dpad_style') ?? 0;
      controlSize = p.getInt('set_control_size') ?? 1;
      leftHanded = p.getBool('set_left_handed') ?? false;
      haptics = p.getBool('set_haptics') ?? true;
      scanlines = p.getBool('set_scanlines') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('set_dpad_style', dpadStyle);
      await p.setInt('set_control_size', controlSize);
      await p.setBool('set_left_handed', leftHanded);
      await p.setBool('set_haptics', haptics);
      await p.setBool('set_scanlines', scanlines);
    } catch (_) {}
  }

  void update({int? dpadStyle, int? controlSize, bool? leftHanded, bool? haptics, bool? scanlines}) {
    this.dpadStyle = dpadStyle ?? this.dpadStyle;
    this.controlSize = controlSize ?? this.controlSize;
    this.leftHanded = leftHanded ?? this.leftHanded;
    this.haptics = haptics ?? this.haptics;
    this.scanlines = scanlines ?? this.scanlines;
    notifyListeners();
    _save();
  }
}
