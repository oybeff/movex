import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/notification_model.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

/// Xabarnomalar ro'yxati.
///
/// Har bir satrda texnika turining ikonkasi turadi — buyurtma qaysi
/// mashina bo'yicha ekanini ro'yxatga qaramasdan ko'rish uchun.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final NotificationService _service = NotificationService();

  List<NotificationModel> _items = [];
  bool _isLoading = true;
  bool _hasError = false;

  /// Mahkamlangan xabarnomalar ro'yxatning tepasida turadi.
  ///
  /// Bu FAQAT shu qurilmadagi belgi, serverga yuborilmaydi: mahkamlash —
  /// bu foydalanuvchining o'zi uchun qulaylik, boshqa qurilmada yoki
  /// boshqa odamda ko'rinishi shart emas.
  Set<int> _pinned = {};

  static const String _pinnedKey = 'pinned_notifications';

  @override
  void initState() {
    super.initState();
    _loadPinned().then((_) => _load());
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_pinnedKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _pinned = saved.map(int.tryParse).whereType<int>().toSet();
    });
  }

  Future<void> _togglePin(NotificationModel item) async {
    setState(() {
      if (!_pinned.remove(item.id)) _pinned.add(item.id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _pinnedKey, _pinned.map((e) => e.toString()).toList());
  }

  /// Mahkamlanganlar tepada, qolganlari o'z tartibida.
  List<NotificationModel> get _ordered {
    final pinned = _items.where((n) => _pinned.contains(n.id)).toList();
    final rest = _items.where((n) => !_pinned.contains(n.id)).toList();
    return [...pinned, ...rest];
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final items = await _service.getNotifications(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((n) => n.copyWith(isRead: true)).toList();
      });
    } catch (_) {
      _showError();
    }
  }

  Future<void> _open(NotificationModel item) async {
    if (!item.isRead) {
      try {
        await _service.markRead(item.id);
        if (mounted) {
          setState(() {
            _items = _items
                .map((n) => n.id == item.id ? n.copyWith(isRead: true) : n)
                .toList();
          });
        }
      } catch (_) {
        // O'qilgan deb belgilay olmadik — bu ekranga o'tishga to'sqinlik qilmaydi
      }
    }

    if (item.orderId != null && mounted) {
      context.push('/order-statistics');
    }
  }

  /// Serverdan o'chirish. Muvaffaqiyatsiz bo'lsa `false` qaytaradi va satr
  /// joyida qoladi.
  ///
  /// Tartib muhim: tarmoq so'rovi confirmDismiss ichida, ro'yxatdan olib
  /// tashlash esa onDismissed da. Agar avval ro'yxatdan olib tashlab, xato
  /// bo'lganda qaytarsak, Flutter "A dismissed Dismissible widget is still
  /// part of the tree" deb yiqiladi.
  Future<bool> _confirmRemove(NotificationModel item) async {
    try {
      await _service.delete(item.id);
      return true;
    } catch (_) {
      _showError();
      return false;
    }
  }

  void _showError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('errors.something_went_wrong'.tr())),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'notifications.just_now'.tr();
    if (diff.inHours < 1) return 'notifications.minutes_ago'.tr(args: ['${diff.inMinutes}']);
    if (diff.inDays < 1) return 'notifications.hours_ago'.tr(args: ['${diff.inHours}']);
    if (diff.inDays < 7) return 'notifications.days_ago'.tr(args: ['${diff.inDays}']);
    return DateFormat('dd.MM.yyyy').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          'notifications.title'.tr(),
          style: const TextStyle(
            color: AppColors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.black),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'notifications.mark_all_read'.tr(),
                style: const TextStyle(color: AppColors.primaryGreen),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_hasError) {
      return _emptyState(
        icon: Icons.wifi_off,
        text: 'errors.something_went_wrong'.tr(),
        actionLabel: 'common.retry'.tr(),
      );
    }

    if (_items.isEmpty) {
      return _emptyState(
        icon: Icons.notifications_none,
        text: 'notifications.empty'.tr(),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _ordered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => _tile(_ordered[index]),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String text,
    String? actionLabel,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 140),
        Icon(icon, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 15),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _load,
              child: Text(
                actionLabel,
                style: const TextStyle(color: AppColors.primaryGreen),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(NotificationModel item) {
    final isPinned = _pinned.contains(item.id);

    return Dismissible(
      key: ValueKey(item.id),
      // O'ngga surish — mahkamlash, chapga — o'chirish.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: AppColors.grey,
        child: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            color: AppColors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: AppColors.white),
      ),
      confirmDismiss: (direction) async {
        // Mahkamlash satrni o'chirmaydi, shuning uchun har doim false:
        // aks holda Dismissible satrni daraxtdan olib tashlashga urinardi.
        if (direction == DismissDirection.startToEnd) {
          await _togglePin(item);
          return false;
        }
        // O'chirish serverda muvaffaqiyatli bo'lsagina satr ketadi
        return _confirmRemove(item);
      },
      onDismissed: (_) {
        setState(() {
          _items.removeWhere((n) => n.id == item.id);
          _pinned.remove(item.id);
        });
      },
      child: Container(
        // O'qilmagan xabarnoma yengil fon bilan ajralib turadi
        color: item.isRead ? AppColors.white : AppColors.primaryGreen.withValues(alpha: 0.06),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lightGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: EquipmentTypeIcon(item.equipmentType, size: 28),
            ),
          ),
          title: Row(
            children: [
              if (isPinned) ...[
                const Icon(Icons.push_pin, size: 14, color: AppColors.grey),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  item.displayTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        item.isRead ? FontWeight.w500 : FontWeight.bold,
                    color: AppColors.black,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.body != null && item.body!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _timeAgo(item.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          trailing: item.isRead
              ? null
              : Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                ),
          onTap: () => _open(item),
        ),
      ),
    );
  }
}
