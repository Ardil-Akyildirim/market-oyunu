// Shared pixel-art UI kit: sprites, icon widget, token-aware Text and helpers.
//
// Import with:   import 'package:material_ui/material_ui.dart' hide Text;
//                import '../widgets/pixel_ui.dart';
// The `Text` exported here is a drop-in replacement: any {name} token in the
// string (e.g. '{moon} Night 2' or '{milk}') is drawn as a pixel icon instead of an emoji.
import 'dart:async';
import '../audio/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as m;

const String kPixelFont = 'Pixelify';

// Shared palette for panels / buttons.
const Color kInk = Color(0xFF14100E);
const Color kPanelDark = Color(0xFF241B15);
const Color kPanelMid = Color(0xFF3A2C22);
const Color kParchment = Color(0xFFE9DFC6);
const Color kGold = Color(0xFFF2CF4A);

/// Flat fill + chunky dark border + hard drop shadow (no blur, no rounding).
BoxDecoration pixelDeco(Color fill, {Color border = kInk, double bw = 3, double shadow = 4}) {
  return BoxDecoration(
    color: fill,
    border: Border.all(color: border, width: bw),
    boxShadow: shadow <= 0
        ? null
        : [BoxShadow(color: const Color(0xAA000000), offset: Offset(shadow, shadow), blurRadius: 0)],
  );
}

class PixelSprites {
  static const Map<String, Color> _pal = {
    'K': Color(0xFF14100E),
    'W': Color(0xFFF4F1E6),
    'G': Color(0xFF9AA3AB),
    'g': Color(0xFF4A525A),
    'R': Color(0xFFD33A2C),
    'r': Color(0xFF8E241C),
    'O': Color(0xFFE8872A),
    'Y': Color(0xFFF2CF4A),
    'y': Color(0xFFB88A1E),
    'N': Color(0xFFB9742E),
    'n': Color(0xFF6B4423),
    'L': Color(0xFF3FA13A),
    'l': Color(0xFF2B6B28),
    'B': Color(0xFF3B78C2),
    'b': Color(0xFF6FA2DD),
    'P': Color(0xFFE0B08A),
    'p': Color(0xFF7A4FB0),
    'C': Color(0xFFF1E3C2)
  };

  static const Map<String, List<String>> _art = {
    'milk': ['..KKKK..', '.KbbbbK.', '.KBBBBK.', '.KWWWWK.', '.KWBBWK.', '.KWBBWK.', '.KWWWWK.', '..KKKK..'],
    'flour': ['..KKKK..', '..KnnK..', '.KCCCCK.', 'KCCCCCCK', 'KCCnnCCK', 'KCCCCCCK', 'KCCCCCCK', '.KKKKKK.'],
    'egg': ['...KK...', '..KCCK..', '.KCWCCK.', '.KCCCCK.', '.KCCCCK.', '.KCCCCK.', '..KCCK..', '...KK...'],
    'tomato': ['...LL...', '..KLLK..', '.KRRRRK.', 'KRWRRRRK', 'KRRRRRRK', 'KRRRRrRK', '.KRrrrK.', '..KKKK..'],
    'pepper': ['.....nK.', '...KKLK.', '..KLLlK.', '..KLLlK.', '.KLLllK.', '.KLLlK..', '.KLlK...', '..KK....'],
    'apple': ['....nL..', '..KKnKK.', '.KLLLLLK', 'KLWLLLLK', 'KLLLLLLK', 'KLLLLllK', '.KLllLK.', '..KKKK..'],
    'cheese': ['........', '....KKK.', '..KKYYYK', '.KYYYyYK', 'KYYyYYYK', 'KYYYYYYK', 'KKKKKKKK', '........'],
    'bread': ['........', '..KKKK..', '.KNYYNK.', 'KNYNNYNK', 'KNNNNNNK', 'KNNnnNNK', '.KKKKKK.', '........'],
    'moon': ['..KKK...', '.KYYYK..', 'KYYK.KK.', 'KYYK....', 'KYYK....', 'KYYYK.K.', '.KYYYYK.', '..KKKK..'],
    'sun': ['...O....', '.O.Y.O..', '..KYYK..', 'OYYYYYYO', '..KYYK..', '.O.Y.O..', '...O....', '........'],
    'coin': ['..KKKK..', '.KYYYYK.', 'KYYnnYYK', 'KYnYYYYK', 'KYYnnYYK', 'KYYYYnYK', '.KYnnYK.', '..KKKK..'],
    'box': ['.KKKKKK.', 'KNYYYYNK', 'KNNYYNNK', 'KNNYYNNK', 'KNNNNNNK', 'KNnnnnNK', 'KNNNNNNK', '.KKKKKK.'],
    'cart': ['K.......', 'KKKKKKK.', '.KGGGGGK', '.KGGGGK.', '..KGGGK.', '..KKKKK.', '..K...K.', '.KK..KK.'],
    'computer': ['KKKKKKKK', 'KbbbbbbK', 'KbWWbbbK', 'KbbbbbbK', 'KKKKKKKK', '..KggK..', '.KKKKKK.', '........'],
    'case': ['...KK...', '..K..K..', 'KKKKKKKK', 'KNNNNNNK', 'KNNyyNNK', 'KNNNNNNK', 'KnnnnnnK', 'KKKKKKKK'],
    'register': ['..KKKK..', '..KbbK..', '.KKKKKK.', 'KGGGGGGK', 'KGWGWGWK', 'KGGGGGGK', 'KnnnnnnK', 'KKKKKKKK'],
    'thief': ['..KKKK..', '.KggggK.', 'KggggggK', 'KKKKKKKK', 'KPWPPWPK', 'KPPPPPPK', '.KPPPPK.', '..KKKK..'],
    'bat': ['......KK', '.....KNK', '....KNNK', '...KNNK.', '..KNNK..', '.KNNK...', 'KnNK....', 'KKK.....'],
    'burst': ['Y..Y..Y.', '.Y.Y.Y..', '..YOY...', 'YYOROYYY', '..YOY...', '.Y.Y.Y..', 'Y..Y..Y.', '........'],
    'shop': ['KKKKKKKK', 'KRWRWRWK', 'KRWRWRWK', 'KKKKKKKK', 'KWWWWWWK', 'KWbbKnWK', 'KWbbKnWK', 'KKKKKKKK'],
    'boots': ['..KK....', '..KgK...', '..KgK...', '..KgKKK.', '.KggggK.', '.KggggK.', 'KKKKKKK.', '........'],
    'gear': ['...KK...', '.K.KK.K.', '..KGGK..', 'KKGKKGKK', 'KKGKKGKK', '..KGGK..', '.K.KK.K.', '...KK...'],
    'lock': ['..KKKK..', '.KG..GK.', '.KG..GK.', 'KKKKKKKK', 'KYYYYYYK', 'KYYKKYYK', 'KYYYYYYK', 'KKKKKKKK'],
    'unlock': ['..KKKK..', '.KG..GK.', '.KG.....', 'KKKKKKKK', 'KYYYYYYK', 'KYYKKYYK', 'KYYYYYYK', 'KKKKKKKK'],
    'check': ['.......K', '......KL', 'K....KL.', 'KL..KL..', 'KLKKL...', '.KLL....', '..K.....', '........'],
    'warn': ['...KK...', '..KYYK..', '..KYYK..', '.KYKKYK.', '.KYKKYK.', 'KYYYYYYK', 'KYYKKYYK', 'KKKKKKKK'],
    'info': ['..KKKK..', '.KBBBBK.', 'KBBWWBBK', 'KBBBBBBK', 'KBBWWBBK', 'KBBWWBBK', '.KBBBBK.', '..KKKK..'],
    'x': ['W......W', 'WW....WW', '.WW..WW.', '..WWWW..', '..WWWW..', '.WW..WW.', 'WW....WW', 'W......W'],
    'redx': ['R......R', 'RR....RR', '.RR..RR.', '..RRRR..', '..RRRR..', '.RR..RR.', 'RR....RR', 'R......R'],
    'plus': ['...WW...', '...WW...', '...WW...', 'WWWWWWWW', 'WWWWWWWW', '...WW...', '...WW...', '...WW...'],
    'minus': ['........', '........', '........', 'WWWWWWWW', 'WWWWWWWW', '........', '........', '........'],
    'back': ['....W...', '...WW...', '..WWW...', '.WWWWWWW', '..WWW...', '...WW...', '....W...', '........'],
    'truck': ['........', '.KKKKK..', '.KWWWKKK', '.KWWWKbK', '.KWWWKKK', '.KKKKKKK', '..K..K..', '........'],
    'bike': ['......KK', '.....KR.', '..KKKKR.', '.KRRRKK.', 'KKKKKKK.', 'KgK.KgK.', '.K...K..', '........'],
    'card': ['........', 'KKKKKKKK', 'KBBBBBBK', 'KKKKKKKK', 'KBBBBBBK', 'KBWWBBBK', 'KKKKKKKK', '........'],
    'bag': ['..K..K..', '..KKKK..', '.KNNNNK.', 'KNNNNNNK', 'KNNyyNNK', 'KNNNNNNK', 'KNNNNNNK', '.KKKKKK.'],
    'undo': ['...K....', '..KK....', '.KKKKKK.', '..KK..KK', '...K...K', '.......K', '..K...KK', '...KKKK.'],
    'note': ['..KKKKK.', '..KWWWK.', '..KKKWK.', '..K..WK.', '.KK.KWK.', 'KWWKKKK.', 'KWWK....', '.KK.....'],
    'speaker': ['...K....', '..KW....', 'KKKWK.K.', 'KWWWK..K', 'KWWWK..K', 'KKKWK.K.', '..KW....', '...K....'],
    'hand': ['..K.K...', '.KPKPK..', '.KPKPKK.', '.KPPPPPK', 'KKPPPPPK', 'KPPPPPK.', '.KPPPPK.', '..KKKK..'],
    'magnifier': ['.KKKK...', 'KWbbWK..', 'KbbbbK..', 'KbbbbK..', '.KKKKK..', '.....KK.', '......KK', '.......K'],
    'face': ['..KKKK..', '.KnnnnK.', 'KnPPPPnK', 'KPKPPKPK', 'KPPPPPPK', 'KPPKKPPK', '.KPPPPK.', '..KKKK..'],
    'hardhat': ['..KKKK..', '.KYYYYK.', 'KYYYYYYK', 'KKKKKKKK', '.KPPPPK.', '.KPKKPK.', '.KPPPPK.', '..KKKK..'],
    'bell': ['...KK...', '..KYYK..', '.KYYYYK.', '.KYYYYK.', 'KYYYYYYK', 'KKKKKKKK', '...KK...', '........'],
    'star': ['...YY...', '...YY...', 'YYYYYYYY', '.YYYYYY.', '..YYYY..', '.YYYYYY.', '.YY..YY.', '........'],
    'clock': ['KKKKKKKK', '.KWWWWK.', '..KWWK..', '...KK...', '...KK...', '..KYYK..', '.KYYYYK.', 'KKKKKKKK'],
    'dot': ['........', '..KKKK..', '.KRRRRK.', '.KRRRRK.', '.KRRRRK.', '.KRRRRK.', '..KKKK..', '........'],
    'menu': ['........', 'WWWWWWWW', 'WWWWWWWW', '........', 'WWWWWWWW', 'WWWWWWWW', '........', '........'],
    'heart': ['........', '.KK..KK.', 'KRRKKRRK', 'KRWRRRRK', 'KRRRRRRK', '.KRRRRK.', '..KRRK..', '...KK...']
  };

  static bool has(String name) => _art.containsKey(name);

  /// Draws sprite [name] with its top-left at [at]; each art pixel is [px] logical pixels.
  static void paint(Canvas canvas, String name, Offset at, double px, {bool slash = false, bool dark = false}) {
    final rows = _art[name];
    if (rows == null) return;
    final p = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;
    for (int y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (int x = 0; x < row.length; x++) {
        var c = _pal[row[x]];
        if (c == null) continue;
        if (dark && row[x] == 'W') c = const Color(0xFF2A221C);
        p.color = c;
        final l = (at.dx + x * px).floorToDouble();
        final t = (at.dy + y * px).floorToDouble();
        final r = (at.dx + (x + 1) * px).floorToDouble();
        final b = (at.dy + (y + 1) * px).floorToDouble();
        canvas.drawRect(Rect.fromLTRB(l, t, r, b), p);
      }
    }
    if (slash) {
      p.color = const Color(0xFFD33A2C);
      for (int i = 0; i < 8; i++) {
        final l = (at.dx + i * px).floorToDouble();
        final t = (at.dy + (7 - i) * px).floorToDouble();
        canvas.drawRect(Rect.fromLTRB(l, t, l + px, t + px), p);
      }
    }
  }
}

class _SpritePainter extends CustomPainter {
  final String name;
  final double px;
  final bool slash;
  final bool dark;
  _SpritePainter(this.name, this.px, this.slash, this.dark);

  @override
  void paint(Canvas canvas, Size size) =>
      PixelSprites.paint(canvas, name, Offset.zero, px, slash: slash, dark: dark);

  @override
  bool shouldRepaint(covariant _SpritePainter o) =>
      o.name != name || o.px != px || o.slash != slash || o.dark != dark;
}

/// A crisp pixel icon. [size] is rounded to a whole multiple of 8 so pixels stay square.
class PixelIcon extends StatelessWidget {
  final String name;
  final double size;
  final bool slash;
  /// Use on light backgrounds: white strokes become dark.
  final bool dark;
  const PixelIcon(this.name, {super.key, this.size = 24, this.slash = false, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final px = (size / 8).round().clamp(1, 12).toDouble();
    return SizedBox(
      width: 8 * px,
      height: 8 * px,
      child: CustomPaint(painter: _SpritePainter(name, px, slash, dark)),
    );
  }
}

final RegExp _token = RegExp(r'\{([a-z_]+)\}');

/// Real emoji never render in this game: anything that slips in is stripped.
final RegExp _emojiRe = RegExp(
    r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
    unicode: true);

/// Drop-in replacement for Flutter's Text that understands {icon} tokens.
class Text extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  const Text(this.data, {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap});

  @override
  Widget build(BuildContext context) {
    final String data = this.data.replaceAll(_emojiRe, '');
    // Tiny pixel text smears digits (2/3/8), so never go below 12.
    final TextStyle? style = (this.style?.fontSize != null && this.style!.fontSize! < 12)
        ? this.style!.copyWith(fontSize: 12)
        : this.style;
    if (!data.contains('{')) {
      return m.Text(data, style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap);
    }
    final base = DefaultTextStyle.of(context).style.merge(style);
    final fs = base.fontSize ?? 14.0;
    final iconSize = (fs * 1.2 / 8).round().clamp(1, 8) * 8.0;
    final spans = <m.InlineSpan>[];
    int last = 0;
    for (final mt in _token.allMatches(data)) {
      final name = mt.group(1)!;
      if (!PixelSprites.has(name)) continue;
      if (mt.start > last) spans.add(TextSpan(text: data.substring(last, mt.start)));
      spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: PixelIcon(name, size: iconSize)));
      last = mt.end;
    }
    if (last < data.length) spans.add(TextSpan(text: data.substring(last)));
    return m.Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}

/// Pixel-style replacement for AlertDialog (hard border, hard shadow, gold title bar).
class PixelDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  // Accepted (and ignored) so it can replace AlertDialog without touching call sites.
  final Color? backgroundColor;
  const PixelDialog({super.key, this.title, this.content, this.actions, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(MediaQuery.of(context).size.height < 500 ? 8 : 16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: pixelDeco(kPanelDark, bw: 4, shadow: 6),
            padding: MediaQuery.of(context).size.height < 500
                ? const EdgeInsets.fromLTRB(14, 8, 14, 10)
                : const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  DefaultTextStyle(
                    style: const TextStyle(fontFamily: kPixelFont, color: kGold, fontSize: 22, fontWeight: FontWeight.w900),
                    child: title!,
                  ),
                if (title != null) ...[
                  const SizedBox(height: 8),
                  Container(height: 4, color: kInk),
                  const SizedBox(height: 12),
                ],
                if (content != null)
                  Flexible(
                    child: DefaultTextStyle(
                      style: const TextStyle(fontFamily: kPixelFont, color: Colors.white70, fontSize: 15),
                      child: SingleChildScrollView(child: content!),
                    ),
                  ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: actions!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps any pixel "button": on press it sinks 3px and flashes lighter, so a tap is visible.
class PixelPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool click; // play the click sfx
  const PixelPress({super.key, required this.child, required this.onTap, this.click = true});

  @override
  State<PixelPress> createState() => _PixelPressState();
}

class _PixelPressState extends State<PixelPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => Future.delayed(const Duration(milliseconds: 90), () => _set(false)),
      onPointerCancel: (_) => _set(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.click) AudioService.instance.sfx('click');
                widget.onTap!();
              },
        child: Transform.translate(
          offset: Offset(0, _down ? 3 : 0),
          child: Stack(
            children: [
              widget.child,
              if (_down) const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x44FFFFFF)))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square ON/OFF toggle row (replaces SwitchListTile).
class PixelToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const PixelToggle({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PixelPress(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16))),
            Container(
              width: 64,
              height: 30,
              alignment: Alignment.center,
              decoration: pixelDeco(value ? const Color(0xFF3F9B5A) : const Color(0xFF5A4A3C), bw: 3, shadow: 3),
              child: Text(value ? 'ON' : 'OFF',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small top-of-screen notification (replaces SnackBars, which pop up at the bottom).
// ---------------------------------------------------------------------------
OverlayEntry? _toastEntry;
Timer? _toastTimer;

void showTopToast(BuildContext context, String text, {Color color = const Color(0xFF7CE0A0), int ms = 1900}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toastEntry?.remove();
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 50,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pixelDeco(const Color(0xEE17120F), border: color, bw: 3, shadow: 3),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
  _toastTimer = Timer(Duration(milliseconds: ms), () {
    entry.remove();
    if (_toastEntry == entry) _toastEntry = null;
  });
}

// ---------------------------------------------------------------------------
// Pixel slider (10 blocks) and option chips for the settings screen.
// ---------------------------------------------------------------------------
class PixelSlider extends StatelessWidget {
  final double value; // 0..1
  final ValueChanged<double> onChanged;
  const PixelSlider({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 200.0;
      void at(double dx) => onChanged(((dx / w) * 10).ceil().clamp(0, 10) / 10.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => at(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              for (int i = 0; i < 10; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    decoration: BoxDecoration(
                      color: i < (value * 10).round() ? kGold : const Color(0xFF4A3C30),
                      border: Border.all(color: kInk, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class PixelChoice extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const PixelChoice({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (int i = 0; i < labels.length; i++)
          PixelPress(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: pixelDeco(i == selected ? const Color(0xFFD9A441) : const Color(0xFF4A3C30), bw: 3, shadow: 2),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: i == selected ? const Color(0xFF1C1209) : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
