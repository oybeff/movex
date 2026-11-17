import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/message_model.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/services/message_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../widgets/taxi_ui.dart';

/// M4 · Texnika egasi bilan chat.
class TaxiChatPage extends StatefulWidget {
  const TaxiChatPage({
    super.key,
    required this.chatId,
    required this.orderId,
    this.name,
    this.initials,
    this.phone,
    this.status,
    this.acceptedAt,
  });

  final int chatId;
  final int orderId;
  final String? name;
  final String? initials;
  final String? phone;

  /// Когда заказ подтверждён — для строки «Bugun · Buyurtma #… qabul
  /// qilindi» в макете. Нет даты — пишем просто «Bugun» не станем: для
  /// вчерашнего заказа это была бы неправда.
  final DateTime? acceptedAt;

  /// Зелёная строка под именем: «Yo'lda · 12 daqiqada yetadi».
  final String? status;

  @override
  State<TaxiChatPage> createState() => _TaxiChatPageState();
}

class _TaxiChatPageState extends State<TaxiChatPage> {
  final _chats = ChatService();
  final _messages = MessageService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<MessageModel> _list = const [];
  int? _me;
  bool _sending = false;
  bool _netDown = false; // U4: последний запрос не прошёл
  final List<String> _failed = []; // U4: не ушли, можно повторить
  Timer? _poll;

  /// «Bugun · Buyurtma #1361 qabul qilindi». День подставляется только
  /// когда известна дата подтверждения: иначе остаётся одна фраза.
  String _systemLine() {
    final text = 'taxi.chat_system'.tr(args: ['${widget.orderId}']);
    final at = widget.acceptedAt?.toLocal();
    if (at == null) return text;
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final day = sameDay ? 'taxi.today'.tr() : DateFormat('d MMMM', context.locale.languageCode).format(at);
    return '$day · $text';
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _me = p.getInt('user_id'));
    });
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _chats.getMessagesForChat(widget.chatId);
      list.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (!mounted) return;
      final grew = list.length != _list.length;
      setState(() {
        _list = list;
        _netDown = false;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _netDown = true);
    }
  }

  Future<void> _send([String? text]) async {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (text == null) _input.clear();
      _failed.remove(t);
      await _messages.createMessage(MessageCreateModel(chatId: widget.chatId, messageText: t));
      await _load();
    } on DioException catch (e) {
      // Сеть — сообщение остаётся в ленте с «Qayta urinish»; иначе — ошибка сервера
      if (e.response == null) {
        if (mounted) {
          setState(() {
            if (!_failed.contains(t)) _failed.add(t);
            _netDown = true;
          });
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call() async {
    final p = widget.phone;
    if (p == null) return;
    await launchUrl(Uri.parse('tel:+${p.replaceAll(RegExp(r'\D'), '')}'));
  }

  String _hm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _bubble(MessageModel m) {
    final mine = m.senderId == _me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 274),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? AppPalette.brand : AppPalette.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.messageText,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  height: 20 / 15,
                  color: mine ? Colors.white : AppPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mine ? '${_hm(m.sentAt)}  ✓✓' : _hm(m.sentAt),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  height: 14 / 11,
                  color: mine ? Colors.white.withValues(alpha: .75) : AppPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failedBubble(String t) => Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Opacity(
              opacity: .5,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 274),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppPalette.brand,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(t,
                    style: const TextStyle(
                        fontFamily: AppTypography.fontFamily, fontSize: 15, height: 20 / 15, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TaxiIcon('alert', size: 14),
                const SizedBox(width: 4),
                Text('${'taxi.not_sent'.tr()} · ',
                    style: AppTypography.captionS.copyWith(color: AppPalette.textDanger)),
                GestureDetector(
                  onTap: () => _send(t),
                  child: Text('taxi.retry'.tr(),
                      style: AppTypography.captionSemibold.copyWith(color: AppPalette.textBrand)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final quick = ['taxi.qr_waiting'.tr(), 'taxi.qr_where'.tr(), 'taxi.qr_thanks'.tr()];
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          children: [
            TaxiPageHeader(
              title: widget.name ?? '',
              leading: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: AppPalette.accent, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      widget.initials ?? '',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name ?? 'taxi.owner'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary,
                          ),
                        ),
                        if (widget.status != null)
                          Text(
                            widget.status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 12,
                              height: 16 / 12,
                              color: AppPalette.textSuccess,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: widget.phone == null ? null : TaxiRoundButton(icon: 'phone_brand', onTap: _call),
            ),
            Container(height: 1, color: AppPalette.borderDefault),
            if (_netDown)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF6E0),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 8),
                child: Row(
                  children: [
                    const TaxiIcon('wifi_off', size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('taxi.chat_offline'.tr(),
                          style: AppTypography.bodyMMedium.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                color: AppPalette.page,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 15, AppSpacing.gutter, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration:
                            BoxDecoration(color: const Color(0xFFE4E8EE), borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          // В макете строка начинается с дня: «Bugun ·
                          // Buyurtma #2483 qabul qilindi».
                          _systemLine(),
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                            height: 16 / 12,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    for (final m in _list) _bubble(m),
                    for (final t in _failed) _failedBubble(t),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 10, AppSpacing.gutter, 8),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final q in quick) ...[
                          GestureDetector(
                            onTap: () => _send(q),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppPalette.borderDefault),
                              ),
                              child: Text(
                                q,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13,
                                  height: 18 / 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppPalette.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration:
                              BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(22)),
                          alignment: Alignment.centerLeft,
                          child: TextField(
                            controller: _input,
                            onSubmitted: (_) => _send(),
                            textInputAction: TextInputAction.send,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 15,
                              color: AppPalette.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'taxi.chat_hint'.tr(),
                              hintStyle: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 15,
                                color: AppPalette.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: AppPalette.brand,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _sending ? null : _send,
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(child: TaxiIcon('send', size: 20)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
