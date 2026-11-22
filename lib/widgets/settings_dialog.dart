import 'package:material_ui/material_ui.dart' hide Text;
import '../audio/audio_service.dart';
import '../settings/settings_service.dart';
import 'pixel_ui.dart';

/// Game settings (audio + controls + look). Used from the main menu and the pause menu.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _s = SettingsService.instance;
  final _a = AudioService.instance;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.w900)),
      );

  @override
  Widget build(BuildContext context) {
    return PixelDialog(
      title: const Text('Settings'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label('AUDIO'),
          PixelToggle(
            label: 'Music',
            value: _a.musicOn,
            onChanged: (v) async {
              await _a.setMusicOn(v);
              setState(() {});
            },
          ),
          Row(children: [
            const SizedBox(width: 78, child: Text('Volume', style: TextStyle(fontSize: 14))),
            Expanded(
              child: PixelSlider(
                value: _a.musicVol,
                onChanged: (v) {
                  _a.setMusicVolume(v);
                  setState(() {});
                },
              ),
            ),
          ]),
          const SizedBox(height: 6),
          PixelToggle(
            label: 'Sound effects',
            value: _a.sfxOn,
            onChanged: (v) async {
              await _a.setSfxOn(v);
              setState(() {});
            },
          ),
          Row(children: [
            const SizedBox(width: 78, child: Text('Volume', style: TextStyle(fontSize: 14))),
            Expanded(
              child: PixelSlider(
                value: _a.sfxVol,
                onChanged: (v) {
                  _a.setSfxVolume(v);
                  _a.sfx('click');
                  setState(() {});
                },
              ),
            ),
          ]),
          _label('CONTROLS'),
          const Text('D-pad style', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          PixelChoice(
            labels: const ['Cross', 'Round'],
            selected: _s.dpadStyle,
            onChanged: (i) => setState(() => _s.update(dpadStyle: i)),
          ),
          const SizedBox(height: 10),
          const Text('Button size', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          PixelChoice(
            labels: const ['Small', 'Medium', 'Large'],
            selected: _s.controlSize,
            onChanged: (i) => setState(() => _s.update(controlSize: i)),
          ),
          const SizedBox(height: 8),
          PixelToggle(
            label: 'Left-handed layout',
            value: _s.leftHanded,
            onChanged: (v) => setState(() => _s.update(leftHanded: v)),
          ),
          PixelToggle(
            label: 'Vibration',
            value: _s.haptics,
            onChanged: (v) => setState(() => _s.update(haptics: v)),
          ),
          _label('LOOK'),
          PixelToggle(
            label: 'CRT scan-lines',
            value: _s.scanlines,
            onChanged: (v) => setState(() => _s.update(scanlines: v)),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
