import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../data/driver_api.dart';
import 'driver_ui.dart';

/// Документы водителя — макет 00: R5 «Hujjatlarni yuklang», R6/R7
/// снимок и «Surat aniqmi?», R8 «Tekshiruvga tayyor», R9 «yuborildi»,
/// V1 «Tabriklaymiz», V2 «qayta yuklang» с причиной от админа.
///
/// Документ уходит на сервер сразу после «Ishlatish»: так фото не
/// теряется, если человек закроет приложение посреди списка. «Tekshiruvga
/// yuborish» — только подтверждение согласия и экран R9.
class DriverVerificationPage extends StatefulWidget {
  const DriverVerificationPage({super.key});

  @override
  State<DriverVerificationPage> createState() => _DriverVerificationPageState();
}

class _DriverVerificationPageState extends State<DriverVerificationPage> {
  final _api = DriverApi();
  final _picker = ImagePicker();
  DriverVerification? _v;
  String? _uploading;
  bool _confirm = false; // R8
  bool _consent = false;
  bool _sent = false; // R9
  /// Документы уже были на проверке, когда экран открыли — сразу R9 (E5).
  /// Иначе статус pending после последней загрузки перепрыгнул бы через R8.
  bool? _openedPending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _api.verification();
      _openedPending ??= v.status == 'pending';
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    }
  }

  Future<void> _shoot(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('driver.doc_$kind'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text('driver.doc_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 12),
            DPrimary('driver.take_photo'.tr(), onPressed: () => Navigator.of(ctx).pop(ImageSource.camera)),
            const SizedBox(height: 8),
            DSecondary('driver.from_gallery'.tr(), tinted: true, onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final shot = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (shot == null || !mounted) return;
    // R7 «Surat aniqmi?»
    final use = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _PhotoCheckPage(path: shot.path, title: 'driver.doc_$kind'.tr()),
    ));
    if (use == false) return _shoot(kind); // «Qayta olish»
    if (use != true || !mounted) return;
    setState(() => _uploading = kind);
    try {
      final v = await _api.uploadDocument(kind, shot.path);
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (v.approved) return _approved();
    if (_sent || (v.status == 'pending' && _openedPending == true)) return _submitted(v);
    if (_confirm) return _confirmPage(v);
    return _list(v);
  }

  /// R5 · список документов.
  Widget _list(DriverVerification v) {
    final done = v.requiredDone;
    final total = DriverVerification.required.length;
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(backgroundColor: AppPalette.page, title: Text('driver.documents'.tr())),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('driver.upload_docs'.tr(), style: AppTypography.h1),
            const SizedBox(height: 4),
            Text('driver.upload_docs_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('driver.required_docs'.tr(), style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('$done / $total', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                color: AppPalette.brand,
                backgroundColor: AppPalette.borderDefault,
              ),
            ),
            const SizedBox(height: 16),
            for (final k in DriverVerification.kinds) ...[
              _docTile(v, k),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DPrimary(
            'driver.send_review'.tr(),
            onPressed: done == total && _uploading == null ? () => setState(() => _confirm = true) : null,
          ),
        ),
      ),
    );
  }

  Widget _docTile(DriverVerification v, String kind) {
    final st = v.statusOf(kind);
    final reason = v.reasonOf(kind);
    final optional = !DriverVerification.required.contains(kind);
    final busy = _uploading == kind;
    final (String label, Color bg, Color fg) = switch (st) {
      'approved' => ('driver.doc_approved'.tr(), AppPalette.successSubtle, AppPalette.textSuccess),
      'pending' => ('driver.doc_pending'.tr(), DChip.blueBg, AppPalette.brand),
      'rejected' => ('driver.doc_rejected'.tr(), DChip.redBg, AppPalette.textDanger),
      _ => (optional ? 'driver.optional'.tr() : 'driver.upload'.tr(), AppPalette.page, AppPalette.textSecondary),
    };
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Одобренный документ сервер заменить не даст — и кнопки нет
        onTap: busy || st == 'approved' ? null : () => _shoot(kind),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: st == null ? AppPalette.page : bg, borderRadius: BorderRadius.circular(10)),
                child: busy
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(st == 'approved' ? Icons.check_rounded : Icons.description_outlined,
                        color: st == null ? AppPalette.textSecondary : fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('driver.doc_$kind'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      st == 'rejected' && reason != null
                          ? 'driver.reject_reason'.tr(args: [reason])
                          : (st == null ? 'driver.doc_${kind}_hint'.tr() : 'driver.doc_uploaded'.tr()),
                      style: TextStyle(fontSize: 12, color: st == 'rejected' ? AppPalette.textDanger : AppPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DChip(st == 'rejected' ? 'driver.reupload'.tr() : label, bg: bg, fg: fg),
            ],
          ),
        ),
      ),
    );
  }

  /// R8 · «Tekshiruvga tayyor».
  Widget _confirmPage(DriverVerification v) => Scaffold(
        backgroundColor: AppPalette.page,
        appBar: AppBar(
          backgroundColor: AppPalette.page,
          title: Text('driver.confirm'.tr()),
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _confirm = false)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('driver.ready_review'.tr(), style: AppTypography.h1),
            const SizedBox(height: 4),
            Text('driver.ready_review_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 16),
            for (final k in DriverVerification.kinds.where((k) => v.docs.containsKey(k)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DCard(
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, color: AppPalette.brand),
                      const SizedBox(width: 10),
                      Expanded(child: Text('driver.doc_$k'.tr(), style: const TextStyle(fontWeight: FontWeight.w500))),
                      const Icon(Icons.check_circle_rounded, color: AppPalette.textSuccess),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _consent,
              onChanged: (x) => setState(() => _consent = x ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text('driver.consent'.tr(), style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DPrimary('driver.send_review'.tr(), onPressed: _consent ? () => setState(() => _sent = true) : null),
          ),
        ),
      );

  /// R9 · «Hujjatlar tekshiruvga yuborildi» (и E5, пока идёт проверка).
  Widget _submitted(DriverVerification v) => _result(
        icon: Icons.shield_outlined,
        color: AppPalette.brand,
        bg: DChip.blueBg,
        title: 'driver.sent_title'.tr(),
        body: 'driver.sent_body'.tr(),
        button: 'driver.to_home'.tr(),
      );

  /// V1 · «Tabriklaymiz».
  Widget _approved() => _result(
        icon: Icons.check_rounded,
        color: Colors.white,
        bg: AppPalette.textSuccess,
        title: 'driver.approved_title'.tr(),
        body: 'driver.approved_body'.tr(),
        button: 'driver.go_online'.tr(),
      );

  Widget _result({
    required IconData icon,
    required Color color,
    required Color bg,
    required String title,
    required String body,
    required String button,
    Widget? extra,
  }) =>
      Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(child: CircleAvatar(radius: 40, backgroundColor: bg, child: Icon(icon, size: 44, color: color))),
                const SizedBox(height: 16),
                Text(title, textAlign: TextAlign.center, style: AppTypography.h1),
                const SizedBox(height: 6),
                Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.textSecondary)),
                ?extra,
                const Spacer(),
                DPrimary(button, onPressed: () => Navigator.of(context).pop(true)),
              ],
            ),
          ),
        ),
      );
}

/// R7 · «Surat aniqmi?» — снимок крупно, «Qayta olish» / «Ishlatish».
class _PhotoCheckPage extends StatelessWidget {
  const _PhotoCheckPage({required this.path, required this.title});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppPalette.surface,
        appBar: AppBar(backgroundColor: AppPalette.surface, title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('driver.photo_clear'.tr(), style: AppTypography.h1),
            const SizedBox(height: 4),
            Text('driver.photo_clear_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 16),
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(path), fit: BoxFit.contain)),
            const SizedBox(height: 16),
            for (final k in const ['photo_check_1', 'photo_check_2', 'photo_check_3'])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: AppPalette.brand),
                  const SizedBox(width: 8),
                  Text('driver.$k'.tr()),
                ]),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: DSecondary('driver.retake'.tr(), tinted: true, onPressed: () => Navigator.of(context).pop(false))),
                const SizedBox(width: 10),
                Expanded(child: DPrimary('driver.use_photo'.tr(), onPressed: () => Navigator.of(context).pop(true))),
              ],
            ),
          ),
        ),
      );
}
