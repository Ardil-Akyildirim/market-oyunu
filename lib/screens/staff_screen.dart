import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../models/staff.dart';
import '../providers/game_provider.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Bilgi Kartı
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Row(
            children: [
              const Text('👥', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personel & Otomasyon Ekibi',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF4C1D95)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kasiyer müşterileri otomatik kasadan geçirir, çırak rafları doldurur! Sen arkana yaslan, marketin çalışsın.',
                      style: TextStyle(fontSize: 11, color: Colors.purple.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Personel Kartları
        ...game.staffList.map((staff) => _buildStaffCard(context, game, staff)),
      ],
    );
  }

  Widget _buildStaffCard(BuildContext context, GameProvider game, Staff staff) {
    final canHire = game.cash >= staff.hireCost;
    final canUpgrade = game.cash >= staff.upgradeCost;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: staff.isHired ? Colors.green.shade300 : Colors.grey.shade300,
          width: staff.isHired ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(staff.avatar, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              // İsim & Pozisyon
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          staff.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (staff.isHired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Çalışıyor ✅',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      staff.roleName,
                      style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              // Terfi / Seviye Yükseltme Butonu
              if (staff.isHired)
                OutlinedButton(
                  onPressed: canUpgrade ? () => game.upgradeStaff(staff) : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: canUpgrade ? Colors.purple.shade600 : Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Seviye ${staff.level + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(
                        '₺${staff.upgradeCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: canUpgrade ? Colors.purple.shade800 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            staff.description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),

          // Durum ve İşe Alım Butonu
          if (!staff.isHired)
            ElevatedButton(
              onPressed: canHire ? () => game.hireStaff(staff) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'İşe Al (₺${staff.hireCost.toStringAsFixed(0)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Aktif Seviye: ${staff.level} (Verimlilik: ${(staff.efficiency * 100).toInt()}%)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                  ),
                  const Text('⚡ Otomatik Aktif', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
