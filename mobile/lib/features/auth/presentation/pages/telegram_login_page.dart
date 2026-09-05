import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import 'package:movex_go/core/utils/error_handler.dart';
import 'package:movex_go/features/auth/data/repositories/auth_repository.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pin_page.dart';

/// Telegram orqali kirish.
///
/// Oqim: server havola beradi (`t.me/<bot>?start=<token>`), odam botni ochib
/// raqamini ulashadi, ilova esa shu vaqtda serverdan "tasdiqlandimi" deb
/// so'rab turadi. Kod kiritish YO'Q — raqamni Telegramning o'zi tasdiqlaydi,
/// bu SMS kodidan kam ishonchli emas.
///
/// Nega havola kerak: bot odamga birinchi bo'lib yoza olmaydi va uni telefon
/// raqami bo'yicha topa olmaydi. Birinchi qadamni doim odam bosadi.
class TelegramLoginPage extends StatefulWidget {
  const TelegramLoginPage({super.key});

  @override
  State<TelegramLoginPage> createState() => _TelegramLoginPageState();
}

enum _Stage { loading, waiting, chooseRole, failed }

class _TelegramLoginPageState extends State<TelegramLoginPage> {
  final AuthRepository _authRepository = AuthRepository();

  /// So'rash oralig'i. Tez-tez so'rashning ma'nosi yo'q: odam bu vaqtda
  /// Telegramga o'tib, tugmani bosib ulguradi.
  static const _pollInterval = Duration(seconds: 2);

  _Stage _stage = _Stage.loading;
  String? _token;
  String? _link;
  String? _phone;
  String _error = '';
  int _secondsLeft = 0;

  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Taymerlarni to'xtatish SHART: sahifa yopilgandan keyin ham so'rab
    // tursa, setState o'lik widgetda chaqiriladi va ilova yiqiladi.
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _stage = _Stage.loading;
      _error = '';
    });

    try {
      final result = await _authRepository.telegramStart();
      if (!mounted) return;

      setState(() {
        _token = result['token'] as String;
        _link = result['url'] as String;
        _secondsLeft = result['expires_in'] as int;
        _stage = _Stage.waiting;
      });

      _poll = Timer.periodic(_pollInterval, (_) => _check());
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _countdown());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        // Bot sozlanmagan bo'lsa server 400 qaytaradi — buni alohida
        // aytamiz, aks holda odam tarmoq xatosi deb o'ylaydi
        _error = 'auth.telegram_unavailable'.tr();
      });
      showErrorDialog(context, e);
    }
  }

  void _countdown() {
    if (!mounted) return;
    if (_secondsLeft <= 1) {
      _stop();
      setState(() {
        _stage = _Stage.failed;
        _error = 'auth.telegram_expired'.tr();
      });
      return;
    }
    setState(() => _secondsLeft--);
  }

  void _stop() {
    _poll?.cancel();
    _tick?.cancel();
    _poll = null;
    _tick = null;
  }

  Future<void> _check() async {
    final token = _token;
    if (token == null) return;

    try {
      final result = await _authRepository.telegramStatus(token);
      if (!mounted) return;

      final status = result['status'] as String;
      if (status == 'confirmed') {
        _phone = result['phone'] as String?;
        _stop();
        await _complete(token);
      } else if (status == 'expired' || status == 'not_found') {
        _stop();
        setState(() {
          _stage = _Stage.failed;
          _error = 'auth.telegram_expired'.tr();
        });
      }
    } catch (_) {
      // Tarmoq uzilishi tabiiy — keyingi so'rovda qayta urinamiz.
      // Bu yerda xato ko'rsatish noto'g'ri bo'lardi: bitta uzilgan
      // so'rov butun kirishni to'xtatib qo'yardi.
    }
  }

  Future<void> _complete(String token) async {
    try {
      final result = await _authRepository.telegramComplete(token);
      if (!mounted) return;

      if (result['success'] == true && result['token'] != null) {
        // Kirish endi saqlanadi va qaytadan so'ralmaydi, shuning uchun
        // bu yerda PIN kod taklif qilinadi — bir marta.
        await offerPinSetup(context);
        if (!mounted) return;
        final role = result['role'];
        if (role == 'client') {
          context.go('/clientHome');
        } else if (role == 'owner') {
          context.go('/ownerHome');
        } else {
          context.go('/');
        }
        return;
      }

      // Hisob hali yo'q. Raqam tasdiqlangan, ya'ni SMS qayta so'rashning
      // hojati yo'q — darhol ro'yxatdan o'tishga o'tamiz. Rolni shu yerda
      // so'raymiz: aks holda hamma "mijoz" bo'lib qolardi, texnika egasi
      // esa o'z parkini umuman qo'sha olmasdi.
      setState(() => _stage = _Stage.chooseRole);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'auth.telegram_expired'.tr();
      });
      showErrorDialog(context, e);
    }
  }

  Future<void> _openTelegram() async {
    final link = _link;
    if (link == null) return;

    final uri = Uri.parse(link);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;

    if (!opened) {
      // Telegram o'rnatilmagan bo'lishi mumkin. Havolani buferga qo'yamiz —
      // shunda odam uni brauzerda ochib, botga o'ta oladi.
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('auth.telegram_cant_open'.tr()),
        description: Text('auth.telegram_link_copied'.tr()),
        autoCloseDuration: const Duration(seconds: 5),
        alignment: Alignment.topCenter,
      );
    }
  }

  void _finishRegistration(String role) {
    final phone = _phone;
    if (phone == null) {
      context.go('/');
      return;
    }
    context.pushReplacement('/register-complete', extra: {
      'phone': phone,
      'role': role,
    });
  }

  String get _timeLeft {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: Text('auth.telegram_title'.tr()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.loading:
        return const CircularProgressIndicator(color: AppColors.primaryGreen);

      case _Stage.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppColors.black),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _start,
              style: _primaryButton(),
              child: Text('auth.telegram_retry'.tr()),
            ),
          ],
        );

      case _Stage.chooseRole:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 56, color: AppColors.primaryGreen),
            const SizedBox(height: 16),
            Text(
              'auth.telegram_confirmed'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'role_select.title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _finishRegistration('client'),
              icon: const Icon(Icons.person, size: 22),
              label: Text('role_select.client'.tr()),
              style: _primaryButton(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _finishRegistration('owner'),
              icon: const Icon(Icons.engineering, size: 22),
              label: Text('role_select.owner'.tr()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                foregroundColor: AppColors.primaryGreen,
                side: const BorderSide(color: AppColors.primaryGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        );

      case _Stage.waiting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send, size: 56, color: AppColors.primaryGreen),
            const SizedBox(height: 20),
            Text(
              'auth.telegram_hint'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.black),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _openTelegram,
              icon: const Icon(Icons.open_in_new, size: 20),
              label: Text('auth.telegram_open'.tr()),
              style: _primaryButton(),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 12),
            Text(
              'auth.telegram_waiting'.tr(),
              style: const TextStyle(fontSize: 14, color: AppColors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              _timeLeft,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.grey,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        );
    }
  }

  ButtonStyle _primaryButton() => ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}
