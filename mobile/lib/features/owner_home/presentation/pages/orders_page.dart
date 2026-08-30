import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dio/dio.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/models/chat_model.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/number_formatter.dart';
import 'chat_page.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final OrderService _orderService = OrderService();
  final EquipmentService _equipmentService = EquipmentService();
  final UserService _userService = UserService();

  List<OrderModel> _orders = [];
  final Map<int, EquipmentModel> _equipmentCache = {};
  final Map<int, UserModel> _userCache = {};
  bool _isLoading = true;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      setState(() => _isLoading = true);

      final orders = await _orderService.getOrders();

      // Buyurtmalarni yangilaridan eskisiga qarab tartiblash (created_at bo'yicha)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Equipment va User ma'lumotlarini yuklaymiz
      for (var order in orders) {
        // Equipment yuklash
        if (!_equipmentCache.containsKey(order.equipmentId)) {
          try {
            final equipment = await _equipmentService.getEquipment(order.equipmentId);
            _equipmentCache[order.equipmentId] = equipment;
          } catch (e) {
            print('Load equipment ${order.equipmentId} error: $e');
          }
        }

        // User yuklash
        if (!_userCache.containsKey(order.userId)) {
          try {
            final user = await _userService.getUser(order.userId);
            _userCache[order.userId] = user;
          } catch (e) {
            print('Load user ${order.userId} error: $e');
          }
        }
      }

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      print('Load orders error: $e');
      setState(() => _isLoading = false);
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

  List<OrderModel> get _filteredOrders {
    if (_filterStatus == 'all') return _orders;
    return _orders.where((order) => order.status == _filterStatus).toList();
  }

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = status;
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

  Future<void> _confirmOrder(OrderModel order) async {
    // Tasdiqlash dialogi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('messages.confirm_order'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('messages.confirm_order_question'.tr()),
            const SizedBox(height: 8),
            Text('${'messages.amount'.tr()}: ${order.totalAmount.toStringAsFixed(0)} ${'common.currency'.tr()}'),
            const SizedBox(height: 4),
            Text(
              'messages.frozen_money_transferred'.tr(),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text(
              'messages.confirm'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _orderService.updateOrderStatus(order.id, 'confirmed');

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.flatColored,
          title: Text('messages.order_confirmed'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        _loadOrders();
      }
    } on DioException catch (e) {
      if (mounted) {
        showErrorDialog(context, e);
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _rejectOrder(OrderModel order) async {
    // Rad etish dialogi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('messages.reject_order'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('messages.reject_order_question'.tr()),
            const SizedBox(height: 8),
            Text(
              'messages.frozen_money_returned'.tr(),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(
              'messages.reject'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _orderService.updateOrderStatus(order.id, 'rejected');

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          style: ToastificationStyle.flatColored,
          title: Text('messages.order_rejected'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        _loadOrders();
      }
    } on DioException catch (e) {
      if (mounted) {
        showErrorDialog(context, e);
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _completeOrder(OrderModel order) async {
    // Yakunlash dialogi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('messages.complete_order'.tr()),
        content: Text('messages.complete_order_question'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text(
              'messages.complete'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _orderService.updateOrderStatus(order.id, 'completed');

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.flatColored,
          title: Text('messages.order_completed'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        _loadOrders();
      }
    } on DioException catch (e) {
      if (mounted) {
        showErrorDialog(context, e);
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'confirmed':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'cancelled':
        return Icons.block;
      case 'completed':
        return Icons.done_all;
      default:
        return Icons.info;
    }
  }

  Future<void> _callClient(OrderModel order) async {
    try {
      final user = _userCache[order.userId];

      if (user == null || user.phone == null || user.phone!.isEmpty) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text('messages.client_phone_not_found'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      final phoneUrl = Uri.parse('tel:+${user.phone}');

      if (await canLaunchUrl(phoneUrl)) {
        await launchUrl(phoneUrl);
      } else {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flatColored,
            title: Text('messages.cannot_make_call'.tr()),
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
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _openChat(OrderModel order) async {
    try {
      final chatService = ChatService();

      // Buyurtma uchun chat mavjudligini tekshirish
      final chats = await chatService.getChats();
      ChatModel? existingChat;

      for (var chat in chats) {
        if (chat.orderId == order.id) {
          existingChat = chat;
          break;
        }
      }

      // Agar chat mavjud bo'lmasa, yangi chat yaratish
      if (existingChat == null) {
        existingChat = await chatService.createChat(
          ChatCreateModel(orderId: order.id),
        );
      }

      // Chat sahifasiga o'tish
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              chatId: existingChat!.id,
              orderId: order.id,
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
          title: Text('messages.chat_open_error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  /// Navigatorda marshrut quradi.
  ///
  /// _openInMap faqat nuqtani ko'rsatadi; egaga esa u yergacha QANDAY
  /// borishni bilish kerak, shuning uchun alohida tugma.
  Future<void> _buildRoute(OrderModel order) async {
    final lat = double.tryParse(order.deliveryLatitude);
    final lng = double.tryParse(order.deliveryLongitude);
    if (lat == null || lng == null) {
      _mapToast('messages.location_not_found'.tr());
      return;
    }

    try {
      final maps = await MapLauncher.installedMaps;
      if (maps.isEmpty) {
        _mapToast('messages.no_map_app'.tr());
        return;
      }
      await maps.first.showDirections(
        destination: Coords(lat, lng),
        destinationTitle: order.deliveryAddress ?? 'orders.delivery_location'.tr(),
      );
    } catch (_) {
      _mapToast('errors.cannot_open_map'.tr());
    }
  }

  void _mapToast(String text) {
    if (!mounted) return;
    toastification.show(
      context: context,
      type: ToastificationType.warning,
      style: ToastificationStyle.flatColored,
      title: Text(text),
      autoCloseDuration: const Duration(seconds: 3),
      alignment: Alignment.topCenter,
    );
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
            title: Text('messages.location_not_found'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      final availableMaps = await MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text('messages.no_map_app'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      // Agar bitta xarita bo'lsa, to'g'ridan-to'g'ri ochish
      if (availableMaps.length == 1) {
        await availableMaps.first.showMarker(
          coords: Coords(deliveryLat, deliveryLng),
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
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 12),
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
                          coords: Coords(deliveryLat, deliveryLng),
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
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text('orders.title'.tr()),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'common.all'.tr()),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'orders.status_pending'.tr()),
                  const SizedBox(width: 8),
                  _buildFilterChip('confirmed', 'orders.confirmed'.tr()),
                  const SizedBox(width: 8),
                  _buildFilterChip('completed', 'orders.status_completed'.tr()),
                  const SizedBox(width: 8),
                  _buildFilterChip('rejected', 'orders.rejected'.tr()),
                  const SizedBox(width: 8),
                  _buildFilterChip('cancelled', 'orders.status_canceled'.tr()),
                ],
              ),
            ),
          ),
          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                : _filteredOrders.isEmpty
                    ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.power_rounded, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'orders.no_orders'.tr(),
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return ListView.builder(
                              padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 80),
                              itemCount: _filteredOrders.length,
                              itemBuilder: (context, index) {
                                final order = _filteredOrders[index];
                        final equipment = _equipmentCache[order.equipmentId];

                        Color statusColor;
                        String statusText;

                        switch (order.status) {
                          case 'pending':
                            statusColor = Colors.orange;
                            statusText = 'orders.pending'.tr();
                            break;
                          case 'confirmed':
                            statusColor = Colors.green;
                            statusText = 'orders.confirmed'.tr();
                            break;
                          case 'rejected':
                            statusColor = Colors.red;
                            statusText = 'orders.rejected'.tr();
                            break;
                          case 'cancelled':
                            statusColor = Colors.red;
                            statusText = 'orders.canceled'.tr();
                            break;
                          case 'completed':
                            statusColor = Colors.grey;
                            statusText = 'orders.completed'.tr();
                            break;
                          default:
                            statusColor = Colors.blue;
                            statusText = order.status;
                        }

                        // startDate — bu SANA, soati yo'q: 'HH:mm' doim
                        // 00:00 chiqarardi va hech qanday ma'no bermasdi.
                        final dateFormat = DateFormat('dd.MM.yyyy');
                        final dateStr = dateFormat.format(order.startDate);

                        return GestureDetector(
                          onTap: () => _showOrderDetails(order, equipment),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Status banner
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getStatusIcon(order.status),
                                        size: 18,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Main content
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: EquipmentTypeIcon(
                                              equipment?.type,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  equipment != null
                                                      ? '#${order.id} | ${EquipmentTypes.label(equipment.type)} ${equipment.model}'
                                                      : '${'orders.equipment'.tr()} #${order.equipmentId}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      // Ism _userCache'da bor — ilgari u yuklanardi,
                                                      // lekin ekranga chiqmasdi va ega mijozning
                                                      // o'rniga "Foydalanuvchi #19" ko'rardi.
                                                      _userCache[order.userId]?.fullName ??
                                                          '${'orders.user'.tr()} #${order.userId}',
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            onSelected: (value) {
                                              switch (value) {
                                                case 'confirm':
                                                  if (order.status == 'pending') {
                                                    _confirmOrder(order);
                                                  }
                                                  break;
                                                case 'reject':
                                                  if (order.status == 'pending') {
                                                    _rejectOrder(order);
                                                  }
                                                  break;
                                                case 'complete':
                                                  if (order.status == 'confirmed') {
                                                    _completeOrder(order);
                                                  }
                                                  break;
                                              }
                                            },
                                            itemBuilder: (context) {
                                              List<PopupMenuEntry<String>> items = [];

                                              if (order.status == 'pending') {
                                                items.add(
                                                  PopupMenuItem(
                                                    value: 'confirm',
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                                        const SizedBox(width: 8),
                                                        Text('orders.confirm'.tr()),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                                items.add(
                                                  PopupMenuItem(
                                                    value: 'reject',
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.cancel, color: Colors.red, size: 20),
                                                        const SizedBox(width: 8),
                                                        Text('orders.reject'.tr()),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }

                                              if (order.status == 'confirmed') {
                                                items.add(
                                                  PopupMenuItem(
                                                    value: 'complete',
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.done_all, color: Colors.blue, size: 20),
                                                        const SizedBox(width: 8),
                                                        Text('orders.complete'.tr()),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }

                                              if (items.isEmpty) {
                                                items.add(
                                                  PopupMenuItem(
                                                    enabled: false,
                                                    child: Text(
                                                      'Hech qanday amal yo\'q',
                                                      style: TextStyle(color: Colors.grey[600]),
                                                    ),
                                                  ),
                                                );
                                              }

                                              return items;
                                            },
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),

                                      // Price and details
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'orders.amount'.tr(),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${NumberFormatter.formatCurrency(order.totalAmount)} ${'common.currency'.tr()}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: AppColors.primaryGreen,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (order.deliveryAddress != null)
                                            Expanded(
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      order.deliveryAddress!,
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
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
                      },
                    );
                  },
                ),
              ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(OrderModel order, EquipmentModel? equipment) {
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
                        'orders.details'.tr(),
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
                        '${EquipmentTypes.label(equipment.type)} ${equipment.model}',
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
                            'orders.total'.tr(),
                            '${NumberFormatter.formatCurrency(order.totalAmount)} ${'common.currency'.tr()}',
                          ),
                          const SizedBox(height: 8),
                          _buildPriceRow(
                            'rent.commission'.tr(),
                            '${NumberFormatter.formatCurrency(order.commission)} ${'common.currency'.tr()}',
                          ),
                          if (order.deliveryFee != null && order.deliveryFee! > 0) ...[
                            const SizedBox(height: 8),
                            _buildPriceRow(
                              "${'equipment.delivery'.tr()} (${order.deliveryDistance?.toStringAsFixed(1) ?? '0'} ${'common.km'.tr()})",
                              '${NumberFormatter.formatCurrency(order.deliveryFee!)} ${'common.currency'.tr()}',
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Delivery location map
                    Text(
                      'orders.delivery_location'.tr(),
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
                            left: 8,
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              elevation: 2,
                              child: InkWell(
                                onTap: () => _buildRoute(order),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.directions,
                                          size: 18, color: AppColors.primaryGreen),
                                      const SizedBox(width: 4),
                                      Text(
                                        'orders.build_route'.tr(),
                                        style: const TextStyle(
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
                                        'orders.open_in_map'.tr(),
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

                    const SizedBox(height: 20),

                    // Qo'ng'iroq qilish va Chat tugmalari
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _callClient(order),
                            icon: const Icon(Icons.phone),
                            label: Text('orders.call_client'.tr()),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.blue),
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openChat(order),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text('chat.open_chat'.tr()),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: AppColors.primaryGreen),
                              foregroundColor: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Buyurtmani boshqarish tugmalari
                    if (order.status == 'pending') ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _rejectOrder(order);
                              },
                              icon: const Icon(Icons.cancel),
                              label: Text('orders.reject_order'.tr()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _confirmOrder(order);
                              },
                              icon: const Icon(Icons.check_circle),
                              label: Text('orders.accept_order'.tr()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Yakunlash tugmasi (faqat confirmed buyurtmalar uchun)
                    if (order.status == 'confirmed') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _completeOrder(order);
                          },
                          icon: const Icon(Icons.done_all),
                          label: Text('orders.complete_order'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
}
