import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'providers/game_provider.dart';
import 'screens/main_menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: 'Pixelify', fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );
}
