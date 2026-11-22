import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'providers/game_provider.dart';
import 'screens/main_menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only: the orientation is fixed in AndroidManifest.xml (sensorLandscape), which
  // lets the phone flip 180 degrees by itself. Calling setPreferredOrientations here would
  // override that and can pin one direction, so it is intentionally not used.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // If the user pulls the system bars down, hide them again shortly after.
  SystemChrome.setSystemUIChangeCallback((visible) async {
    if (visible) {
      await Future.delayed(const Duration(seconds: 2));
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  });
  runApp(const MarketGameApp());
}

class MarketGameApp extends StatelessWidget {
  const MarketGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
      ],
      child: MaterialApp(
        title: 'Village Market',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.orange,
          scaffoldBackgroundColor: const Color(0xFF17120F),
          fontFamily: 'Pixelify',
          splashFactory: NoSplash.splashFactory,
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF2A221C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFF14100E), width: 4),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(style: _pixelButton()),
          filledButtonTheme: FilledButtonThemeData(style: _pixelButton()),
          outlinedButtonTheme: OutlinedButtonThemeData(style: _pixelButton()),
          textButtonTheme: TextButtonThemeData(style: _pixelButton(bordered: false)),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF241B15),
            contentTextStyle: TextStyle(fontFamily: 'Pixelify', color: Colors.white, fontSize: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFFF2CF4A), width: 3),
            ),
          ),
        ),
        home: const MainMenuScreen(),
      ),
    );
  }
}

ButtonStyle _pixelButton({bool bordered = true}) {
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: bordered ? const BorderSide(color: Color(0xFF14100E), width: 3) : BorderSide.none,
    )),
    overlayColor: WidgetStateProperty.resolveWith(
      (st) => st.contains(WidgetState.pressed) ? const Color(0x55FFFFFF) : null,
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: 'Pixelify', fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );
}
