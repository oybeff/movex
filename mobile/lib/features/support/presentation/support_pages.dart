import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/number_formatter.dart';
import '../../../core/widgets/h_icon.dart';
import '../../taxi/presentation/widgets/taxi_ui.dart';
import '../data/support_api.dart';
import 'chat_view.dart';

String _money(double v) => '${NumberFormatter.formatCurrency(v)} ${'common.currency'.tr()}';

/// Nizo ochish: sabab, izoh, rasm. Hamma turdagi buyurtma uchun.
/// [role]: client — buyurtmachi, performer — ijrochi (ega / haydovchi).
/// Yuborilgach nizo ekrani ochiladi; true qaytaradi.
class OpenDisputePage extends StatefulWidget {
  const OpenDisputePage({super.key, required this.kind, required this.orderId, this.role = 'client'});

  /// equipment | freight | material
  final String kind;
  final int orderId;
  final String role;

  @override
  State<OpenDisputePage> createState() => _OpenDisputePageState();
}

class _OpenDisputePageState extends State<OpenDisputePage> {
  final _api = SupportApi();
  final _comment = TextEditingController();
  final List<String> _photos = [];
  late String _reason = _reasons.first;
  bool _busy = false;

  List<String> get _reasons {
    if (widget.role == 'performer') return const ['client_no_pay', 'client_absent', 'other'];
    switch (widget.kind) {
      case 'equipment':
        return const ['not_arrived', 'wrong_equipment', 'poor_quality', 'price_differs', 'other'];
      case 'material':
        return const ['not_arrived', 'damaged', 'wrong_quantity', 'price_differs', 'other'];
      default:
        return const ['not_arrived', 'damaged', 'price_differs', 'other'];
    }
  }

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
          ? await _api.uploadPhotoBytes(await file.readAsBytes(), file.name)
          : await _api.uploadPhoto(file.path, file.name);
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
      final d = await _api.openDispute(
          kind: widget.kind, orderId: widget.orderId, reason: _reason,
          comment: _comment.text.trim(), photos: _photos);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DisputePage(id: d.id)),
        result: true,
      );
    } catch (e) {
      _toast(getErrorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.problem_title'.tr()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 16),
                children: [
                  Text('taxi.problem_what'.tr(), style: AppTypography.h3),
                  const SizedBox(height: 10),
                  for (final r in _reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: r == _reason ? AppPalette.brandSubtle : AppPalette.page,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => setState(() => _reason = r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            child: Row(children: [
                              Expanded(child: Text('dispute.reason_$r'.tr(), style: AppTypography.bodyMedium)),
                              HIcon(r == _reason ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: r == _reason ? AppPalette.brand : AppPalette.textSecondary),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _comment,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'taxi.problem_comment'.tr(), counterText: ''),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addPhoto,
                    icon: const HIcon(Icons.photo_camera_outlined),
                    label: Text(_photos.isEmpty
                        ? 'taxi.problem_photo'.tr()
                        : 'taxi.problem_photo_n'.tr(args: ['${_photos.length}'])),
                  ),
                  const SizedBox(height: 12),
                  Text('dispute.how_it_works'.tr(), style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 8),
              child: ElevatedButton(onPressed: _busy ? null : _send, child: Text('taxi.send'.tr())),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nizo: holat, qaror va MoveX GO bilan yozishma (ikkala tomon ko'radi).
class DisputePage extends StatefulWidget {
  const DisputePage({super.key, required this.id});

  final int id;

  @override
  State<DisputePage> createState() => _DisputePageState();
}

class _DisputePageState extends State<DisputePage> {
  final _api = SupportApi();
  Dispute? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.dispute(widget.id);
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted && _d == null) setState(() => _error = getErrorMessage(e));
    }
  }

  Widget _head(Dispute d) {
    final res = d.resolution;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: d.open ? AppPalette.brandSubtle : AppPalette.successSubtle,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('dispute.reason_${d.reason}'.tr(), style: AppTypography.h3),
          const SizedBox(height: 4),
          Text('dispute.order_n'.tr(args: ['${d.orderId}']),
              style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
          const SizedBox(height: 8),
          Text(
            d.open
                ? 'dispute.status_open'.tr()
                : 'dispute.resolved_$res'.tr(args: [_money(d.refundAmount)]),
            style: AppTypography.bodyM,
          ),
          if ((d.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('«${d.comment}»', style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TaxiPageHeader(title: 'dispute.title_n'.tr(args: ['${widget.id}'])),
            Expanded(
              child: d == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
                    )
                  : ChatView(
                      header: _head(d),
                      messages: d.messages,
                      emptyText: 'dispute.wait_admin'.tr(),
                      canWrite: d.open,
                      closedText: 'dispute.closed'.tr(),
                      onRefresh: _load,
                      onSend: (text, photos) async {
                        final n = await _api.sendDisputeMessage(widget.id, text: text, photos: photos);
                        if (mounted) setState(() => _d = n);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mening nizolarim.
class DisputesPage extends StatefulWidget {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  final _api = SupportApi();
  List<Dispute>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.myDisputes();
      if (mounted) setState(() { _items = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = getErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          children: [
            TaxiPageHeader(title: 'dispute.mine'.tr()),
            Expanded(
              child: items == null
                  ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: items.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.all(40),
                                child: Text('dispute.none'.tr(), textAlign: TextAlign.center,
                                    style: AppTypography.body.copyWith(color: AppPalette.textSecondary)),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(AppSpacing.gutter),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final d = items[i];
                                return Material(
                                  color: AppPalette.surface,
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                    title: Text('dispute.reason_${d.reason}'.tr(), style: AppTypography.bodyMedium),
                                    subtitle: Text('dispute.order_n'.tr(args: ['${d.orderId}'])),
                                    trailing: Text(d.open ? 'dispute.badge_open'.tr() : 'dispute.badge_done'.tr(),
                                        style: AppTypography.captionSemibold.copyWith(
                                            color: d.open ? AppPalette.textBrand : AppPalette.textSuccess)),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => DisputePage(id: d.id)));
                                      _load();
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Yordam» chati: MoveX GO qo'llab-quvvatlash xizmati bilan yozishma.
class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _api = SupportApi();
  SupportThread? _t;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _api.thread();
      if (mounted) setState(() { _t = t; _error = null; });
    } catch (e) {
      if (mounted && _t == null) setState(() => _error = getErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TaxiPageHeader(title: 'support.title'.tr()),
            Expanded(
              child: t == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
                    )
                  : ChatView(
                      messages: t.messages,
                      emptyText: 'support.empty'.tr(),
                      onRefresh: _load,
                      onSend: (text, photos) async {
                        // Serverda bitta xabar — bitta rasm: qolganlari alohida xabar bo'lib ketadi
                        var n = await _api.sendSupport(text: text, photo: photos.isNotEmpty ? photos.first : null);
                        for (final p in photos.skip(1)) {
                          n = await _api.sendSupport(photo: p);
                        }
                        if (mounted) setState(() => _t = n);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
