import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../data/app_status.dart';
import '../widgets/taxi_ui.dart';
import 'help_page.dart';

/// Пустое состояние экрана: «ореол» 140 с кругом 112 и иконкой, заголовок,
/// текст (U2, U3, U5, U6).
class HaloState extends StatelessWidget {
  const HaloState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.halo = AppPalette.brandSubtle,
    this.extra,
  });

  final Widget icon;
  final String title;
  final String body;
  final Color halo;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 140,
            height: 140,
            // Внешнее кольцо в макете всегда голубое (U2, U3, B6), цветной —
            // только внутренний круг
            decoration: BoxDecoration(color: AppPalette.brandSubtle.withValues(alpha: .7), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: halo, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: icon,
            ),
          ),
          const SizedBox(height: 32),
          Text(title, textAlign: TextAlign.center, style: AppTypography.h2.copyWith(fontSize: 24, height: 32 / 24)),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              height: 22 / 15,
              color: AppPalette.textSecondary,
            ),
          ),
          if (extra != null) ...[const SizedBox(height: 16), extra!],
        ],
      );
}

/// U2 · Majburiy yangilanish. Назад не уйти: старая версия не пускается.
class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key, required this.status, required this.current});

  final AppStatus status;
  final String current;

  Future<void> _open() async {
    final url = !kIsWeb && Platform.isIOS ? status.storeIos : status.storeAndroid;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppPalette.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: HaloState(
                        icon: const Icon(Icons.refresh_rounded, size: 36, color: AppPalette.textPrimary),
                        title: 'taxi.update_title'.tr(),
                        body: 'taxi.update_body'.tr(),
                        extra: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
                          child: Text('$current  →  ${status.minVersion}',
                              style: AppTypography.bodyMMedium.copyWith(color: AppPalette.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(onPressed: _open, child: Text('taxi.update_btn'.tr())),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      );
}

/// U3 · Texnik ishlar. «Qayta urinish» спрашивает сервер снова и,
/// если работы кончились, закрывает экран (результат true).
class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, required this.status});

  final AppStatus status;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    final s = await AppStatus.fetch();
    if (!mounted) return;
    setState(() => _busy = false);
    if (s != null && !s.maintenance) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final until = widget.status.maintenanceUntil;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: HaloState(
                      halo: AppPalette.accentSubtle,
                      icon: const TaxiIcon('clock', size: 36),
                      title: 'taxi.maintenance_title'.tr(),
                      body: (until == null || until.isEmpty)
                          ? 'taxi.maintenance_body'.tr()
                          : 'taxi.maintenance_body_until'.tr(args: [until]),
                    ),
                  ),
                ),
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: _busy ? null : _retry,
                    style: TextButton.styleFrom(
                      backgroundColor: AppPalette.brandSubtle,
                      foregroundColor: AppPalette.textBrand,
                      textStyle: AppTypography.buttonLarge,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: Text('taxi.retry'.tr()),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpPage())),
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.textBrand,
                      textStyle: AppTypography.buttonLarge,
                    ),
                    child: Text('taxi.write_support'.tr()),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Проверка при запуске: true — можно идти дальше.
Future<bool> passAppStatus(BuildContext context) async {
  final s = await AppStatus.fetch();
  if (s == null || !context.mounted) return true;
  final current = await AppStatus.currentVersion();
  if (!context.mounted) return false;
  if (AppStatus.older(current, s.minVersion)) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UpdatePage(status: s, current: current)));
    return false;
  }
  if (s.maintenance) {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => MaintenancePage(status: s)));
    return ok == true;
  }
  return true;
}
