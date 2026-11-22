import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'providers/game_provider.dart';
import 'screens/simulation_screen.dart';

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
        title: 'Supermarket Simulator',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.orange,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          fontFamily: 'Segoe UI',
        ),
        home: const SimulationScreen(),
      ),
    );
  }
}
