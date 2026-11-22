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
          fontFamily: 'monospace',
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF2A221C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFF14100E), width: 4),
            ),
          ),
        ),
        home: const MainMenuScreen(),
      ),
    );
  }
}
