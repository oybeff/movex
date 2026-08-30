import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:map_launcher/map_launcher.dart' as map_launcher;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/services/message_service.dart';
import '../../../../core/models/chat_model.dart';
import '../../../../core/models/message_model.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/number_formatter.dart';

// Import Owner ChatDetailPage
import '../../../owner_home/presentation/pages/chat_page.dart' show ChatDetailPage;

class ClientChatPage extends StatefulWidget {
  const ClientChatPage({super.key});

  @override
  State<ClientChatPage> createState() => _ClientChatPageState();
}

class _ClientChatPageState extends State<ClientChatPage> {
  final ChatService _chatService = ChatService();
  final OrderService _orderService = OrderService();

  List<ChatModel> _chats = [];
  final Map<int, OrderModel> _orders = {};
  bool _isLoading = true;
  String _filterTab = 'active'; // 'active' yoki 'archive'

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _isLoading = true);

    try {
      final chats = await _chatService.getChats();

      // Har bir chat uchun order ma'lumotlarini olish
      for (var chat in chats) {
        try {
          final order = await _orderService.getOrder(chat.orderId);
          _orders[chat.orderId] = order;
        } catch (e) {
          print('Error loading order ${chat.orderId}: $e');
        }
      }

      // Chatlarni so'nggi xabar vaqti bo'yicha tartiblash (eng yangi birinchi)
      chats.sort((a, b) {
        final aTime = a.lastMessageTime ?? a.createdAt;
        final bTime = b.lastMessageTime ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('chat.error'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  List<ChatModel> get _filteredChats {
    return _chats.where((chat) {
      final order = _orders[chat.orderId];
      if (order == null) return false;

      if (_filterTab == 'active') {
        // Faol: pending va confirmed
        return order.status == 'pending' || order.status == 'confirmed';
      } else {
        // Arxiv: completed, cancelled, rejected
        return order.status == 'completed' ||
               order.status == 'cancelled' ||
               order.status == 'rejected';
      }
    }).toList();
  }

  Widget _buildFilterChip(String tab, String label) {
    final isSelected = _filterTab == tab;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterTab = tab;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primaryGreen,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primaryGreen : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primaryGreen : Colors.grey[300]!,
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (difference.inDays == 1) {
      return 'common.yesterday'.tr();
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(dateTime);
    } else {
      return DateFormat('dd.MM.yyyy').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            // Filter Tabs
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildFilterChip('active', 'chat.active'.tr()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterChip('archive', 'chat.archive'.tr()),
                  ),
                ],
              ),
            ),
            // Chat List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                  : _filteredChats.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'chat.no_chats'.tr(),
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadChats,
                          color: AppColors.primaryGreen,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: _filteredChats.length,
                            itemBuilder: (context, index) {
                              final chat = _filteredChats[index];
                              final order = _orders[chat.orderId];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClientChatDetailPage(
                                      chatId: chat.id,
                                      orderId: chat.orderId,
                                    ),
                                  ),
                                ).then((_) => _loadChats());
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Avatar with gradient
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppColors.primaryGreen,
                                            Color(0xFF2ECC71),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primaryGreen.withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.receipt_long,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '#${chat.orderId}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      '${'chat.order'.tr()} #${chat.orderId}',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: Color(0xFF2C3E50),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _formatTime(chat.lastMessageTime),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  chat.lastMessage ?? 'chat.no_messages'.tr(),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                              if (chat.unreadCount > 0) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    gradient: const LinearGradient(
                                                      colors: [
                                                        AppColors.primaryGreen,
                                                        Color(0xFF2ECC71),
                                                      ],
                                                    ),
                                                    borderRadius: BorderRadius.circular(12),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: AppColors.primaryGreen.withValues(alpha: 0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    chat.unreadCount.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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

// Client Chat Detail sahifasi - Owner ChatDetailPage bilan bir xil
class ClientChatDetailPage extends StatefulWidget {
  final int chatId;
  final int orderId;

  const ClientChatDetailPage({
    super.key,
    required this.chatId,
    required this.orderId,
  });

  @override
  State<ClientChatDetailPage> createState() => _ClientChatDetailPageState();
}

class _ClientChatDetailPageState extends State<ClientChatDetailPage> {
  final ChatService _chatService = ChatService();
  final MessageService _messageService = MessageService();
  final OrderService _orderService = OrderService();
  final EquipmentService _equipmentService = EquipmentService();
  final UserService _userService = UserService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadMessages();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    setState(() => _currentUserId = userId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final messages = await _chatService.getMessagesForChat(widget.chatId);
      setState(() {
        _messages = messages.reversed.toList();
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('chat.error'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    setState(() => _isSending = true);

    try {
      final message = MessageCreateModel(
        chatId: widget.chatId,
        messageText: content,
      );

      await _messageService.createMessage(message);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('chat.send_error'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  Widget _buildOrderIdBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryGreen, Color(0xFF2ECC71)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'order.id'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '#${widget.orderId}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _showOrderDetails(),
            icon: const Icon(Icons.visibility, size: 18),
            label: Text('order.view_details'.tr()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderDetails() async {
    try {
      // Buyurtma ma'lumotlarini yuklaymiz
      final orders = await _orderService.getOrders();
      final order = orders.firstWhere((o) => o.id == widget.orderId);

      // Texnika ma'lumotlarini yuklaymiz
      EquipmentModel? equipment;
      try {
        equipment = await _equipmentService.getEquipment(order.equipmentId);
      } catch (e) {
        equipment = null;
      }

      if (mounted) {
        _showOrderDetailsModal(order, equipment);
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.network'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  void _showOrderDetailsModal(OrderModel order, EquipmentModel? equipment) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'order.details'.tr(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Equipment info
                    if (equipment != null) ...[
                      Text(
                        'orders.equipment'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${equipment.type} ${equipment.model}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Dates
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'orders.start_date'.tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateFormat.format(order.startDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'orders.end_date'.tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateFormat.format(order.endDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Price details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildPriceRow(
                            'order.total_amount'.tr(),
                            '${NumberFormatter.formatCurrency(order.totalAmount)} ${'common.currency'.tr()}',
                          ),
                          const SizedBox(height: 8),
                          _buildPriceRow(
                            'Komissiya',
                            '${NumberFormatter.formatCurrency(order.commission)} ${'common.currency'.tr()}',
                          ),
                          if (order.deliveryFee != null && order.deliveryFee! > 0) ...[
                            const SizedBox(height: 8),
                            _buildPriceRow(
                              'Yetkazish (${order.deliveryDistance?.toStringAsFixed(1) ?? '0'} km)',
                              '${NumberFormatter.formatCurrency(order.deliveryFee!)} ${'common.currency'.tr()}',
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Delivery location map
                    Text(
                      'Yetkazish joyi',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Manzil (agar mavjud bo'lsa)
                    if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, size: 20, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                order.deliveryAddress!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Yandex Map
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          YandexMap(
                            onMapCreated: (controller) {
                              final deliveryLat = double.tryParse(order.deliveryLatitude);
                              final deliveryLng = double.tryParse(order.deliveryLongitude);

                              if (deliveryLat != null && deliveryLng != null) {
                                controller.moveCamera(
                                  CameraUpdate.newCameraPosition(
                                    CameraPosition(
                                      target: Point(latitude: deliveryLat, longitude: deliveryLng),
                                      zoom: 14,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                          // Marker in center
                          Center(
                            child: Icon(
                              Icons.location_on,
                              size: 48,
                              color: Colors.red,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withAlpha(100),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          // "Xaritada ochish" tugmasi
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              elevation: 2,
                              child: InkWell(
                                onTap: () => _openInMap(order),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.map, size: 18, color: AppColors.primaryGreen),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Xaritada ochish',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.primaryGreen,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _callOwner() async {
    try {
      // Avval buyurtma ma'lumotlarini yuklaymiz
      final orders = await _orderService.getOrders();
      final order = orders.firstWhere((o) => o.id == widget.orderId);

      // Equipment ma'lumotlarini yuklaymiz
      final equipment = await _equipmentService.getEquipment(order.equipmentId);

      // Owner ma'lumotlarini yuklaymiz
      final owner = await _userService.getUser(equipment.ownerId);

      if (owner.phone == null || owner.phone!.isEmpty) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text('errors.phone_not_available'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      final uri = Uri.parse('tel:${owner.phone}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flatColored,
            title: Text('errors.cannot_make_call'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.network'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _openInMap(OrderModel order) async {
    try {
      final deliveryLat = double.tryParse(order.deliveryLatitude);
      final deliveryLng = double.tryParse(order.deliveryLongitude);

      if (deliveryLat == null || deliveryLng == null) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text('errors.location_not_available'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      final availableMaps = await map_launcher.MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text('errors.no_maps_available'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      // Agar bitta xarita bo'lsa, to'g'ridan-to'g'ri ochish
      if (availableMaps.length == 1) {
        await availableMaps.first.showMarker(
          coords: map_launcher.Coords(deliveryLat, deliveryLng),
          title: 'orders.delivery_location'.tr(),
          description: order.deliveryAddress ?? '',
        );
        return;
      }

      // Ko'p xarita bo'lsa, tanlash dialogini ko'rsatish
      if (mounted) {
        await showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'orders.open_in_map'.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...availableMaps.map((map) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: SvgPicture.asset(
                        map.icon,
                        height: 30.0,
                        width: 30.0,
                      ),
                      title: Text(map.mapName),
                      onTap: () {
                        Navigator.pop(context);
                        map.showMarker(
                          coords: map_launcher.Coords(deliveryLat, deliveryLng),
                          title: 'orders.delivery_location'.tr(),
                          description: order.deliveryAddress ?? '',
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.cannot_open_map'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text('${'chat.order'.tr()} #${widget.orderId}'),
          backgroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.blue),
              tooltip: 'orders.call_owner'.tr(),
              onPressed: () => _callOwner(),
            ),
          ],
        ),
        body: Column(
          children: [
            // Order ID Banner
            _buildOrderIdBanner(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'chat.no_chats'.tr(),
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMe = _currentUserId != null && message.senderId == _currentUserId;

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe ? AppColors.primaryGreen : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.messageText,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('HH:mm').format(message.sentAt),
                                      style: TextStyle(
                                        color: isMe ? Colors.white70 : Colors.grey[600],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'chat.type_message'.tr(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppColors.primaryGreen),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
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
