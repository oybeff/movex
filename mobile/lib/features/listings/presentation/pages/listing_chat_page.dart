import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/listing_model.dart';
import '../../../../core/services/listing_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/h_icon.dart';

/// E'lon bo'yicha mijoz va haydovchi o'rtasidagi ilova ichidagi chat.
class ListingChatPage extends StatefulWidget {
  const ListingChatPage({
    super.key,
    required this.listing,
    this.receiverId,
    this.receiverName,
  });

  final ListingModel listing;
  final int? receiverId;
  final String? receiverName;

  @override
  State<ListingChatPage> createState() => _ListingChatPageState();
}

class _ListingChatPageState extends State<ListingChatPage> {
  final ListingService _service = ListingService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  int? _currentUserId;
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _currentUserId = prefs.getInt('user_id'));
    }
  }

  Future<void> _loadMessages() async {
    try {
      final list = await _service.getListingMessages(widget.listing.id);
      if (!mounted) return;
      final grew = list.length != _messages.length;
      setState(() {
        _messages = list;
        _isLoading = false;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _isSending) return;

    _input.clear();
    setState(() => _isSending = true);

    try {
      await _service.sendListingMessage(
        widget.listing.id,
        text,
        receiverId: widget.receiverId,
      );
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('errors.something_went_wrong'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openTelegram(String telegram) async {
    String clean = telegram.trim();
    if (clean.startsWith('@')) {
      clean = clean.substring(1);
    }
    final url = clean.startsWith('http') ? clean : 'https://t.me/$clean';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.receiverName ?? widget.listing.title;

    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const HIcon(Icons.arrow_back_ios_new,
              size: 20, color: AppPalette.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary,
              ),
            ),
            Text(
              widget.listing.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionS.copyWith(
                color: AppPalette.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.listing.hasTelegram)
            IconButton(
              icon: const HIcon(Icons.send_rounded, color: Color(0xFF0088CC), size: 20),
              tooltip: 'Telegram',
              onPressed: () => _openTelegram(widget.listing.contactTelegram!),
            ),
          if (widget.listing.hasPhone)
            IconButton(
              icon: const HIcon(Icons.phone_outlined,
                  color: AppColors.primaryGreen, size: 20),
              tooltip: 'Telefon',
              onPressed: () => _callPhone(widget.listing.contactPhone!),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Info header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppPalette.brandSubtle.withValues(alpha: 0.5),
            child: Row(
              children: [
                const HIcon(Icons.info_outline, size: 16, color: AppPalette.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'chat.listing_chat_hint'.tr(args: [widget.listing.title]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionS.copyWith(
                      color: AppPalette.brand,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Messages list ────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppPalette.brand))
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'chat.no_messages'.tr(),
                          style: AppTypography.bodyM.copyWith(
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final isMe = msg['sender_id'] == _currentUserId;
                          final text = msg['message_text'] as String? ?? '';
                          final timeStr = msg['created_at'] as String?;
                          final time = timeStr != null
                              ? DateTime.tryParse(timeStr)?.toLocal()
                              : null;
                          final senderName = msg['sender_name'] as String?;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppPalette.brand
                                    : AppPalette.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                boxShadow: AppShadows.card,
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe && senderName != null) ...[
                                    Text(
                                      senderName,
                                      style: AppTypography.captionS.copyWith(
                                        color: AppPalette.brand,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  Text(
                                    text,
                                    style: AppTypography.body.copyWith(
                                      color: isMe
                                          ? AppPalette.textOnBrand
                                          : AppPalette.textPrimary,
                                    ),
                                  ),
                                  if (time != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('HH:mm').format(time),
                                      style: AppTypography.captionS.copyWith(
                                        fontSize: 10,
                                        color: isMe
                                            ? AppPalette.textOnBrand
                                                .withValues(alpha: 0.75)
                                            : AppPalette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // ── Input field ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(
              color: AppPalette.surface,
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    minLines: 1,
                    style: AppTypography.body,
                    decoration: InputDecoration(
                      hintText: 'chat.hint'.tr(),
                      hintStyle: AppTypography.hint,
                      filled: true,
                      fillColor: AppPalette.page,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _isSending ? null : _send,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppPalette.brand,
                      shape: BoxShape.circle,
                    ),
                    child: _isSending
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.textOnBrand,
                              ),
                            ),
                          )
                        : const HIcon(
                            Icons.send_rounded,
                            color: AppPalette.textOnBrand,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
