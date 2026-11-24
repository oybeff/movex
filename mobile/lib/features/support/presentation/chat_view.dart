import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/h_icon.dart';
import '../data/support_api.dart';

/// Xabarlar ro'yxati + yozish maydoni. Nizo va «Yordam» chatida bitta.
///
/// Push yo'q: ekran ochiq turganda [onRefresh] har 10 soniyada chaqiriladi.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.messages,
    required this.onSend,
    required this.onRefresh,
    this.header,
    this.canWrite = true,
    this.closedText,
    this.emptyText,
  });

  final List<ChatMessage> messages;
  final Future<void> Function(String text, List<String> photos) onSend;
  final Future<void> Function() onRefresh;
  final Widget? header;
  final bool canWrite;
  final String? closedText;
  final String? emptyText;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _api = SupportApi();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<String> _photos = [];
  bool _busy = false;
  Timer? _poll;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => widget.onRefresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  void didUpdateWidget(covariant ChatView old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != _lastCount) {
      _lastCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
    final t = _text.text.trim();
    if ((t.isEmpty && _photos.isEmpty) || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(t, List.of(_photos));
      _text.clear();
      _photos.clear();
    } catch (e) {
      // Matn o'chirilmaydi — odam qayta yuborishi mumkin
      _toast('support.not_sent'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _bubble(ChatMessage m) {
    final mine = m.mine;
    final support = m.fromSupport;
    final bg = mine ? AppPalette.brand : AppPalette.surface;
    final fg = mine ? AppPalette.textOnBrand : AppPalette.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: AppPalette.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  support ? 'support.team'.tr() : (m.authorName ?? ''),
                  style: AppTypography.captionSemibold.copyWith(
                      color: support ? AppPalette.textBrand : AppPalette.textSecondary),
                ),
              if ((m.text ?? '').isNotEmpty) Text(m.text!, style: AppTypography.body.copyWith(color: fg)),
              if (m.photos.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in m.photos)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(AppConfig.mediaUrl(p), width: 96, height: 96, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 96, height: 96)),
                    ),
                ]),
              ],
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(_time(m.createdAt),
                    style: AppTypography.captionS.copyWith(
                        color: mine ? AppPalette.textOnBrand.withValues(alpha: 0.75) : AppPalette.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 12),
              children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: 12)],
                if (msgs.isEmpty && widget.emptyText != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(widget.emptyText!, textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(color: AppPalette.textSecondary)),
                  ),
                for (final m in msgs) _bubble(m),
              ],
            ),
          ),
        ),
        if (!widget.canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppPalette.surface,
            child: Text(widget.closedText ?? '', textAlign: TextAlign.center,
                style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
          )
        else
          Container(
            color: AppPalette.surface,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 8),
                      child: Row(children: [
                        Text('taxi.problem_photo_n'.tr(args: ['${_photos.length}']), style: AppTypography.captionS),
                        const Spacer(),
                        TextButton(onPressed: () => setState(_photos.clear), child: Text('common.delete'.tr())),
                      ]),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'support.attach'.tr(),
                        onPressed: _busy ? null : _addPhoto,
                        icon: const HIcon(Icons.attach_file_rounded, color: AppPalette.textSecondary),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(hintText: 'support.write_hint'.tr(), counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'support.send'.tr(),
                        onPressed: _busy ? null : _send,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const HIcon(Icons.send_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
