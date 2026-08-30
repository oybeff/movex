import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/models/equipment_request_model.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import 'search_area_page.dart';

/// Egaga: yaqin atrofdagi ochiq zayavkalar.
///
/// Ro'yxatni server radius va texnika turi bo'yicha filtrlaydi. Bo'sh
/// bo'lsa sababini aytamiz — "hech narsa yo'q" degan ekran foydalanuvchini
/// sozlamalarga olib bormaydi.
class RequestsFeedPage extends StatefulWidget {
  const RequestsFeedPage({super.key});

  @override
  State<RequestsFeedPage> createState() => _RequestsFeedPageState();
}

class _RequestsFeedPageState extends State<RequestsFeedPage> {
  final EquipmentRequestService _service = EquipmentRequestService();
  final EquipmentService _equipmentService = EquipmentService();

  List<EquipmentRequestModel> _items = [];
  List<EquipmentModel> _myEquipment = [];
  SearchAreaModel? _area;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getFeed(),
        _service.getSearchArea(),
        _equipmentService.getEquipmentList(ownerOnly: true, limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<EquipmentRequestModel>;
        _area = results[1] as SearchAreaModel;
        _myEquipment = results[2] as List<EquipmentModel>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openArea() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchAreaPage(isOwner: true)),
    );
    _load();
  }

  /// Navigator ilovasini ochadi. Xarita ilovasi yo'q bo'lsa aytamiz.
  Future<void> _buildRoute(EquipmentRequestModel request) async {
    final uri = Uri.parse(
      'https://yandex.ru/maps/?rtext=~'
      '${request.deliveryLatitude},${request.deliveryLongitude}&rtt=auto',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) _snack('errors.no_maps_available'.tr());
    } catch (_) {
      if (mounted) _snack('errors.cannot_open_map'.tr());
    }
  }

  Future<void> _makeOffer(EquipmentRequestModel request) async {
    // Faqat turi mos keladigan texnika — server ham shuni tekshiradi,
    // lekin foydalanuvchiga mos kelmaydiganini ko'rsatishning ma'nosi yo'q.
    final suitable = _myEquipment
        .where((e) => e.type == request.equipmentType)
        .toList();

    if (suitable.isEmpty) {
      _snack('equipment.none_found'.tr());
      return;
    }

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OfferSheet(
        request: request,
        equipment: suitable,
        service: _service,
      ),
    );
    if (sent == true) {
      _snack('requests.offer_sent'.tr());
      _load();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'requests.feed'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'area.title'.tr(),
            icon: const Icon(Icons.tune),
            onPressed: _openArea,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _load,
              child: _items.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _areaBanner();
                        return _requestCard(_items[index - 1]);
                      },
                    ),
            ),
    );
  }

  Widget _areaBanner() {
    final area = _area;
    if (area == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.radar, size: 18, color: AppColors.secondaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              area.hasPoint
                  ? '${'area.title'.tr()}: ${area.radiusKm} ${'common.km'.tr()}'
                  : 'area.point_not_set'.tr(),
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryGreen,
                  fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: _openArea,
            child: Text('common.edit'.tr(),
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.radar, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text('requests.feed_empty'.tr(),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'requests.feed_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: _openArea,
            icon: const Icon(Icons.tune, size: 18),
            label: Text('area.title'.tr()),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _requestCard(EquipmentRequestModel request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EquipmentTypeIcon(request.equipmentType, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.typeLabel,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      '${DateFormat('dd.MM.yyyy').format(request.startDate)} — '
                      '${DateFormat('dd.MM.yyyy').format(request.endDate)}'
                      '  (${'rent.days_count'.plural(request.rentalDays)})',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (request.distanceKm != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'requests.distance_away'.tr(
                        args: [request.distanceKm!.toStringAsFixed(0)]),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[800]),
                  ),
                ),
            ],
          ),
          if (request.deliveryAddress != null &&
              request.deliveryAddress!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 15, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(request.deliveryAddress!,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[700])),
                ),
              ],
            ),
          ],
          if (request.budget != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.payments_outlined,
                    size: 15, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${'requests.client_budget'.tr()}: '
                  '${NumberFormatter.formatCurrency(request.budget)} '
                  '${'common.currency'.tr()}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
          if (request.comment != null && request.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.comment!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _buildRoute(request),
                  icon: const Icon(Icons.directions, size: 18),
                  label: Text('orders.build_route'.tr(),
                      style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.black,
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _makeOffer(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('requests.make_offer'.tr(),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Taklif yuborish oynasi: qaysi mashina va qancha narxga.
class _OfferSheet extends StatefulWidget {
  const _OfferSheet({
    required this.request,
    required this.equipment,
    required this.service,
  });

  final EquipmentRequestModel request;
  final List<EquipmentModel> equipment;
  final EquipmentRequestService service;

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late EquipmentModel _selected = widget.equipment.first;
  late final TextEditingController _price = TextEditingController(
    // Katalogdagi stavkani oldindan qo'yamiz — ko'p hollarda o'sha qoladi
    text: _selected.pricePerDayValue.toStringAsFixed(0),
  );
  final TextEditingController _comment = TextEditingController();
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final price = double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (price == null || price <= 0) {
      setState(() => _error = 'errors.price_positive'.tr());
      return;
    }
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.service.createOffer(
        requestId: widget.request.id,
        equipmentId: _selected.id,
        pricePerDay: price,
        comment: _comment.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      String? detail;
      try {
        final data = (e as dynamic).response?.data;
        if (data is Map && data['detail'] is String) {
          detail = data['detail'] as String;
        }
      } catch (_) {}
      setState(() {
        _isSending = false;
        _error = detail ?? 'errors.something_went_wrong'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.request.rentalDays;
    final price =
        double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('requests.make_offer'.tr(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('requests.select_equipment'.tr(),
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 6),
            DropdownButtonFormField<EquipmentModel>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: widget.equipment
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Row(
                          children: [
                            EquipmentTypeIcon(e.type, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.model,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selected = value;
                  _price.text = value.pricePerDayValue.toStringAsFixed(0);
                });
              },
            ),
            const SizedBox(height: 16),
            Text('requests.offer_price'.tr(),
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText:
                    '${'common.currency'.tr()}/${'common.day'.tr()}',
                border: const UnderlineInputBorder(),
              ),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (price > 0) ...[
              const SizedBox(height: 8),
              Text(
                'requests.estimated'.tr(args: [
                  '${NumberFormatter.formatCurrency(price * days)} '
                      '${'common.currency'.tr()}'
                ]),
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              Text('requests.estimate_note'.tr(),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'requests.comment'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('common.submit'.tr(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
