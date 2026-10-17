import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/utils/number_formatter.dart';

/// Diagnostika — narxi qat'iy tez buyurtma.
///
/// Oddiy tez buyurtmadan (create_request_page) farqi: tur va narx tanlanmaydi.
/// Narxni SERVER qo'yadi (GET /requests/diagnostika) va buyurtma yaratilganda
/// o'sha summani muzlatadi; ilova narx yubormaydi. Ekranda faqat joy, sana va
/// vaqt. Mablag' yetmasa — hisobni to'ldirishga taklif (katalogdagi kabi).
class DiagnostikaPage extends StatefulWidget {
  const DiagnostikaPage({super.key});

  @override
  State<DiagnostikaPage> createState() => _DiagnostikaPageState();
}

class _DiagnostikaPageState extends State<DiagnostikaPage> {
  final EquipmentRequestService _service = EquipmentRequestService();
  final BalanceService _balanceService = BalanceService();
  final _addressController = TextEditingController();

  double? _price;
  bool _priceFailed = false;
  DateTime? _date;
  TimeOfDay? _time;
  double? _lat;
  double? _lon;
  bool _isLocating = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadPrice();
    _detectLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadPrice() async {
    setState(() => _priceFailed = false);
    try {
      final price = await _service.getDiagnostikaPrice();
      if (mounted) setState(() => _price = price);
    } catch (_) {
      if (mounted) setState(() => _priceFailed = true);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lon = position.longitude;
        _isLocating = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _date ?? DateTime(now.year, now.month, now.day),
      locale: context.locale,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.primaryGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: AppColors.primaryGreen),
          ),
          child: child!,
        ),
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  String get _timeText =>
      '${_time!.hour.toString().padLeft(2, '0')}:'
      '${_time!.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_price == null) {
      _snack('requests.diag_price_error'.tr());
      return;
    }
    if (_date == null) {
      _snack('requests.diag_choose_date'.tr());
      return;
    }
    if (_time == null) {
      _snack('requests.quick_time_required'.tr());
      return;
    }
    if (_lat == null || _lon == null) {
      _snack('errors.location_not_available'.tr());
      return;
    }

    setState(() => _isSending = true);

    // Mablag'ni oldindan tekshiramiz — yetmasa to'ldirishni taklif qilamiz.
    // Server baribir o'zi tekshiradi (va muzlatadi), bu faqat qulaylik.
    try {
      final balance = await _balanceService.getBalance();
      if (!mounted) return;
      if (balance.availableBalance < _price!) {
        setState(() => _isSending = false);
        _showInsufficientBalanceDialog(balance.availableBalance, _price!);
        return;
      }
    } catch (_) {
      // Balansni olib bo'lmadi — server o'zi javob beradi
    }

    try {
      await _service.createDiagnostika(
        date: _date!,
        startTime: '$_timeText:00',
        latitude: _lat!,
        longitude: _lon!,
        address: _addressController.text.trim(),
      );
      if (!mounted) return;
      _snack('requests.diag_created'.tr());
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      String? detail;
      try {
        final data = (e as dynamic).response?.data;
        if (data is Map && data['detail'] is String) detail = data['detail'] as String;
      } catch (_) {}
      _snack(detail ?? 'errors.something_went_wrong'.tr());
    }
  }

  void _showInsufficientBalanceDialog(double available, double required) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('messages.insufficient_balance'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'messages.available_balance'.tr()}: '
                '${NumberFormatter.formatCurrency(available)} ${'common.currency'.tr()}'),
            Text('${'messages.required_amount'.tr()}: '
                '${NumberFormatter.formatCurrency(required)} ${'common.currency'.tr()}'),
            const SizedBox(height: 8),
            Text('messages.topup_to_continue'.tr(),
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/balance-topup', extra: required - available);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen),
            child: Text('balance.topup_button'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
          'requests.diag_title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _priceCard(),
          const SizedBox(height: 12),
          _card(
            title: 'rent.delivery_place'.tr(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _lat == null ? Icons.place_outlined : Icons.place,
                      size: 18,
                      color: _lat == null
                          ? AppColors.grey
                          : AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lat == null
                            ? 'messages.detecting_location'.tr()
                            : '${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: _lat == null ? Colors.grey[600] : AppColors.black,
                        ),
                      ),
                    ),
                    if (_isLocating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.my_location, size: 20),
                        color: AppColors.primaryGreen,
                        onPressed: _detectLocation,
                      ),
                  ],
                ),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    hintText: 'equipment.address'.tr(),
                    border: const UnderlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'requests.diag_date'.tr(),
            child: _pickerRow(
              icon: Icons.calendar_today,
              text: _date == null
                  ? 'requests.diag_choose_date'.tr()
                  : DateFormat('dd.MM.yyyy').format(_date!),
              empty: _date == null,
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'requests.start_time'.tr(),
            child: _pickerRow(
              icon: Icons.schedule,
              text: _time == null ? 'requests.choose_time'.tr() : _timeText,
              empty: _time == null,
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSending || _price == null ? null : _submit,
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
                  : Text('requests.diag_order'.tr(),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _priceCard() {
    return _card(
      title: 'requests.diag_subtitle'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (_price != null)
            Text(
              'requests.diag_price'
                  .tr(args: [NumberFormatter.formatCurrency(_price)]),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            )
          else if (_priceFailed)
            InkWell(
              onTap: _loadPrice,
              child: Row(
                children: [
                  Expanded(
                    child: Text('requests.diag_price_error'.tr(),
                        style: const TextStyle(color: Colors.red)),
                  ),
                  const Icon(Icons.refresh, color: AppColors.primaryGreen),
                ],
              ),
            )
          else
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(height: 6),
          Text('requests.diag_price_hint'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _pickerRow({
    required IconData icon,
    required String text,
    required bool empty,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.grey),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: empty ? Colors.grey[600] : AppColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
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
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
