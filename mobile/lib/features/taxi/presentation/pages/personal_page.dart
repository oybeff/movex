import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/user_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/delete_account_button.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';

/// Pr2 · Shaxsiy ma'lumotlar. Телефон не меняется: он — логин, смена
/// идёт через поддержку (как написано под полем).
class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  String? _phone;
  String? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    UserService().getCurrentUser().then((u) {
      if (!mounted) return;
      final parts = u.fullName.trim().split(RegExp(r'\s+'));
      setState(() {
        _first.text = parts.isEmpty ? '' : parts.first;
        _last.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        _email.text = u.email ?? '';
        _phone = u.phone;
        _avatar = u.avatarUrl;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  String get _initials {
    final s = [_first.text, _last.text].where((p) => p.trim().isNotEmpty).map((p) => p.trim()[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  String get _phoneText {
    final d = (_phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 12) return _phone ?? '';
    return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} ${d.substring(8, 10)} ${d.substring(10)}';
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _photo() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final url = await ProfileApi().uploadAvatar(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _avatar = url);
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = [_first.text.trim(), _last.text.trim()].where((p) => p.isNotEmpty).join(' ');
    if (name.isEmpty) {
      _toast('taxi.name_required'.tr());
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _toast('taxi.email_invalid'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      // Пустую почту не шлём: поле в базе уникальное, «» у двоих столкнётся
      await UserService().updateCurrentUser(fullName: name, email: email.isEmpty ? null : email);
      if (!mounted) return;
      _toast('taxi.saved'.tr());
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.personal_title'.tr()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 16),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _busy ? null : _photo,
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: Stack(
                          children: [
                            ProfileAvatar(size: 96, initials: _initials, url: _avatar),
                            Positioned(
                              left: 66,
                              top: 64,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: AppPalette.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: AppShadows.card,
                                ),
                                alignment: Alignment.center,
                                child: const TaxiIcon('camera', size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: GestureDetector(
                      onTap: _busy ? null : _photo,
                      child: Text(
                        'taxi.change_photo'.tr(),
                        style: AppTypography.bodyMMedium.copyWith(color: AppPalette.textBrand),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Field(label: 'taxi.first_name'.tr(), controller: _first, onChanged: () => setState(() {})),
                  const SizedBox(height: 14),
                  _Field(label: 'taxi.last_name'.tr(), controller: _last, onChanged: () => setState(() {})),
                  const SizedBox(height: 14),
                  _Field(label: 'taxi.phone'.tr(), value: _phoneText, locked: true),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('taxi.phone_change_hint'.tr(), style: AppTypography.captionS),
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'taxi.email_optional'.tr(),
                    controller: _email,
                    onChanged: () => setState(() {}),
                    keyboard: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(onPressed: _busy ? null : _save, child: Text('taxi.save'.tr())),
                  const SizedBox(height: 4),
                  // Требование Google Play: аккаунт удаляется из приложения.
                  const DeleteAccountButton(large: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Input из макета: серое поле 56, плавающая подпись 12 над значением 16.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    this.controller,
    this.value,
    this.locked = false,
    this.keyboard,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? value;
  final bool locked;
  final TextInputType? keyboard;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          children: [
            Expanded(
              child: locked
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: AppTypography.captionS),
                        const SizedBox(height: 2),
                        Text(value ?? '', style: AppTypography.bodyMedium),
                      ],
                    )
                  // Подпись 12 сверху всегда, значение 16 под ней — как Input в макете
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (controller!.text.isNotEmpty) ...[
                          Text(label, style: AppTypography.captionS),
                          const SizedBox(height: 2),
                        ],
                        TextField(
                          controller: controller,
                          keyboardType: keyboard,
                          onChanged: (_) => onChanged?.call(),
                          style: AppTypography.bodyMedium,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: label,
                            hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary),
                          ),
                        ),
                      ],
                    ),
            ),
            if (locked) const TaxiIcon('lock_field', size: 20),
          ],
        ),
      );
}
