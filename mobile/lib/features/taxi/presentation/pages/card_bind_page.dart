import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/card_api.dart';
import '../widgets/taxi_ui.dart';

/// Добавить карту: K2/K3 — форма Multicard в WebView (номер карты и SMS-код
/// вводятся у Multicard: своих полей карты у нас быть не может без PCI DSS),
/// затем K4 «Karta qo'shildi». Возвращает добавленную карту или null.
Future<BankCard?> addBankCard(BuildContext context) async {
  final api = CardApi();
  final ({String sessionId, String formUrl}) s;
  try {
    s = await api.bind();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    }
    return null;
  }
  if (!context.mounted) return null;
  final card = await Navigator.of(context).push<BankCard>(
    MaterialPageRoute(builder: (_) => _BindPage(sessionId: s.sessionId, formUrl: s.formUrl)),
  );
  if (card == null || !context.mounted) return null;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardAddedPage(card: card)));
  return card;
}

class _BindPage extends StatefulWidget {
  const _BindPage({required this.sessionId, required this.formUrl});

  final String sessionId;
  final String formUrl;

  @override
  State<_BindPage> createState() => _BindPageState();
}

class _BindPageState extends State<_BindPage> {
  final _api = CardApi();
  WebViewController? _web;
  Timer? _poll;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // В браузере WebView нет: форма в новой вкладке, статус опрашиваем
      launchUrl(Uri.parse(widget.formUrl), mode: LaunchMode.externalApplication);
    } else {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
          if (req.url.contains('/cards/bind/done')) {
            _check();
            return NavigationDecision.prevent;
          }
          if (req.url.contains('/cards/bind/fail')) {
            _failed();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        }))
        ..loadRequest(Uri.parse(widget.formUrl));
    }
    // Колбэк может прийти раньше редиректа — опрашиваем статус и так
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check({bool quiet = false}) async {
    if (_done) return;
    try {
      final c = await _api.status(widget.sessionId);
      if (c != null && mounted && !_done) {
        _done = true;
        _poll?.cancel();
        Navigator.of(context).pop(c);
      } else if (c == null && !quiet && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('taxi.card_not_added_yet'.tr())));
      }
    } catch (e) {
      if (apiStatus(e) == 409 && mounted && !_done) {
        _done = true;
        _poll?.cancel();
        await showCardAlreadyAdded(context);
        if (mounted) Navigator.of(context).pop();
      } else if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
      }
    }
  }

  void _failed() {
    if (!mounted) return;
    _done = true;
    _poll?.cancel();
    showCardRejected(context);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TaxiPageHeader(title: 'taxi.add_card_title'.tr()),
              Expanded(
                child: _web != null
                    ? WebViewWidget(controller: _web!)
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.gutter),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('taxi.card_form_opened'.tr(), textAlign: TextAlign.center, style: AppTypography.subtitle),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _check, child: Text('taxi.card_form_done'.tr())),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
}

/// Рисунок карты (синий градиент, чип, маска номера, система).
class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.card, this.grey = false});

  final BankCard card;
  final bool grey;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 343 / 188,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: grey
                  ? const [Color(0xFF4B5563), Color(0xFF9CA3AF)]
                  : const [Color(0xFF2A62C0), Color(0xFF5B9BEA)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 30,
                    decoration: BoxDecoration(color: const Color(0xFFF6C849), borderRadius: BorderRadius.circular(6)),
                  ),
                  const Spacer(),
                  Text('taxi.bank_card'.tr(),
                      style: const TextStyle(fontFamily: AppTypography.fontFamily, fontSize: 13, color: Colors.white70)),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  card.pan.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]}  ').trim(),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 22,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(card.holder ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: AppTypography.fontFamily, fontSize: 13, color: Colors.white)),
                  ),
                  Text(
                    (card.ps ?? '').toUpperCase(),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// K4 · Karta qo'shildi.
class CardAddedPage extends StatefulWidget {
  const CardAddedPage({super.key, required this.card});

  final BankCard card;

  @override
  State<CardAddedPage> createState() => _CardAddedPageState();
}

class _CardAddedPageState extends State<CardAddedPage> {
  late bool _main = widget.card.isDefault;

  Future<void> _done() async {
    if (_main && !widget.card.isDefault) {
      try {
        await CardApi().makeDefault(widget.card.id);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 70),
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(color: AppPalette.successSubtle, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(color: AppPalette.textSuccess, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text('taxi.card_added'.tr(), textAlign: TextAlign.center, style: AppTypography.h1),
                const SizedBox(height: 12),
                Text('taxi.card_added_body'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: AppTypography.fontFamily, fontSize: 15, height: 22 / 15, color: AppPalette.textSecondary)),
                const SizedBox(height: 32),
                CardArt(card: widget.card),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('taxi.make_main'.tr(), style: AppTypography.bodyMedium),
                            const SizedBox(height: 2),
                            Text('taxi.make_main_hint'.tr(), style: AppTypography.captionS.copyWith(fontSize: 13)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _main,
                        onChanged: widget.card.isDefault ? null : (v) => setState(() => _main = v),
                        activeTrackColor: AppPalette.brand,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _done, child: Text('taxi.done'.tr())),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
}

Widget _dialog(BuildContext ctx,
        {required Widget icon,
        required Color iconBg,
        required String title,
        required String body,
        required String primary,
        String? secondary,
        Color? secondaryColor}) =>
    Dialog(
      backgroundColor: AppPalette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: icon,
              ),
            ),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: AppTypography.h3),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center, style: AppTypography.subtitle),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(primary)),
            if (secondary != null)
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: secondaryColor ?? AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                  ),
                  child: Text(secondary),
                ),
              ),
          ],
        ),
      ),
    );

/// T4 · Karta allaqachon qo'shilgan (у другого аккаунта).
Future<void> showCardAlreadyAdded(BuildContext context) => showDialog<bool>(
      context: context,
      barrierColor: const Color(0x730B1220),
      builder: (ctx) => _dialog(ctx,
          icon: const TaxiIcon('menu_card', size: 24),
          iconBg: AppPalette.brandSubtle,
          title: 'taxi.card_exists_title'.tr(),
          body: 'taxi.card_exists_body'.tr(),
          primary: 'taxi.understood'.tr()),
    );

/// K5 · Kartani ulab bo'lmadi.
void showCardRejected(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('taxi.card_rejected'.tr())),
    );

/// T6 · Kartani o'chirish. true — удалить.
Future<bool?> confirmDeleteCard(BuildContext context, BankCard c) => showDialog<bool>(
      context: context,
      barrierColor: const Color(0x730B1220),
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: AppPalette.dangerSubtle, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const TaxiIcon('menu_card', size: 24),
                ),
              ),
              const SizedBox(height: 10),
              Text('taxi.card_delete_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h3),
              const SizedBox(height: 10),
              Text('taxi.card_delete_body'.tr(args: [c.label]), textAlign: TextAlign.center, style: AppTypography.subtitle),
              const SizedBox(height: 16),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.brandSubtle,
                    foregroundColor: AppPalette.textDanger,
                    textStyle: AppTypography.buttonLarge,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: Text('taxi.card_delete_yes'.tr()),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.textBrand, textStyle: AppTypography.buttonLarge),
                  child: Text('taxi.cancel'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
