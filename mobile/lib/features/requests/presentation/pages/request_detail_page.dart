import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/equipment_request_model.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

/// Zayavka va unga kelgan takliflar. Mijoz shu yerdan bittasini tanlaydi.
///
/// Taklifdagi summa TAXMINIY: unda komissiya va yetkazib berish yo'q.
/// Yakuniy summani server buyurtma yaratilganda hisoblaydi, shuning uchun
/// ekranda buni ochiq yozamiz — foydalanuvchi keyin boshqa raqam ko'rib
/// hayron bo'lmasligi kerak.
class RequestDetailPage extends StatefulWidget {
  const RequestDetailPage({super.key, required this.requestId});

  final int requestId;

  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage> {
  final EquipmentRequestService _service = EquipmentRequestService();

  EquipmentRequestModel? _request;
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final request = await _service.getRequest(widget.requestId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('errors.something_went_wrong'.tr());
    }
  }

  Future<void> _accept(RequestOfferModel offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('requests.accept_offer'.tr()),
        content: Text('requests.accept_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await _service.acceptOffer(widget.requestId, offer.id);
      if (!mounted) return;
      _snack('requests.accepted'.tr());
      await _load();
      if (mounted) setState(() => _isBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      // Eng ehtimolli sabab — balansda mablag' yetmasligi. Serverning
      // xabarini ko'rsatamiz, u aniqroq.
      _snack(_serverMessage(e) ?? 'errors.something_went_wrong'.tr());
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('requests.cancel'.tr()),
        content: Text('requests.cancel_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.no'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.yes'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await _service.cancelRequest(widget.requestId);
      if (!mounted) return;
      _snack('requests.cancelled'.tr());
      await _load();
      if (mounted) setState(() => _isBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _snack(_serverMessage(e) ?? 'errors.something_went_wrong'.tr());
    }
  }

  String? _serverMessage(Object error) {
    try {
      final data = (error as dynamic).response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    } catch (_) {}
    return null;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          '${'requests.title'.tr()} #${widget.requestId}',
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (request != null && request.isOpen)
            IconButton(
              tooltip: 'requests.cancel'.tr(),
              icon: const Icon(Icons.close, color: AppColors.error),
              onPressed: _isBusy ? null : _cancel,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : request == null
              ? Center(child: Text('errors.something_went_wrong'.tr()))
              : RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summary(request),
                      const SizedBox(height: 20),
                      Text('requests.offers'.tr(),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (request.offers.isEmpty)
                        _noOffers()
                      else
                        ...request.offers
                            .map((offer) => _offerCard(request, offer)),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _summary(EquipmentRequestModel request) {
    return Container(
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
              EquipmentTypeIcon(request.equipmentType, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.typeLabel,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
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
            ],
          ),
          if (request.deliveryAddress != null &&
              request.deliveryAddress!.isNotEmpty) ...[
            const Divider(height: 24),
            _row(Icons.place_outlined, 'orders.delivery_location'.tr(),
                request.deliveryAddress!),
          ],
          if (request.budget != null) ...[
            const Divider(height: 24),
            _row(
              Icons.payments_outlined,
              'requests.budget'.tr(),
              '${NumberFormatter.formatCurrency(request.budget)} '
                  '${'common.currency'.tr()}',
            ),
          ],
          if (request.comment != null && request.comment!.isNotEmpty) ...[
            const Divider(height: 24),
            _row(Icons.notes_outlined, 'requests.comment'.tr(),
                request.comment!),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noOffers() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('requests.no_offers'.tr(),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'requests.no_offers_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _offerCard(EquipmentRequestModel request, RequestOfferModel offer) {
    final isAccepted = offer.status == 'accepted';
    final canAccept = request.isOpen && offer.isPending && !_isBusy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccepted ? AppColors.primaryGreen : Colors.black12,
          width: isAccepted ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EquipmentTypeIcon(offer.equipmentType, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.equipmentLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (offer.ownerName != null)
                      Text(offer.ownerName!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (isAccepted)
                const Icon(Icons.check_circle,
                    color: AppColors.primaryGreen, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormatter.formatCurrency(offer.pricePerDay),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${'common.currency'.tr()}/${'common.day'.tr()}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          if (offer.estimatedSubtotal != null) ...[
            const SizedBox(height: 4),
            Text(
              'requests.estimated'.tr(args: [
                '${NumberFormatter.formatCurrency(offer.estimatedSubtotal)} '
                    '${'common.currency'.tr()}'
              ]),
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 2),
            Text(
              'requests.estimate_note'.tr(),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
          if (offer.comment != null && offer.comment!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(offer.comment!,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ],
          if (canAccept) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _accept(offer),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('requests.accept_offer'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
