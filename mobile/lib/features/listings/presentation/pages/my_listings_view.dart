import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/listing_model.dart';
import '../../../../core/services/listing_service.dart';
import '../widgets/listing_card.dart';

/// O'z e'lonlari — muallif tomoni.
///
/// ROLGA BOG'LIQ EMAS: mijoz ham, ega ham e'lon joylay oladi, shuning uchun
/// bu ro'yxat ikkalasida ham bor.
///
/// Asosiy amal shu yerda — kimdir e'lonni olganda muallif uni TASDIQLASHI
/// kerak. Shuning uchun olingan e'lonlar tepaga chiqadi: aks holda o'nta
/// eski e'lon orasida ko'rinmay qolardi va ijrochi javob kutib o'tirardi.
///
/// Bu Scaffold EMAS: ekranni ListingsPage tutadi, bu yerda faqat tanasi.
class MyListingsView extends StatefulWidget {
  const MyListingsView({super.key});

  @override
  State<MyListingsView> createState() => MyListingsViewState();
}

class MyListingsViewState extends State<MyListingsView> {
  final ListingService _service = ListingService();

  List<ListingModel> _items = [];
  List<ListingModel> _posted = [];   // o'zi joylagani — muallif tomoni
  List<ListingModel> _taken = [];    // o'zi javob bergani — ijrochi tomoni
  bool _isLoading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getMine();
      if (!mounted) return;
      setState(() {
        // Javob kutayotganlari birinchi, keyin qolgani yangiligi bo'yicha.
        items.sort((a, b) {
          final byWaiting = (b.isTaken ? 1 : 0) - (a.isTaken ? 1 : 0);
          if (byWaiting != 0) return byWaiting;
          return b.createdAt.compareTo(a.createdAt);
        });
        // Ikki bo'lim: o'zi joylagani va o'zi javob bergani. Server endi
        // ikkalasini ham qaytaradi — ilgari javob berganini ro'yxat bo'lib
        // ko'radigan joy umuman yo'q edi, u faqat taxtada begonalar orasida
        // ko'rinardi.
        _posted = items.where((e) => !e.takenByMe).toList();
        _taken = items.where((e) => e.takenByMe).toList();
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _act(
    ListingModel listing,
    Future<ListingModel> Function(int id) action,
    String successKey, {
    String? confirmKey,
  }) async {
    if (confirmKey != null) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(confirmKey.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.no'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('common.yes'.tr()),
            ),
          ],
        ),
      );
      if (agreed != true) return;
    }

    setState(() => _busyId = listing.id);
    try {
      await action(listing.id);
      if (!mounted) return;
      _snack(successKey.tr());
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String? _detail(Object e) {
    try {
      final data = (e as dynamic).response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    } catch (_) {}
    return null;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Tashqaridan yangilash — e'lon joylangandan keyin ListingsPage chaqiradi.
  Future<void> reload() => _load();

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen))
        : RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: _load,
            child: _items.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      // Sarlavhalar faqat ikkala bo'lim ham bo'lganda: bitta
                      // ro'yxat ustida "Men joylashtirdim" ortiqcha shovqin.
                      if (_taken.isNotEmpty && _posted.isNotEmpty)
                        _sectionTitle('listings.section_posted'.tr()),
                      for (final listing in _posted) _card(listing),
                      if (_taken.isNotEmpty && _posted.isNotEmpty)
                        _sectionTitle('listings.section_taken'.tr()),
                      for (final listing in _taken) _card(listing),
                    ],
                  ),
          );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _card(ListingModel listing) {
    final busy = _busyId == listing.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kimdir olgan bo'lsa — bu muallif uchun eng muhim xabar, uni
        // kartochkadan yuqorida, alohida ko'rsatamiz. Ijrochiga esa aksincha:
        // u kutayotgan tomon, unga "tasdiqlang" deyish noto'g'ri.
        if (listing.isTaken && !listing.takenByMe)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.pan_tool_alt_outlined,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'listings.waiting_your_confirm'.tr(),
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ListingCard(
          listing: listing,
          actions: busy
              ? [
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primaryGreen),
                    ),
                  )
                ]
              : _actionsFor(listing),
        ),
      ],
    );
  }

  List<Widget> _actionsFor(ListingModel listing) {
    // --- ijrochi tomoni: e'lonni O'ZI olgan ---
    if (listing.takenByMe) {
      // Olindi, lekin muallif hali tasdiqlagani yo'q: telefon yopiq,
      // qiladigan ish yo'q — shuni ochiq aytamiz.
      if (listing.isTaken) {
        return [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'listings.waiting_client_confirm'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ];
      }
      if (listing.isConfirmed) {
        return [
          ElevatedButton(
            onPressed: () => _act(listing, _service.finish, 'listings.finished',
                confirmKey: 'listings.finish_confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('listings.finish'.tr(),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ];
      }
      return const [];
    }

    // --- muallif tomoni ---
    if (listing.isTaken) {
      return [
        OutlinedButton(
          onPressed: () => _act(listing, _service.reject, 'listings.rejected',
              confirmKey: 'listings.reject_confirm'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.black,
            side: const BorderSide(color: Colors.black26),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('listings.reject'.tr(),
              style: const TextStyle(fontSize: 13)),
        ),
        ElevatedButton(
          onPressed: () =>
              _act(listing, _service.confirm, 'listings.confirmed'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('listings.confirm'.tr(),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ];
    }

    if (listing.isConfirmed) {
      return [
        ElevatedButton(
          onPressed: () => _act(listing, _service.finish, 'listings.finished',
              confirmKey: 'listings.finish_confirm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('listings.finish'.tr(),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ];
    }

    if (listing.isOpen) {
      return [
        OutlinedButton(
          onPressed: () => _act(listing, _service.cancel, 'listings.cancelled',
              confirmKey: 'listings.cancel_confirm'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: Colors.black26),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('listings.cancel'.tr(),
              style: const TextStyle(fontSize: 13)),
        ),
      ];
    }

    return const [];
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text('listings.my_empty'.tr(),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'listings.my_empty_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
