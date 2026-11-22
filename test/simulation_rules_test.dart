import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_oyunu/simulation/simulation_engine.dart';
import 'package:market_oyunu/simulation/simulation_models.dart';
import 'package:market_oyunu/simulation/dialogs/courier_packing_dialog.dart';

void main() {
  group('Market oyunu kurallari', () {
    test('3 kasa vardir ve her seviyede 1 tane acilir', () {
      final engine = SimulationEngine();
      expect(engine.checkoutCounters.length, 3);
      expect(engine.storeLevel, 1);
      expect(engine.unlockedCheckoutCount, 1);

      engine.storeLevel = 2;
      expect(engine.unlockedCheckoutCount, 2);

      engine.storeLevel = 3;
      expect(engine.unlockedCheckoutCount, 3);
    });

    test('Dolaptan (yumurta, un, sut) her basista 1 adet alinir ve rafta geri birakilmaz', () {
      final engine = SimulationEngine();
      final eggShelf = engine.shelves.firstWhere((s) => s.assignedProduct == SimProductType.egg);
      final initialStock = eggShelf.currentStock;

      // Oyuncu yumurta standinin onunde
      engine.playerX = eggShelf.rect.center.dx;
      engine.playerY = eggShelf.rect.bottom + 20;

      // 1. basis
      engine.handleShelfClick(eggShelf);
      expect(engine.carriedBox, isNotNull);
      expect(engine.carriedBox!.productType, SimProductType.egg);
      expect(engine.carriedBox!.currentCount, 1);
      expect(engine.carriedBox!.isPickedFromShelf, isTrue);
      expect(eggShelf.currentStock, initialStock - 1);

      // 2. ve 3. basis
      engine.handleShelfClick(eggShelf);
      engine.handleShelfClick(eggShelf);
      expect(engine.carriedBox!.currentCount, 3);
      expect(eggShelf.currentStock, initialStock - 3);

      // Rafta beklerken urunler otomatik rafa geri konmamali
      for (int i = 0; i < 10; i++) {
        engine.update(0.1);
      }
      expect(engine.carriedBox!.currentCount, 3);
      expect(eggShelf.currentStock, initialStock - 3);
    });

    test('Kasada kurye paketi yapilamaz ve kurye paketleme istasyonu ayri yerdedir', () {
      final engine = SimulationEngine();
      engine.courierState = CourierState.waitingForOrder;
      engine.activeCourierOrder = CourierOrder(
        id: 'ord_1',
        customerName: 'Test Kurye',
        productType: SimProductType.flour,
        requiredQty: 3,
        rewardAmount: 100,
        remainingTime: 50,
        totalTime: 50,
      );

      // Kurye paketleme istasyonu kasalarla cakismamali
      for (final c in engine.checkoutCounters) {
        expect(c.overlaps(engine.courierPackingDesk), isFalse);
      }

      // Elde un varken 1. kasaya yaklas
      engine.carriedBox = CarriedBox(
        productType: SimProductType.flour,
        currentCount: 3,
        maxCount: 10,
        isPickedFromShelf: true,
      );
      engine.playerX = engine.checkoutCounters.first.center.dx;
      engine.playerY = engine.checkoutCounters.first.bottom + 20;
      engine.update(0.016);

      // Kasada kurye paketi yapma aksiyonu olmamali
      expect(engine.activeInteractionAction, isNull);
      expect(engine.activeInteractionText, contains('No courier packages at the register'));
      expect(engine.carriedBox!.isCourierPackage, isFalse);
    });

    test('Inek ciftligi (Sut Kovasi), Un tarlasi (Capa) ve Tavuk ciftligi (Tavuk Kovasi) calisir', () {
      final engine = SimulationEngine();
      expect(engine.farmProducers.length, 3);

      final barn = engine.farmProducers.firstWhere((f) => f.zoneType == FarmZoneType.barn);
      final field = engine.farmProducers.firstWhere((f) => f.zoneType == FarmZoneType.field);
      final coop = engine.farmProducers.firstWhere((f) => f.zoneType == FarmZoneType.coop);

      expect(barn.name, 'İnek Çiftliği');
      expect(barn.requiredTool, FarmToolType.milkBucket);
      expect(barn.requiredTool.name, 'Süt Kovası');

      expect(field.name, 'Un Tarlası');
      expect(field.requiredTool, FarmToolType.scythe);
      expect(field.requiredTool.name, 'Çapa');

      expect(coop.name, 'Tavuk Çiftliği');
      expect(coop.requiredTool, FarmToolType.eggBucket);
      expect(coop.requiredTool.name, 'Tavuk Kovası');

      // Un tarlasina girince Capa eline alinir ve un hasat edilir
      final cropSpot = field.spots.first;
      engine.playerX = cropSpot.x;
      engine.playerY = cropSpot.y;
      engine.update(0.1);
      expect(engine.playerTool, FarmToolType.scythe);

      for (int i = 0; i < 15; i++) {
        engine.update(0.1);
      }
      expect(engine.carriedBox, isNotNull);
      expect(engine.carriedBox!.productType, SimProductType.flour);
      expect(engine.carriedBox!.isFromFarm, isTrue);
    });

    testWidgets('Fazla urunle paketlemeye gidince "Bu fazla!" uyarisi verir ve ona gore paket yapar',
        (WidgetTester tester) async {
      final engine = SimulationEngine();
      final eggShelf = engine.shelves.firstWhere((s) => s.assignedProduct == SimProductType.egg);
      eggShelf.currentStock = 10;

      engine.courierState = CourierState.waitingForOrder;
      engine.activeCourierOrder = CourierOrder(
        id: 'ord_2',
        customerName: 'Test Kurye',
        productType: SimProductType.egg,
        requiredQty: 3,
        rewardAmount: 66,
        remainingTime: 50,
        totalTime: 50,
      );

      // Elde 5 yumurta var (3 isteniyor -> 2 fazla)
      engine.carriedBox = CarriedBox(
        productType: SimProductType.egg,
        currentCount: 5,
        maxCount: 12,
        isPickedFromShelf: true,
      );
      engine.playerX = engine.courierPackingDesk.center.dx;
      engine.playerY = engine.courierPackingDesk.bottom + 20;
      engine.update(0.016);

      // Otomatik paketlenmemeli, fazla uyarisi vermeli
      expect(engine.carriedBox!.isCourierPackage, isFalse);
      expect(engine.activeInteractionText, contains('Too many'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CourierPackingDialog(engine: engine),
                ),
                child: const Text('Ac'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ac'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many!'), findsOneWidget);
      expect(find.textContaining('5 / 3'), findsOneWidget);

      // 2 fazla cikarilana kadar paketle butonu gorunmez
      expect(find.textContaining('Tape the package'), findsNothing);

      // 2 kere "-1" tikla
      await tester.tap(find.text('Remove 1'));
      await tester.pump();
      await tester.tap(find.text('Remove 1'));
      await tester.pump();

      expect(find.textContaining('3 / 3'), findsOneWidget);
      expect(find.textContaining('Tape the package'), findsOneWidget);

      await tester.tap(find.textContaining('Tape the package'));
      await tester.pumpAndSettle();

      // Tam 3 adetlik kurye paketi hazir olmali ve 2 fazla rafa donmus olmali
      expect(engine.carriedBox, isNotNull);
      expect(engine.carriedBox!.isCourierPackage, isTrue);
      expect(engine.carriedBox!.currentCount, 3);
      expect(eggShelf.currentStock, 12);
    });
  });
}
