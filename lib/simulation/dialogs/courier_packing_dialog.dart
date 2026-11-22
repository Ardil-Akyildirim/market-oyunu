import 'dart:math';
import 'package:material_ui/material_ui.dart' hide Text;
import '../../widgets/pixel_ui.dart';
import '../simulation_engine.dart';
import '../simulation_models.dart';

/// {box} Kurye Siparişi Paketleme İstasyonu Penceresi
/// Kasadan tamamen ayrıdır. Fazla ürün getirilirse "Bu fazla!" uyarısı verir ve tam siparişe göre paketletir.
class CourierPackingDialog extends StatefulWidget {
  final SimulationEngine engine;

  const CourierPackingDialog({super.key, required this.engine});

  @override
  State<CourierPackingDialog> createState() => _CourierPackingDialogState();
}

class _CourierPackingDialogState extends State<CourierPackingDialog> {
  late int _trayCount;
  int _excessRemoved = 0;

  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    final order = engine.activeCourierOrder;
    final staged = (order != null && engine.courierStagedProduct == order.productType)
        ? engine.courierStagedCount
        : 0;
    final held = (order != null &&
            engine.carriedBox != null &&
            !engine.carriedBox!.isCourierPackage &&
            engine.carriedBox!.productType == order.productType)
        ? engine.carriedBox!.currentCount
        : 0;
    _trayCount = staged + held;
  }

  void _removeOneExcess() {
    if (_trayCount <= 0) return;
    setState(() {
      _trayCount--;
      _excessRemoved++;
    });
  }

  void _trimAllExcess(int needed) {
    if (_trayCount <= needed) return;
    setState(() {
      _excessRemoved += (_trayCount - needed);
      _trayCount = needed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final order = engine.activeCourierOrder;

    if (order == null) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('{box} There is no active courier order right now.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        ),
      );
    }

    final def = productCatalog[order.productType]!;
    final int needed = order.remainingQty;
    final int excess = (_trayCount - needed).clamp(0, 999);
    final int missing = (needed - _trayCount).clamp(0, 999);
    final bool isExact = _trayCount == needed && needed > 0;
    final bool hasExcess = excess > 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        width: min(500.0, MediaQuery.of(context).size.width - 24),
        decoration: pixelDeco(kParchment, bw: 4, shadow: 6),
        padding: EdgeInsets.all(MediaQuery.of(context).size.height < 500 ? 12 : 20),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: Colors.deepPurple.shade200),
                  ),
                  child: const Text('{box}', style: TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Courier Packing Station',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF2A221C)),
                      ),
                      Text(
                        '{bike} ${order.customerName} • Reward: +\$${order.rewardAmount.toStringAsFixed(0)} • ${order.remainingTime.toInt()}s',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade700),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: PixelIcon('x', size: 24, dark: true),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // İstenen vs Getirilen Özet Kartı
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4EBD3),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: const Color(0xFFE9DFC6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(def.ico, style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                def.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Courier Wants: $needed pcs',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: hasExcess
                          ? Colors.red.shade100
                          : (isExact ? Colors.green.shade100 : Colors.amber.shade100),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: hasExcess
                            ? Colors.red.shade400
                            : (isExact ? Colors.green.shade500 : Colors.amber.shade500),
                      ),
                    ),
                    child: Text(
                      '$_trayCount / $needed',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: hasExcess
                            ? Colors.red.shade900
                            : (isExact ? Colors.green.shade900 : Colors.amber.shade900),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Durum Uyarı Kutusu ("Bu fazla!" / "Tam!" / "Eksik!")
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasExcess
                    ? Colors.red.shade50
                    : (isExact ? Colors.green.shade50 : Colors.amber.shade50),
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: hasExcess
                      ? Colors.red.shade400
                      : (isExact ? Colors.green.shade400 : Colors.amber.shade400),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    hasExcess ? '{warn}' : (isExact ? '{check}' : '{info}'),
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasExcess
                          ? 'Too many! The courier wants $needed x ${def.ico}, you brought $_trayCount ($excess extra!). Remove the extras and pack accordingly!'
                          : (isExact
                              ? 'Exactly the courier order ($needed/$needed)! Now tape the package and take it to the bike.'
                              : (_trayCount == 0
                                  ? 'Each press takes 1 ${def.ico} ${def.name} from the cabinet; bring it to this table ($needed needed).'
                                  : 'There are $_trayCount here now. Grab $missing more ${def.ico} from the cabinet!')),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hasExcess
                            ? Colors.red.shade900
                            : (isExact ? Colors.green.shade900 : Colors.amber.shade900),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Paket Tepsisi Ürün Slotları
            Container(
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 84),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2431),
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: hasExcess ? Colors.redAccent : const Color(0xFFFACC15),
                  width: 2,
                ),
              ),
              child: _trayCount == 0
                  ? Center(
                      child: Text(
                        '{box} Courier Box Empty (0/$needed ${def.ico})',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: List.generate(_trayCount, (index) {
                        final isExtra = index >= needed;
                        return InkWell(
                          onTap: isExtra ? _removeOneExcess : null,
                          borderRadius: BorderRadius.zero,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isExtra ? Colors.red.shade700 : const Color(0xFF4C1D95),
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: isExtra ? Colors.redAccent.shade100 : const Color(0xFFFACC15),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(def.ico, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 4),
                                Text(
                                  isExtra ? 'EXTRA x' : '#${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
            ),

            const SizedBox(height: 14),

            // Alt Eylem Butonları
            if (hasExcess) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _removeOneExcess,
                      icon: PixelIcon('minus', size: 24, dark: true),
                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Remove 1', style: TextStyle(fontWeight: FontWeight.bold))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade400, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _trimAllExcess(needed),
                      icon: PixelIcon('x', size: 24, dark: true),
                      label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Set to $needed', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            if (isExact)
              ElevatedButton.icon(
                onPressed: () {
                  engine.sealCourierPackageFromDialog(
                    packCount: _trayCount,
                    excessReturned: _excessRemoved,
                  );
                  Navigator.pop(context);
                },
                icon: PixelIcon('box', size: 24),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Tape the package', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
                ),
              )
            else if (!hasExcess && _trayCount > 0)
              ElevatedButton.icon(
                onPressed: () {
                  engine.keepStagedAtPackingDeskFromDialog(
                    stageCount: _trayCount,
                    excessReturned: _excessRemoved,
                  );
                  Navigator.pop(context);
                },
                icon: PixelIcon('bag', size: 24),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Leave on table ($_trayCount/$needed)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
                ),
              )
            else if (!hasExcess)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A3C30),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Color(0xFF14100E), width: 3)),
                ),
                child: const Text('OK, Take Item from Cabinet', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
