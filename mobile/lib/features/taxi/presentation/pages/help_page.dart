import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/contact_method_model.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../widgets/taxi_ui.dart';
import 'app_status_pages.dart' show HaloState;

/// M6 · Yordam. Контакты — из админки (SettingsService), не из кода:
/// «Chatda yozish» ведёт в Telegram/WhatsApp, «Qo'ng'iroq» — на телефон.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  static const _faq = ['price', 'cancel', 'money', 'late', 'receipt'];

  List<ContactMethodModel> _methods = const [];
  String _query = '';
  String? _open = 'price';

  @override
  void initState() {
    super.initState();
    SettingsService().getContactMethods().then((m) {
      if (mounted) setState(() => _methods = m.where((x) => x.isActive == 1).toList());
    }).catchError((_) {});
  }

  ContactMethodModel? _find(List<String> types) {
    for (final t in types) {
      final m = _methods.where((m) => m.type.toLowerCase() == t).firstOrNull;
      if (m != null) return m;
    }
    return null;
  }

  Future<void> _launch(ContactMethodModel? m) async {
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('profile.help_empty'.tr())));
      return;
    }
    final v = m.value;
    final url = switch (m.type.toLowerCase()) {
      'phone' => 'tel:$v',
      'telegram' => v.startsWith('http') ? v : 'https://t.me/${v.replaceAll('@', '')}',
      'whatsapp' => 'https://wa.me/${v.replaceAll(RegExp(r'[^\d]'), '')}',
      'sms' => 'sms:$v',
      'email' => 'mailto:$v',
      _ => v,
    };
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _contact({required String icon, required Color bg, required String title, required String sub, VoidCallback? onTap}) =>
      Expanded(
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: TaxiIcon(icon, size: 20),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      height: 18 / 13,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final chat = _find(['telegram', 'whatsapp', 'sms']);
    final phone = _find(['phone']);
    final q = _query.trim().toLowerCase();
    final faq = _faq.where((k) {
      if (q.isEmpty) return true;
      return 'taxi.faq_${k}_q'.tr().toLowerCase().contains(q) || 'taxi.faq_${k}_a'.tr().toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'profile.help'.tr()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 24),
                children: [
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Row(
                      children: [
                        const TaxiIcon('search', size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            style: AppTypography.body,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'taxi.help_search'.tr(),
                              hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (faq.isNotEmpty) const SizedBox(height: 16),
                  if (faq.isNotEmpty) Row(
                    children: [
                      _contact(
                        icon: 'chat_white',
                        bg: AppPalette.brand,
                        title: 'taxi.help_chat'.tr(),
                        sub: 'taxi.help_chat_sub'.tr(),
                        onTap: () => _launch(chat),
                      ),
                      const SizedBox(width: 10),
                      _contact(
                        icon: 'phone',
                        bg: AppPalette.brandSubtle,
                        title: 'taxi.call'.tr(),
                        sub: phone == null ? '24/7' : '24/7 · ${phone.value}',
                        onTap: () => _launch(phone),
                      ),
                    ],
                  ),
                  if (faq.isEmpty) ...[
                    const SizedBox(height: 40),
                    HaloState(
                      icon: const TaxiIcon('menu_help', size: 32),
                      title: 'taxi.help_nothing'.tr(),
                      body: 'taxi.help_nothing_body'.tr(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(onPressed: () => _launch(chat), child: Text('taxi.write_operator'.tr())),
                  ] else ...[
                  const SizedBox(height: 16),
                  GroupLabel('taxi.faq_title'.tr()),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Column(
                      children: [
                        for (var i = 0; i < faq.length; i++)
                          _Faq(
                            q: 'taxi.faq_${faq[i]}_q'.tr(),
                            a: 'taxi.faq_${faq[i]}_a'.tr(),
                            open: _open == faq[i] || q.isNotEmpty,
                            last: i == faq.length - 1,
                            onTap: () => setState(() => _open = _open == faq[i] ? null : faq[i]),
                          ),
                      ],
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.q, required this.a, required this.open, required this.last, required this.onTap});

  final String q;
  final String a;
  final bool open;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppPalette.borderDefault)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      q,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 15,
                        height: 20 / 15,
                        fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                        color: AppPalette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TaxiIcon(open ? 'minus' : 'plus', size: 18),
                ],
              ),
              if (open) ...[
                const SizedBox(height: 6),
                Text(a, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
              ],
            ],
          ),
        ),
      );
}
