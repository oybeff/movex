import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/services/listing_service.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

/// E'lon joylash.
///
/// Faqat sarlavha majburiy. Qolganining hammasi ixtiyoriy — odam ko'chada
/// turib yozadi, o'n qatorni to'ldirishga majbur qilsak hech kim yozmaydi.
/// Bo'sh qolgan maydonlar e'londa ko'rsatilmaydi.
class CreateListingPage extends StatefulWidget {
  const CreateListingPage({super.key});

  @override
  State<CreateListingPage> createState() => _CreateListingPageState();
}

class _CreateListingPageState extends State<CreateListingPage> {
  final ListingService _service = ListingService();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  String? _equipmentType;
  DateTime? _from;
  DateTime? _to;

  /// Yuklangan rasm manzillari. Rasm E'LON YARATILISHIDAN OLDIN yuklanadi:
  /// odam "joylash" bosishidan avval ularni ko'rib turishi kerak.
  final List<String> _photos = [];
  bool _isUploading = false;

  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _budget.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 6) {
      _snack('listings.photo_limit'.tr(args: ['6']));
      return;
    }
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
    } catch (_) {
      _snack('listings.photo_pick_failed'.tr());
      return;
    }
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      // Webda faylning yo'li yo'q — faqat mazmuni bor.
      final String url;
      if (kIsWeb) {
        final Uint8List bytes = await picked.readAsBytes();
        url = await _service.uploadPhoto(bytes: bytes, fileName: picked.name);
      } else {
        url = await _service.uploadPhoto(
            filePath: picked.path, fileName: picked.name);
      }
      if (!mounted) return;
      setState(() {
        _photos.add(url);
        _isUploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _snack(_detail(e) ?? 'listings.photo_upload_failed'.tr());
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.primaryGreen),
        ),
        child: child!,
      ),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.length < 2) {
      setState(() => _error = 'listings.title_required'.tr());
      return;
    }
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await _service.create(
        title: title,
        description: _description.text.trim(),
        equipmentType: _equipmentType,
        budget: double.tryParse(_budget.text.replaceAll(RegExp(r'[^0-9]'), '')),
        address: _address.text.trim(),
        neededFrom: _from,
        neededTo: _to,
        contactPhone: _phone.text.trim(),
        photos: _photos,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = _detail(e) ?? 'errors.something_went_wrong'.tr();
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'listings.create'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _label('listings.title_field'.tr(), required: true),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: _box('listings.title_hint'.tr()),
          ),

          _label('listings.description'.tr()),
          TextField(
            controller: _description,
            maxLines: 4,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: _box('listings.description_hint'.tr()),
          ),

          _label('listings.photos'.tr()),
          _photoRow(),

          _label('listings.type_optional'.tr()),
          _typePicker(),

          _label('listings.budget'.tr()),
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _box('listings.budget_hint'.tr()).copyWith(
              suffixText: 'common.currency'.tr(),
            ),
          ),

          _label('listings.address'.tr()),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: _box('listings.address_hint'.tr()).copyWith(
              prefixIcon: const Icon(Icons.place_outlined, size: 20),
            ),
          ),

          _label('listings.dates'.tr()),
          InkWell(
            onTap: _pickDates,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 18, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _from == null
                          ? 'listings.dates_hint'.tr()
                          : '${DateFormat('dd.MM.yyyy').format(_from!)} — '
                              '${DateFormat('dd.MM.yyyy').format(_to!)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: _from == null ? Colors.grey[600] : AppColors.black,
                      ),
                    ),
                  ),
                  if (_from != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _from = null;
                        _to = null;
                      }),
                    ),
                ],
              ),
            ),
          ),

          _label('listings.contact_phone'.tr()),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: _box('listings.contact_phone_hint'.tr()).copyWith(
              prefixIcon: const Icon(Icons.phone_outlined, size: 20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'listings.phone_privacy'.tr(),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('listings.publish'.tr(),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'listings.ttl_note'.tr(args: ['14']),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            if (required)
              const Text(' *', style: TextStyle(color: AppColors.error)),
          ],
        ),
      );

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[500]),
        filled: true,
        fillColor: AppColors.white,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen),
        ),
      );

  Widget _photoRow() {
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < _photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      AppConfig.mediaUrl(_photos[i]),
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 88,
                        height: 88,
                        color: AppColors.lightGrey,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: _isUploading ? null : _pickPhoto,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primaryGreen),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            size: 22, color: Colors.grey[600]),
                        const SizedBox(height: 4),
                        Text('listings.add_photo'.tr(),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tur ixtiyoriy: e'lon aynan shuning uchun kerak — ma'lumotnomada
  /// yo'q narsani ham so'rash mumkin bo'lsin.
  Widget _typePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final code in EquipmentTypes.codes)
          ChoiceChip(
            selected: _equipmentType == code,
            onSelected: (selected) =>
                setState(() => _equipmentType = selected ? code : null),
            avatar: EquipmentTypeIcon(code, size: 20),
            label: Text(EquipmentTypes.label(code),
                style: const TextStyle(fontSize: 12)),
            selectedColor: AppColors.primaryGreen.withValues(alpha: 0.18),
            backgroundColor: AppColors.white,
            side: BorderSide(
              color: _equipmentType == code
                  ? AppColors.primaryGreen
                  : Colors.black12,
            ),
          ),
      ],
    );
  }
}
