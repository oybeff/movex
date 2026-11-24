import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/services/listing_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../../core/widgets/h_icon.dart';

/// E'lon joylash (Create Listing) ekrani.
///
/// Mijoz stsenariysi:
/// Odam uyida ish qildirmoqchi (masalan: «Uyga hovuz kovlash kerak, chuqurligi 3 m,
/// eni 2 m, uzunligi 5 m, byudjet 1 000 000 so'm»). Aniq soat yoki tarifni bilmaydi,
/// e'lon qoldiradi — haydovchilar esa o'z narxi va muddatini taklif qilishadi.
/// Mijoz eng ma'qul taklifni qabul qiladi.
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
  final TextEditingController _telegram = TextEditingController();

  bool _allowChat = true;

  String? _equipmentType;
  DateTime? _from;
  DateTime? _to;

  /// Yuklangan rasm manzillari.
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
    _telegram.dispose();
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
              .copyWith(primary: AppPalette.brand),
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
        contactTelegram: _telegram.text.trim(),
        allowChat: _allowChat,
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
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
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
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const HIcon(Icons.arrow_back_ios_new,
              size: 20, color: AppPalette.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'listings.create'.tr(),
          style: AppTypography.h3.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          // ── Scenario Explainer Banner ─────────────────────────────
          _buildScenarioBanner(),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 1: Ish haqida (Sarlavha & Tafsilotlar) ─────────
          _cardWrapper(
            children: [
              _fieldLabel(
                'listings.title_field'.tr(),
                required: true,
              ),
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.body,
                decoration: _fieldInputDecoration(
                  hint: 'listings.title_hint'.tr(),
                  prefixIcon: Icons.edit_note_outlined,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _fieldLabel(
                'listings.description'.tr(),
                subtitle: 'listings.description_helper'.tr(),
              ),
              TextField(
                controller: _description,
                maxLines: 4,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.body,
                decoration: _fieldInputDecoration(
                  hint: 'listings.description_hint'.tr(),
                  prefixIcon: Icons.description_outlined,
                  isMultiline: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 2: Rasmlar ────────────────────────────────────
          _cardWrapper(
            children: [
              _fieldLabel(
                'listings.photos'.tr(),
                subtitle: 'listings.photos_subtitle'.tr(),
              ),
              _photoRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 3: Texnika turi ───────────────────────────────
          _cardWrapper(
            children: [
              _fieldLabel(
                'listings.type_optional'.tr(),
                subtitle: 'listings.type_helper'.tr(),
              ),
              _typePicker(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 4: Narx va Manzil ─────────────────────────────
          _cardWrapper(
            children: [
              _fieldLabel(
                'listings.budget'.tr(),
                subtitle: 'listings.budget_helper'.tr(),
              ),
              TextField(
                controller: _budget,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTypography.bodyMedium,
                decoration: _fieldInputDecoration(
                  hint: 'listings.budget_hint'.tr(),
                  prefixIcon: Icons.payments_outlined,
                ).copyWith(
                  suffixText: 'common.currency'.tr(),
                  suffixStyle: AppTypography.bodyMedium.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _fieldLabel('listings.address'.tr()),
              TextField(
                controller: _address,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.body,
                decoration: _fieldInputDecoration(
                  hint: 'listings.address_hint'.tr(),
                  prefixIcon: Icons.location_on_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 5: Sanalar va Aloqa ───────────────────────────
          _cardWrapper(
            children: [
              _fieldLabel('listings.dates'.tr()),
              InkWell(
                onTap: _pickDates,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.page,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppPalette.borderDefault),
                  ),
                  child: Row(
                    children: [
                      const HIcon(Icons.calendar_today_outlined,
                          size: 20, color: AppPalette.brand),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _from == null
                              ? 'listings.dates_hint'.tr()
                              : '${DateFormat('dd.MM.yyyy').format(_from!)} — '
                                  '${DateFormat('dd.MM.yyyy').format(_to!)}',
                          style: AppTypography.body.copyWith(
                            color: _from == null
                                ? AppPalette.textPlaceholder
                                : AppPalette.textPrimary,
                          ),
                        ),
                      ),
                      if (_from != null)
                        InkWell(
                          onTap: () => setState(() {
                            _from = null;
                            _to = null;
                          }),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: HIcon(Icons.close,
                                size: 18, color: AppPalette.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _fieldLabel(
                'listings.contact_methods'.tr(),
                subtitle: 'listings.contact_methods_helper'.tr(),
              ),

              // 1) Ilova ichidagi chat
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _allowChat ? AppPalette.brandSubtle : AppPalette.page,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: _allowChat
                        ? AppPalette.brand.withValues(alpha: 0.3)
                        : AppPalette.borderDefault,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _allowChat ? AppPalette.brand : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: const HIcon(Icons.chat_outlined,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'listings.contact_chat_title'.tr(),
                            style: AppTypography.bodyMMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'listings.contact_chat_subtitle'.tr(),
                            style: AppTypography.captionS.copyWith(
                              color: AppPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _allowChat,
                      activeThumbColor: AppPalette.brand,
                      onChanged: (val) => setState(() => _allowChat = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2) Telegram
              _fieldLabel('listings.contact_telegram'.tr()),
              TextField(
                controller: _telegram,
                textInputAction: TextInputAction.next,
                style: AppTypography.body,
                decoration: _fieldInputDecoration(
                  hint: 'listings.contact_telegram_hint'.tr(),
                  prefixIcon: Icons.send_rounded,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3) Telefon raqam
              _fieldLabel('listings.contact_phone'.tr()),
              TextField(
                controller: _phone,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.phone,
                style: AppTypography.body,
                decoration: _fieldInputDecoration(
                  hint: 'listings.contact_phone_hint'.tr(),
                  prefixIcon: Icons.phone_outlined,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Row(
                  children: [
                    const HIcon(Icons.lock_outline,
                        size: 14, color: AppPalette.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'listings.phone_privacy'.tr(),
                        style: AppTypography.captionS.copyWith(
                          color: AppPalette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Xato bildirishnomalari ────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppPalette.dangerSubtle,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppPalette.borderDanger),
              ),
              child: Row(
                children: [
                  const HIcon(Icons.error_outline,
                      color: AppPalette.textDanger, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppTypography.bodyM.copyWith(
                        color: AppPalette.textDanger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── Submit Button ─────────────────────────────────────────
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: ElevatedButton(
              onPressed: _isSending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.brand,
                foregroundColor: AppPalette.textOnBrand,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.textOnBrand,
                      ),
                    )
                  : Text(
                      'listings.publish'.tr(),
                      style: AppTypography.buttonLarge.copyWith(
                        color: AppPalette.textOnBrand,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'listings.ttl_note'.tr(args: ['14']),
            textAlign: TextAlign.center,
            style: AppTypography.captionS.copyWith(
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Tushuntiruvchi banner: mijoz e'lon joylaydi, haydovchilar taklif kiritadi.
  Widget _buildScenarioBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.brandSubtle,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppPalette.brand.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              shape: BoxShape.circle,
              boxShadow: AppShadows.xs,
            ),
            child: const HIcon(
              Icons.handyman_outlined,
              color: AppPalette.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'listings.scenario_title'.tr(),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppPalette.brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'listings.scenario_desc'.tr(),
                  style: AppTypography.captionS.copyWith(
                    color: AppPalette.textPrimary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardWrapper({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppPalette.borderDefault),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _fieldLabel(
    String text, {
    bool required = false,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                text,
                style: AppTypography.bodyMMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(
                    color: AppPalette.textDanger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTypography.captionS.copyWith(
                color: AppPalette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldInputDecoration({
    required String hint,
    IconData? prefixIcon,
    bool isMultiline = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.hint.copyWith(
        color: AppPalette.textPlaceholder,
      ),
      filled: true,
      fillColor: AppPalette.page,
      counterText: '',
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: isMultiline ? AppSpacing.md : AppSpacing.lg,
      ),
      prefixIcon: prefixIcon != null
          ? HIcon(prefixIcon, size: 20, color: AppPalette.iconSecondary)
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderFocus, width: 1.5),
      ),
    );
  }

  Widget _photoRow() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < _photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.network(
                      AppConfig.mediaUrl(_photos[i]),
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        height: 92,
                        color: AppPalette.page,
                        child: const HIcon(
                          Icons.broken_image_outlined,
                          color: AppPalette.textPlaceholder,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppPalette.inverse.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const HIcon(
                          Icons.close,
                          size: 14,
                          color: AppPalette.surface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: _isUploading ? null : _pickPhoto,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppPalette.page,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppPalette.borderDefault,
                  width: 1.2,
                ),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.brand,
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const HIcon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: AppPalette.brand,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'listings.add_photo'.tr(),
                          style: AppTypography.captionS.copyWith(
                            color: AppPalette.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typePicker() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final code in EquipmentTypes.codes)
          ChoiceChip(
            showCheckmark: false,
            selected: _equipmentType == code,
            onSelected: (selected) =>
                setState(() => _equipmentType = selected ? code : null),
            avatar: EquipmentTypeIcon(code, size: 24),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            label: Text(
              EquipmentTypes.label(code),
              style: AppTypography.captionS.copyWith(
                fontWeight: _equipmentType == code
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _equipmentType == code
                    ? AppPalette.brand
                    : AppPalette.textPrimary,
              ),
            ),
            selectedColor: AppPalette.brandSubtle,
            backgroundColor: AppPalette.page,
            side: BorderSide(
              color: _equipmentType == code
                  ? AppPalette.brand
                  : AppPalette.borderDefault,
              width: _equipmentType == code ? 1.5 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
      ],
    );
  }
}
