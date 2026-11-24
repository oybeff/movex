import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/driver_card_model.dart';
import 'driver_add_card_page.dart';
import 'driver_ui.dart';
import '../../../core/widgets/h_icon.dart';

/// Макет 04 C6 & C7: «Kartalarim» va karta sozlamalari / o'chirish.
class DriverCardsPage extends StatefulWidget {
  const DriverCardsPage({super.key});

  @override
  State<DriverCardsPage> createState() => _DriverCardsPageState();
}

class _DriverCardsPageState extends State<DriverCardsPage> {
  List<DriverPayoutCard> _cards = [];
  bool _loading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await AuthService().getUserId();
      if (me != null) {
        _userId = me.toString();
        final cards = await DriverCardsRepository.getCards(_userId!);
        if (mounted) setState(() => _cards = cards);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onAdd() async {
    final res = await Navigator.of(context).push<DriverPayoutCard>(
      MaterialPageRoute(builder: (_) => const DriverAddCardPage()),
    );
    if (res != null) _load();
  }

  void _showCardSheet(DriverPayoutCard card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppPalette.brandSubtle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      card.typeName.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppPalette.brand),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.shortMasked, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text("Muddati: ${card.expiry}", style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                    ],
                  ),
                ),
                if (card.isDefault)
                  const DChip("Asosiy", bg: Color(0xFFDCFCE7), fg: Color(0xFF16A34A)),
              ],
            ),
            const SizedBox(height: 20),
            if (!card.isDefault) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const HIcon(Icons.star_outline_rounded, color: AppPalette.brand),
                title: const Text("Asosiy karta qilish", style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (_userId != null) {
                    await DriverCardsRepository.setDefault(_userId!, card.id);
                    _load();
                  }
                },
              ),
              const Divider(height: 1),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const HIcon(Icons.delete_outline_rounded, color: AppPalette.textDanger),
              title: const Text("Kartani o'chirish", style: TextStyle(color: AppPalette.textDanger, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text("Kartani o'chirish"),
                    content: Text("${card.shortMasked} kartasini ro'yxatdan o'chirmoqchimisiz?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text('common.cancel'.tr())),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        style: TextButton.styleFrom(foregroundColor: AppPalette.textDanger),
                        child: Text('driver.card_delete'.tr()),
                      ),
                    ],
                  ),
                );
                if (ok == true && _userId != null) {
                  await DriverCardsRepository.deleteCard(_userId!, card.id);
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const HIcon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Kartalarim", style: AppTypography.h3),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_cards.isEmpty) ...[
                    const SizedBox(height: 60),
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(color: AppPalette.brandSubtle, shape: BoxShape.circle),
                        child: const HIcon(Icons.credit_card_off_outlined, size: 36, color: AppPalette.brand),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text('driver.cards_empty'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        "Pul yechish uchun avval Uzcard yoki Humo kartangizni qo'shing",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppPalette.textSecondary),
                      ),
                    ),
                  ] else ...[
                    for (final c in _cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: AppPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showCardSheet(c),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: c.type == DriverCardType.humo
                                          ? const Color(0xFFE6F4EA)
                                          : const Color(0xFFEBF2FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        c.typeName.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: c.type == DriverCardType.humo
                                              ? const Color(0xFF0F766E)
                                              : AppPalette.brand,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.shortMasked, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text("Muddati: ${c.expiry}", style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  if (c.isDefault)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: DChip("Asosiy", bg: Color(0xFFDCFCE7), fg: Color(0xFF16A34A)),
                                    ),
                                  const HIcon(Icons.more_vert, color: AppPalette.textSecondary),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  DSecondary("+ Yangi karta qo'shish", onPressed: _onAdd, tinted: true),
                ],
              ),
      ),
    );
  }
}
