import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';

/// B5 · Muammo haqida xabar. Возвращает true, если жалоба ушла.
///
/// Жалоба останавливает автоподтверждение заказа на сервере: деньги не
/// уйдут владельцу, пока заказ не разберут.
class ProblemPage extends StatefulWidget {
  const ProblemPage({super.key, required this.orderId});

  final int orderId;

  @override
  State<ProblemPage> createState() => _ProblemPageState();
}

class _ProblemPageState extends State<ProblemPage> {
  static const _reasons = [
    'not_arrived',
    'wrong_equipment',
    'poor_quality',
    'price_differs',
    'other',
  ];

  final _api = TaxiService();
  final _comment = TextEditingController();
  String _reason = 'wrong_equipment';
  final List<String> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 3 || _busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final url = kIsWeb
          ? await _api.uploadProblemPhotoBytes(await file.readAsBytes(), file.name)
          : await _api.uploadProblemPhoto(file.path, file.name);
      if (mounted) setState(() => _photos.add(url));
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await _api.reportProblem(
        widget.orderId,
        reason: _reason,
        comment: _comment.text.trim(),
        photos: _photos,
      );
      if (!mounted) return;
      _toast('taxi.problem_sent'.tr());
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast(getErrorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Widget _row(String r) {
    final on = r == _reason;
    // Подпись в макете есть только у «Texnika nosoz yoki boshqa»
    final hasSub = on && r == 'wrong_equipment';
    return GestureDetector(
      onTap: () => setState(() => _reason = r),
      child: Container(
        height: 60,
        padding: const EdgeInsets.only(left: 12, right: 14),
        decoration: BoxDecoration(
          color: on ? AppPalette.brandSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: on ? AppPalette.surface : AppPalette.page,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const TaxiIcon('alert', size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('taxi.problem_$r'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium),
                  if (hasSub)
                    Text(
                      'taxi.problem_wrong_equipment_hint'.tr(),
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
            const SizedBox(width: 12),
            on
                ? const TaxiIcon('radio_on', size: 22)
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFC9D0D9), width: 2),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 0),
              child: Row(
                children: [
                  Material(
                    color: AppPalette.brandSubtle,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: TaxiIcon('back', size: 20, color: AppPalette.iconBrand)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('taxi.problem_title'.tr(), style: AppTypography.h3),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 16),
                children: [
                  Text('taxi.problem_what'.tr(), style: AppTypography.h3),
                  const SizedBox(height: 10),
                  for (final r in _reasons) ...[_row(r), const SizedBox(height: 10)],
                  TextField(
                    controller: _comment,
                    maxLength: 1000,
                    decoration: InputDecoration(labelText: 'taxi.problem_comment'.tr(), counterText: ''),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _addPhoto,
                    child: CustomPaint(
                      painter: _DashedBorder(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const TaxiIcon('camera', size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _photos.isEmpty
                                  ? 'taxi.problem_photo'.tr()
                                  : 'taxi.problem_photo_n'.tr(args: ['${_photos.length}']),
                              style: AppTypography.bodyMMedium.copyWith(color: AppPalette.textBrand),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 8),
              child: ElevatedButton(
                onPressed: _busy ? null : _send,
                child: Text('taxi.send'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пунктирная рамка «Rasm qo'shish» (1.5, #E5E9EE, радиус 12).
class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.borderDefault
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
