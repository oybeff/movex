import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/models/listing_model.dart';
import '../../../../core/services/listing_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../widgets/listing_card.dart';

/// Taxta: begonalarning ochiq e'lonlari.
///
/// ROLGA BOG'LIQ EMAS. Mijoz ham, ega ham bir xil taxtani ko'radi va
/// bir-birining e'loniga javob bera oladi: mijoz "gruzchik kerak" deb
/// yozadi, ega "ertaga ekskavator bo'sh" deb yozadi.
///
/// Zayavkalar lentasidan farqi — bu yerda savdo yo'q. "Olaman" bosiladi va
/// muallif tasdiqlashini kutiladi; kim birinchi bosgan bo'lsa, e'lon
/// o'shanga biriktiriladi (buni server hal qiladi, ikkinchisiga xato).
///
/// Bu Scaffold EMAS: ekranni ListingsPage tutadi, bu yerda faqat tanasi.
class ListingsFeedView extends StatefulWidget {
  const ListingsFeedView({super.key});

  @override
  State<ListingsFeedView> createState() => ListingsFeedViewState();
}

class ListingsFeedViewState extends State<ListingsFeedView> {
  final ListingService _service = ListingService();

  List<ListingModel> _items = [];
  String? _filterType;
  bool _isLoading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getFeed(equipmentType: _filterType);
      if (!mounted) return;
      setState(() {
        // O'zi olganlari tepada: ular bo'yicha javob kutilyapti.
        items.sort((a, b) {
          final byMine = (b.takenByMe ? 1 : 0) - (a.takenByMe ? 1 : 0);
          if (byMine != 0) return byMine;
          return b.createdAt.compareTo(a.createdAt);
        });
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _take(ListingModel listing) async {
    setState(() => _busyId = listing.id);
    try {
      await _service.take(listing.id);
      if (!mounted) return;
      _snack('listings.taken_wait_confirm'.tr());
      await _load();
    } catch (e) {
      if (!mounted) return;
      // Eng ehtimolli xato — kimdir tezroq bosgan. Server nima deganini
      // aynan ko'rsatamiz, o'zimizdan sabab o'ylab topmaymiz.
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Yurakcha va xatcho'p.
  ///
  /// Server javobida yangi sanoqlar keladi — ro'yxatni butunlay qayta
  /// yuklamasdan, faqat shu kartochka almashtiriladi: aks holda har bir
  /// bosishda ekran sakrab ketardi.
  Future<void> _toggleMark(ListingModel listing, {required bool like}) async {
    try {
      final updated = like
          ? await _service.setLike(listing.id, !listing.likedByMe)
          : await _service.setSaved(listing.id, !listing.savedByMe);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((x) => x.id == listing.id);
        if (index != -1) _items[index] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
    }
  }

  /// Narx taklif qilish. "Olaman" dan farqi shundaki, bu yerda ijrochi
  /// O'Z summasini aytadi, muallif esa kelganlaridan birini tanlaydi.
  Future<void> _offerPrice(ListingModel listing) async {
    final controller = TextEditingController(
      text: listing.budget != null ? listing.budget!.round().toString() : '',
    );
    final commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('listings.offer_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (listing.budget != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${'listings.budget'.tr()}: '
                  '${NumberFormatter.formatCurrency(listing.budget)} '
                  '${'common.currency'.tr()}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'listings.offer_price'.tr(),
                suffixText: 'common.currency'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commentController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'listings.offer_comment'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text('listings.offer_send'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final price = double.tryParse(controller.text.replaceAll(' ', ''));
    if (price == null || price <= 0) {
      _snack('listings.offer_price_invalid'.tr());
      return;
    }

    setState(() => _busyId = listing.id);
    try {
      await _service.makeOffer(listing.id,
          price: price, comment: commentController.text.trim());
      if (!mounted) return;
      _snack('listings.offer_sent'.tr());
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _finish(ListingModel listing) async {
    setState(() => _busyId = listing.id);
    try {
      await _service.finish(listing.id);
      if (!mounted) return;
      _snack('listings.finished'.tr());
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _buildRoute(ListingModel listing) async {
    final uri = Uri.parse('https://yandex.ru/maps/?rtext=~'
        '${listing.latitude},${listing.longitude}&rtt=auto');
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) _snack('errors.no_maps_available'.tr());
    } catch (_) {
      if (mounted) _snack('errors.cannot_open_map'.tr());
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack('errors.something_went_wrong'.tr());
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
    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryGreen))
              : RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? _empty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _items.length,
                          itemBuilder: (context, i) => _card(_items[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
            child: ChoiceChip(
              selected: _filterType == null,
              onSelected: (_) {
                setState(() {
                  _filterType = null;
                  _isLoading = true;
                });
                _load();
              },
              label: Text('common.all'.tr(),
                  style: const TextStyle(fontSize: 12)),
              selectedColor: AppColors.primaryGreen.withValues(alpha: 0.18),
              backgroundColor: AppColors.white,
              side: BorderSide(
                color: _filterType == null
                    ? AppColors.primaryGreen
                    : Colors.black12,
              ),
            ),
          ),
          for (final code in EquipmentTypes.codes)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: ChoiceChip(
                selected: _filterType == code,
                onSelected: (selected) {
                  setState(() {
                    _filterType = selected ? code : null;
                    _isLoading = true;
                  });
                  _load();
                },
                avatar: EquipmentTypeIcon(code, size: 18),
                label: Text(EquipmentTypes.label(code),
                    style: const TextStyle(fontSize: 12)),
                selectedColor: AppColors.primaryGreen.withValues(alpha: 0.18),
                backgroundColor: AppColors.white,
                side: BorderSide(
                  color: _filterType == code
                      ? AppColors.primaryGreen
                      : Colors.black12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(ListingModel listing) {
    final busy = _busyId == listing.id;

    return ListingCard(
      listing: listing,
      onToggleLike: () => _toggleMark(listing, like: true),
      onToggleSave: () => _toggleMark(listing, like: false),
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
    );
  }

  List<Widget> _actionsFor(ListingModel listing) {
    final route = listing.latitude != null && listing.longitude != null
        ? OutlinedButton.icon(
            onPressed: () => _buildRoute(listing),
            icon: const Icon(Icons.directions, size: 18),
            label: Text('orders.build_route'.tr(),
                style: const TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.black,
              side: const BorderSide(color: Colors.black26),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          )
        : null;

    if (listing.isOpen) {
      // Ikkala yo'l ham ochiq: "olaman" — muallif byudjetiga rozilik,
      // "narx taklif qilaman" — o'z summasi. Byudjet ko'rsatilmagan
      // e'lonlar ko'p, shuning uchun bittasi yetmaydi.
      return [
        if (route != null) route,
        OutlinedButton(
          onPressed: () => _offerPrice(listing),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryGreen,
            side: const BorderSide(color: AppColors.primaryGreen),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            listing.offeredByMe
                ? 'listings.offer_change'.tr()
                : 'listings.offer_button'.tr(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: () => _take(listing),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('listings.take'.tr(),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ];
    }

    // Olingan, lekin hali tasdiqlanmagan: telefon HALI ochilmagan — buni
    // aytib qo'yamiz, aks holda ega nimani kutayotganini bilmaydi.
    if (listing.isTaken && listing.takenByMe) {
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

    if (listing.isConfirmed && listing.takenByMe) {
      return [
        if (listing.hasPhone)
          OutlinedButton.icon(
            onPressed: () => _call(listing.contactPhone!),
            icon: const Icon(Icons.phone, size: 18),
            label: Text('common.call'.tr(),
                style: const TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ElevatedButton(
          onPressed: () => _finish(listing),
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

    return [if (route != null) route];
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text('listings.feed_empty'.tr(),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            _filterType == null
                ? 'listings.feed_hint'.tr()
                : 'listings.feed_hint_filtered'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
