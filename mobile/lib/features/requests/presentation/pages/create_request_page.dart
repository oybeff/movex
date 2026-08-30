import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

/// Zayavka berish: mijoz ANIQ mashinani emas, TURNI so'raydi.
///
/// Katalogdan farqi shu. Bu yerda narx yo'q va bo'lmasligi ham kerak:
/// byudjet — mijozning mo'ljali, haqiqiy summa esa taklif tanlangandan
/// keyin serverda hisoblanadi. Shuning uchun bu ekranda hech qanday
/// hisob-kitob ko'rsatilmaydi — aks holda foydalanuvchi keyin boshqa raqam
/// ko'rib chalg'ib qolardi.
class CreateRequestPage extends StatefulWidget {
  const CreateRequestPage({super.key, this.initialType});

  /// Katalogdan "shunday texnika kerak" bilan kelinsa — oldindan tanlangan tur
  final String? initialType;

  @override
  State<CreateRequestPage> createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends State<CreateRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final EquipmentRequestService _service = EquipmentRequestService();

  final _budgetController = TextEditingController();
  final _commentController = TextEditingController();
  final _addressController = TextEditingController();

  String? _type;
  DateTimeRange? _dates;
  double? _lat;
  double? _lon;

  bool _isSending = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _detectLocation();
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _commentController.dispose();
    _addressController.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() => _isLocating = false);
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dates,
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
    if (picked != null) setState(() => _dates = picked);
  }

  Future<void> _pickType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('equipment.type'.tr(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: EquipmentTypes.codes.length,
                itemBuilder: (context, index) {
                  final code = EquipmentTypes.codes[index];
                  return ListTile(
                    leading: EquipmentTypeIcon(code, size: 32),
                    title: Text(EquipmentTypes.label(code)),
                    trailing: _type == code
                        ? const Icon(Icons.check_circle,
                            color: AppColors.primaryGreen)
                        : null,
                    onTap: () => Navigator.pop(context, code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _type = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == null) {
      _snack('equipment.type'.tr());
      return;
    }
    if (_dates == null) {
      _snack('rent.select_dates'.tr());
      return;
    }
    if (_lat == null || _lon == null) {
      _snack('errors.location_not_available'.tr());
      return;
    }

    setState(() => _isSending = true);
    try {
      final request = await _service.createRequest(
        equipmentType: _type!,
        startDate: _dates!.start,
        endDate: _dates!.end,
        latitude: _lat!,
        longitude: _lon!,
        address: _addressController.text.trim(),
        budget: double.tryParse(
            _budgetController.text.replaceAll(RegExp(r'[^0-9]'), '')),
        comment: _commentController.text.trim(),
      );
      if (!mounted) return;
      _snack('requests.created'.tr());
      Navigator.of(context).pop(request);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _snack('errors.something_went_wrong'.tr());
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
          'requests.new_request'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              title: 'equipment.type'.tr(),
              child: InkWell(
                onTap: _pickType,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      if (_type != null) ...[
                        EquipmentTypeIcon(_type, size: 34),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          _type == null
                              ? 'common.choose'.tr()
                              : EquipmentTypes.label(_type),
                          style: TextStyle(
                            fontSize: 16,
                            color: _type == null
                                ? Colors.grey[600]
                                : AppColors.black,
                            fontWeight: _type == null
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              title: 'rent.rental_period'.tr(),
              child: InkWell(
                onTap: _pickDates,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: AppColors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dates == null
                              ? 'rent.select_dates'.tr()
                              : '${DateFormat('dd.MM.yyyy').format(_dates!.start)} — '
                                  '${DateFormat('dd.MM.yyyy').format(_dates!.end)}'
                                  '  (${'rent.days_count'.plural(_dates!.duration.inDays + 1)})',
                          style: TextStyle(
                            fontSize: 15,
                            color: _dates == null
                                ? Colors.grey[600]
                                : AppColors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                            color: _lat == null
                                ? Colors.grey[600]
                                : AppColors.black,
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
              title: 'requests.budget'.tr(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _budgetController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'balance.enter_amount'.tr(),
                      suffixText: 'common.currency'.tr(),
                      border: const UnderlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return 'errors.price_positive'.tr();
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Text('requests.budget_hint'.tr(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              title: 'requests.comment'.tr(),
              child: TextFormField(
                controller: _commentController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: 'requests.comment_hint'.tr(),
                  border: const UnderlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSending ? null : _submit,
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
                    : Text('requests.create'.tr(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
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
