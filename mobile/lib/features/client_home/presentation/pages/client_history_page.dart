import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:map_launcher/map_launcher.dart' as map_launcher;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/models/chat_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/number_formatter.dart';
import 'client_chat_page.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../../core/widgets/map_or_placeholder.dart';

class ClientHistoryPage extends StatefulWidget {
  const ClientHistoryPage({super.key});

  @override
  State<ClientHistoryPage> createState() => _ClientHistoryPageState();
}

class _ClientHistoryPageState extends State<ClientHistoryPage> {
  final OrderService _orderService = OrderService();
  final EquipmentService _equipmentService = EquipmentService();
  final UserService _userService = UserService();

  List<OrderModel> _orders = [];
  Map<int, EquipmentModel> _equipmentCache = {};
  Map<int, UserModel> _ownerCache = {};
  bool _isLoading = false;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);

    try {
      final orders = await _orderService.getOrders(limit: 100);

      // Buyurtmalarni yangilaridan eskisiga qarab tartiblash (created_at bo'yicha)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _orders = orders;
        _isLoading = false;
      });

      for (var order in orders) {
        // Equipment yuklash
        if (!_equipmentCache.containsKey(order.equipmentId)) {
          try {
            final equipment = await _equipmentService.getEquipment(order.equipmentId);
            setState(() {
              _equipmentCache[order.equipmentId] = equipment;
            });

            // Owner ma'lumotlarini yuklash (equipment.ownerId orqali)
            if (equipment.ownerId != null && !_ownerCache.containsKey(equipment.ownerId)) {
              try {
                final owner = await _userService.getUser(equipment.ownerId!);
                setState(() {
                  _ownerCache[equipment.ownerId!] = owner;
                });
              } catch (e) {
                // Ignore
              }
            }
          } catch (e) {
            // Ignore
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('orders.load_error'.tr()),
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

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return AppColors.primaryGreen;
      case 'completed':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'pending':
        return 'orders.status_pending'.tr();
      case 'confirmed':
        return 'orders.confirmed'.tr();
      case 'completed':
        return 'orders.status_completed'.tr();
      case 'rejected':
        return 'orders.rejected'.tr();
      case 'cancelled':
        return 'orders.status_canceled'.tr();
      default:
        return status;
    }
  }

  Future<void> _cancelOrder(OrderModel order) async {
    // Tasdiqlangan buyurtma uchun maxsus ogohlantirish
    String dialogContent;
    if (order.status == 'confirmed') {
      dialogContent = 'messages.cancel_confirmed_order_warning'.tr();
    } else {
      dialogContent = 'messages.cancel_order_question'.tr();
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('orders.cancel_order'.tr()),
        content: Text(dialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('orders.cancel_order'.tr()),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _orderService.updateOrderStatus(order.id, 'cancelled');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.flatColored,
          title: Text('messages.order_cancelled'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        _loadOrders();
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

  Future<void> _openInMaps(OrderModel order) async {
    try {
      final deliveryLat = double.tryParse(order.deliveryLatitude);
      final deliveryLng = double.tryParse(order.deliveryLongitude);

      if (deliveryLat == null || deliveryLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('errors.location_not_available'.tr())),
          );
        }
        return;
      }

      final availableMaps = await map_launcher.MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('errors.no_maps_available'.tr())),
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
          title: Text('messages.map_open_error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _callOwner(EquipmentModel? equipment) async {
    if (equipment == null || equipment.ownerId == null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('messages.owner_info_not_found'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    final owner = _ownerCache[equipment.ownerId];
    if (owner == null || owner.phone == null || owner.phone!.isEmpty) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('messages.owner_phone_not_found'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    try {
      final phoneUrl = Uri.parse('tel:${owner.phone}');
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
            builder: (_) => ClientChatDetailPage(
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
          title: Text('client.orders'.tr()),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
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
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                  : _filteredOrders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'orders.not_found'.tr(),
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadOrders,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredOrders.length,
                            itemBuilder: (context, index) {
                              final order = _filteredOrders[index];
                              final equipment = _equipmentCache[order.equipmentId];
                              return _buildOrderCard(order, equipment);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filterStatus = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order, EquipmentModel? equipment) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return GestureDetector(
      onTap: () => _showOrderDetails(order, equipment),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: equipment?.photos != null && equipment!.photos!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            equipment.photos!.first.url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                EquipmentTypeIcon(equipment.type, size: 34),
                          ),
                        )
                      : EquipmentTypeIcon(equipment?.type, size: 34),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text( 
                        equipment != null ? ' #${order.id} | ${EquipmentTypes.label(equipment.type)} ${equipment.model}' : 'orders.equipment'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _statusColor(order.status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusText(order.status),
                          style: TextStyle(
                            color: _statusColor(order.status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Colors.black12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'orders.start_date'.tr(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(order.startDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black,
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(order.endDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'orders.total_price'.tr(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${NumberFormatter.formatCurrency(order.totalAmount)} ${'common.currency'.tr()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
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
                        'equipment.title'.tr(),
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
                            'order.total_amount'.tr(),
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
                    Stack(
                      children: [
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: MapOrPlaceholder(mapBuilder: (_) => YandexMap(
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
                            mapObjects: [
                              PlacemarkMapObject(
                                mapId: const MapObjectId('delivery_location'),
                                point: Point(
                                  latitude: double.tryParse(order.deliveryLatitude) ?? 0,
                                  longitude: double.tryParse(order.deliveryLongitude) ?? 0,
                                ),
                                opacity: 1.0,
                                icon: PlacemarkIcon.single(
                                  PlacemarkIconStyle(
                                    image: BitmapDescriptor.fromAssetImage('assets/my_location.png'),
                                    scale: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          )),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            elevation: 2,
                            child: InkWell(
                              onTap: () => _openInMaps(order),
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
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryGreen,
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
                    
                    const SizedBox(height: 20),

                    // Egasi bilan aloqa va Chat tugmalari
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _callOwner(equipment),
                            icon: const Icon(Icons.phone),
                            label: Text('messages.call_owner'.tr()),
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

                    // Buyurtmani bekor qilish tugmasi (faqat pending yoki confirmed uchun)
                    if (order.status == 'pending' || order.status == 'confirmed') ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _cancelOrder(order);
                          },
                          icon: const Icon(Icons.cancel),
                          label: Text('orders.cancel_order'.tr()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
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
