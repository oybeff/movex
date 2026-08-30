import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/equipment_request_model.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import 'create_request_page.dart';
import 'request_detail_page.dart';

/// Mijozning zayavkalari.
class MyRequestsPage extends StatefulWidget {
  const MyRequestsPage({super.key});

  @override
  State<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends State<MyRequestsPage> {
  final EquipmentRequestService _service = EquipmentRequestService();

  List<EquipmentRequestModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getMyRequests();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRequestPage()),
    );
    if (created != null) _load();
  }

  Future<void> _open(EquipmentRequestModel request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailPage(requestId: request.id),
      ),
    );
    _load();
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
          'requests.my_requests'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('requests.find_equipment'.tr()),
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
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _items.length,
                      itemBuilder: (context, index) =>
                          _requestCard(_items[index]),
                    ),
            ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text('requests.empty'.tr(),
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
        ),
      ],
    );
  }

  Widget _requestCard(EquipmentRequestModel request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: InkWell(
        onTap: () => _open(request),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EquipmentTypeIcon(request.equipmentType, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(request.typeLabel,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('dd.MM.yyyy').format(request.startDate)} — '
                          '${DateFormat('dd.MM.yyyy').format(request.endDate)}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  _statusChip(request.status),
                ],
              ),
              if (request.deliveryAddress != null &&
                  request.deliveryAddress!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 15, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(request.deliveryAddress!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700])),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (request.budget != null) ...[
                    Icon(Icons.payments_outlined,
                        size: 15, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${NumberFormatter.formatCurrency(request.budget)} '
                      '${'common.currency'.tr()}',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (request.isOpen)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: request.offersCount > 0
                            ? AppColors.primaryGreen.withValues(alpha: 0.12)
                            : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'requests.offers_count'
                            .tr(args: ['${request.offersCount}']),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: request.offersCount > 0
                              ? AppColors.secondaryGreen
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final map = {
      'open': (AppColors.primaryGreen, 'requests.status_open'),
      'assigned': (AppColors.accentGreen, 'requests.status_assigned'),
      'cancelled': (AppColors.grey, 'requests.status_cancelled'),
      'expired': (AppColors.grey, 'requests.status_expired'),
    };
    final (color, key) = map[status] ?? (AppColors.grey, 'requests.status_open');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        key.tr(),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
