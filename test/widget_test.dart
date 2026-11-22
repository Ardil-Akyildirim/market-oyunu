import 'package:flutter_test/flutter_test.dart';
import 'package:market_oyunu/main.dart';

void main() {
  testWidgets('Supermarket Simulation smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MarketGameApp());
    expect(find.text('PLAY'), findsOneWidget);
  });
}
