import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/widgets/date_range_calendar.dart';
import '../../../../core/constants/equipment_types.dart';

class RentEquipmentPage extends StatefulWidget {
  final EquipmentModel equipment;

  const RentEquipmentPage({
    super.key,
    required this.equipment,
  });

  @override
  State<RentEquipmentPage> createState() => _RentEquipmentPageState();
}

class _RentEquipmentPageState extends State<RentEquipmentPage> {
  final OrderService _orderService = OrderService();
  final BalanceService _balanceService = BalanceService();
  final GeocodingService _geocodingService = GeocodingService();
  final EquipmentService _equipmentService = EquipmentService();

  DateTime? _startDate;
  DateTime? _endDate;
  Point? _selectedLocation; // Tanlangan yetkazib berish joyi
  String? _deliveryAddress; // Yetkazib berish manzili
  bool _isLoading = false;
  bool _isLoadingBookedDates = false;
  BalanceModel? _balance;
  List<DateTimeRange> _bookedRanges = [];

  int get _totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  int get _dailyRate {
    // pricePerDay String formatida keladi, masalan: "150000.0" yoki "150000"
    final priceStr = widget.equipment.pricePerDay;

    // Agar String bo'sh bo'lsa, 0 qaytaramiz
    if (priceStr.isEmpty) return 0;

    // Agar String ichida nuqta bo'lsa (masalan: "150000.0"), double ga parse qilib, int ga aylantiramiz
    if (priceStr.contains('.')) {
      return double.tryParse(priceStr)?.toInt() ?? 0;
    }

    // Aks holda, to'g'ridan-to'g'ri int ga parse qilamiz
    return int.tryParse(priceStr) ?? 0;
  }

  int get _subtotal {
    return _dailyRate * _totalDays;
  }

  int get _commission {
    return (_subtotal * 0.1).round(); // 10% komissiya
  }

  // Masofa hisoblash (km)
  double? get _deliveryDistance {
    if (_selectedLocation == null ||
        widget.equipment.latitude == null ||
        widget.equipment.longitude == null) {
      return null;
    }

    final equipLat = double.tryParse(widget.equipment.latitude!);
    final equipLng = double.tryParse(widget.equipment.longitude!);

    if (equipLat == null || equipLng == null) return null;

    return _calculateDistance(
      equipLat,
      equipLng,
      _selectedLocation!.latitude,
      _selectedLocation!.longitude,
    );
  }

  // Yetkazish narxi
  int get _deliveryFee {
    if (_deliveryDistance == null ||
        widget.equipment.deliveryPricePerKm == null ||
        widget.equipment.deliveryPricePerKm!.isEmpty) {
      return 0;
    }

    final pricePerKm = double.tryParse(widget.equipment.deliveryPricePerKm!) ?? 0;
    return (_deliveryDistance! * pricePerKm).round();
  }

  int get _total {
    return _subtotal + _commission + _deliveryFee;
  }

  // Haversine formula - masofa hisoblash
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  @override
  void initState() {
    super.initState();
    _loadBookedDates();
    _loadBalance();
  }

  // Band sanalarni yuklash
  Future<void> _loadBookedDates() async {
    setState(() {
      _isLoadingBookedDates = true;
    });

    try {
      final result = await _equipmentService.getBookedDates(widget.equipment.id);
      final bookedRanges = result['booked_ranges'] as List;

      setState(() {
        _bookedRanges = bookedRanges.map((range) {
          return DateTimeRange(
            start: DateTime.parse(range['start_date']),
            end: DateTime.parse(range['end_date']),
          );
        }).toList();
        _isLoadingBookedDates = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBookedDates = false;
      });

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

  Future<void> _loadBalance() async {
    try {
      _balance = await _balanceService.getBalance();
      setState(() {});
    } catch (e) {
      // Balans yuklanmasa ham davom etamiz
    }
  }

  // Tasdiqlash dialog'ini ko'rsatish
  Future<bool?> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.help_outline, color: AppColors.primaryGreen, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Buyurtma berish',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Haqiqatdan ham buyurtma berasizmi?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfirmationRow(
                    Icons.calendar_today,
                    'Sana',
                    '${DateFormat('dd.MM.yyyy').format(_startDate!)} - ${DateFormat('dd.MM.yyyy').format(_endDate!)}',
                  ),
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                    Icons.access_time,
                    'Davomiyligi',
                    '$_totalDays kun',
                  ),
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                    Icons.location_on,
                    'Manzil',
                    _deliveryAddress ?? 'Tanlangan',
                  ),
                  const Divider(height: 24),
                  _buildConfirmationRow(
                    Icons.payments,
                    'Jami to\'lov',
                    '${NumberFormatter.formatCurrency(_total)} ${'common.currency'.tr()}',
                    isTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '💡 Pul hisobingizdan muzlatiladi va buyurtma tugagandan keyin egaga o\'tkaziladi.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Bekor qilish',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Ha, buyurtma beraman',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationRow(IconData icon, String label, String value, {bool isTotal = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isTotal ? AppColors.primaryGreen : Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              color: Colors.grey[700],
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? AppColors.primaryGreen : Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  // Calendar dialog'ni ko'rsatish
  Future<void> _showDateRangeCalendar() async {
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sana oralig\'ini tanlang',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (tempStart != null && tempEnd != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tempStart!.isAtSameMomentAs(tempEnd!)
                          ? '${DateFormat('dd.MM.yyyy').format(tempStart!)} (1 kun)'
                          : '${DateFormat('dd.MM.yyyy').format(tempStart!)} - ${DateFormat('dd.MM.yyyy').format(tempEnd!)} (${tempEnd!.difference(tempStart!).inDays + 1} kun)',
                      style: TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                DateRangeCalendar(
                  bookedRanges: _bookedRanges,
                  initialStartDate: _startDate,
                  initialEndDate: _endDate,
                  onDateRangeSelected: (start, end) {
                    setDialogState(() {
                      tempStart = start;
                      tempEnd = end;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Bekor qilish'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: tempStart != null && tempEnd != null
                          ? () {
                              setState(() {
                                _startDate = tempStart;
                                _endDate = tempEnd;
                              });
                              Navigator.pop(context);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                      ),
                      child: Text('Tanlash'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLocationPicker() async {
    final result = await showModalBottomSheet<Point>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _LocationPickerBottomSheet(
        initialLocation: _selectedLocation ?? const Point(latitude: 41.2995, longitude: 69.2401), // Toshkent
      ),
    );

    if (result != null) {
      setState(() {
        _selectedLocation = result;
        _deliveryAddress = null; // Reset address
      });

      // Reverse geocoding - manzilni olish
      try {
        final address = await _geocodingService.getAddressFromCoordinates(
          result.latitude,
          result.longitude,
        );

        if (address != null && mounted) {
          setState(() {
            _deliveryAddress = address;
          });
        }
      } catch (e) {
        print('Reverse geocoding error: $e');
      }
    }
  }

  Future<void> _confirmBooking() async {
    // Sana va lokatsiya majburiy
    if (_startDate == null || _endDate == null) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('messages.select_dates'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    if (_selectedLocation == null) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('messages.select_delivery_location'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    // Band sanalar bilan to'qnashuvni tekshirish
    for (var range in _bookedRanges) {
      if (!(_endDate!.isBefore(range.start) || _startDate!.isAfter(range.end))) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('Bu sana oralig\'ida texnika band'),
          autoCloseDuration: const Duration(seconds: 4),
          alignment: Alignment.topCenter,
        );
        return;
      }
    }

    if (_endDate!.isBefore(_startDate!)) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('rent.end_date_error'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    // Tasdiqlash dialog'ini ko'rsatish
    final confirmed = await _showConfirmationDialog();
    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Balansni tekshirish
      _balance = await _balanceService.getBalance();

      final totalAmount = _total.toDouble();
      final availableBalance = _balance!.availableBalance;

      // 2. Pul yetarli emasligini tekshirish
      if (availableBalance < totalAmount) {
        setState(() => _isLoading = false);

        // Pul yetmasa, dialog ko'rsatish
        if (mounted) {
          _showInsufficientBalanceDialog(availableBalance, totalAmount);
        }
        return;
      }

      // 3. Order yaratish (userId va status backend o'zi qo'shadi)
      final order = OrderCreateModel(
        equipmentId: widget.equipment.id,
        startDate: _startDate!,
        endDate: _endDate!,
        totalAmount: totalAmount,
        commission: _commission.toDouble(),
        deliveryLatitude: _selectedLocation!.latitude.toString(),
        deliveryLongitude: _selectedLocation!.longitude.toString(),
        deliveryAddress: _deliveryAddress, // Reverse geocoding orqali olingan manzil
        deliveryDistance: _deliveryDistance,
        deliveryFee: _deliveryFee > 0 ? _deliveryFee.toDouble() : null,
      );

      await _orderService.createOrder(order);

      setState(() => _isLoading = false);

      // 5. Muvaffaqiyatli dialog ko'rsatish
      if (mounted) {
        _showSuccessDialog(totalAmount);
      }
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        // Backend xatoligini ko'rsatish
        showErrorDialog(context, e);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('rent.booking_error'.tr())),
        );
      }
    }
  }

  void _showSuccessDialog(double totalAmount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.primaryGreen,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'messages.order_sent_successfully'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Amount info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Muzlatilgan summa:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        '${NumberFormatter.formatCurrency(totalAmount)} so\'m',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info text
            Text(
              'messages.order_confirm_deduction'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          // Buyurtmalarim bo'limiga o'tish
          // TextButton(
          //   onPressed: () {
          //     Navigator.pop(context); // Dialog yopish
          //     context.pop(true); // Rent page yopish
          //     // Buyurtmalarim tab'iga o'tish (index 2)
          //     // Bu yerda main page'dagi tab controller'ni o'zgartirish kerak
          //   },
          //   child: Text(
          //     'Buyurtmalarimga o\'tish',
          //     style: TextStyle(
          //       color: AppColors.primaryGreen,
          //       fontWeight: FontWeight.w600,
          //     ),
          //   ),
          // ),

          // OK tugmasi
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Dialog yopish
              context.pop(true); // Rent page yopish
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(
              'common.ok'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInsufficientBalanceDialog(double availableBalance, double requiredAmount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('messages.insufficient_balance'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'messages.available_balance'.tr()}: ${NumberFormatter.formatCurrency(availableBalance)} so\'m'),
            Text('${'messages.required_amount'.tr()}: ${NumberFormatter.formatCurrency(requiredAmount)} so\'m'),
            const SizedBox(height: 8),
            Text(
              'messages.topup_balance_title'.tr(),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Kerakli summani parametr sifatida o'tkazish
              final neededAmount = requiredAmount - availableBalance;
              context.push('/balance-topup', extra: neededAmount);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text(
              'balance.topup'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

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
          title: Text('rent.title'.tr()),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Equipment Info Card - Chiroyli
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey[200]!, width: 1),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            AppColors.primaryGreen.withOpacity(0.02),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Rasm container - kattaroq va chiroyliroq
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primaryGreen.withOpacity(0.2),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: widget.equipment.photos.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.network(
                                        widget.equipment.photos.first.url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Icon(Icons.construction, size: 40, color: AppColors.primaryGreen),
                                      ),
                                    )
                                  : Icon(Icons.construction, size: 40, color: AppColors.primaryGreen),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Texnika nomi
                                  Text(
                                    '${EquipmentTypes.label(widget.equipment.type)} ${widget.equipment.model}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  // Kunlik narx - badge ko'rinishida
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryGreen.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.payments, color: Colors.white, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$_dailyRate ${'common.currency'.tr()}/${'common.day'.tr()}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Yetkazish narxi
                                  if (widget.equipment.deliveryPricePerKm != null && widget.equipment.deliveryPricePerKm!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.local_shipping, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${widget.equipment.deliveryPricePerKm} so\'m/km',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Date Selection
                  Text(
                    'rent.select_dates'.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sana tanlash card - joylashuv bilan bir xil
                  InkWell(
                    onTap: _showDateRangeCalendar,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _startDate != null ? AppColors.primaryGreen : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: _startDate != null ? AppColors.primaryGreen : Colors.grey[600],
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _startDate != null && _endDate != null
                                      ? 'Sana tanlandi'
                                      : 'Sana oralig\'ini tanlang',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _startDate != null ? AppColors.primaryGreen : Colors.grey[700],
                                  ),
                                ),
                                if (_startDate != null && _endDate != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${DateFormat('dd.MM.yyyy').format(_startDate!)} - ${DateFormat('dd.MM.yyyy').format(_endDate!)} ($_totalDays kun)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.grey[400],
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location Selection
                  Text(
                    'Yetkazib berish joyi',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _showLocationPicker,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedLocation != null ? AppColors.primaryGreen : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: _selectedLocation != null ? AppColors.primaryGreen : Colors.grey[600],
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedLocation != null
                                      ? 'Joylashuv tanlandi'
                                      : 'Joylashuvni tanlang',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedLocation != null ? AppColors.primaryGreen : Colors.grey[700],
                                  ),
                                ),
                                if (_selectedLocation != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _deliveryAddress ?? '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.grey[400],
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Price Calculation
                  if (_totalDays > 0) ...[
                    Text(
                      'rent.price_calculation'.tr(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildPriceRow(
                              'rent.daily_rate'.tr(),
                              '${NumberFormatter.formatCurrency(_dailyRate)} ${'common.currency'.tr()}',
                            ),
                            const SizedBox(height: 8),
                            _buildPriceRow(
                              'rent.total_days'.tr(),
                              '$_totalDays ${'rent.days'.tr()}',
                            ),
                            const Divider(height: 24),
                            _buildPriceRow(
                              'rent.subtotal'.tr(),
                              '${NumberFormatter.formatCurrency(_subtotal)} ${'common.currency'.tr()}',
                            ),
                            const SizedBox(height: 8),
                            _buildPriceRow(
                              'rent.commission'.tr() + ' (10%)',
                              '${NumberFormatter.formatCurrency(_commission)} ${'common.currency'.tr()}',
                            ),
                            // Yetkazish narxi
                            if (_deliveryFee > 0) ...[
                              const SizedBox(height: 8),
                              _buildPriceRow(
                                'Yetkazish (${_deliveryDistance!.toStringAsFixed(1)} km)',
                                '${NumberFormatter.formatCurrency(_deliveryFee)} ${'common.currency'.tr()}',
                              ),
                            ],
                            const Divider(height: 24),
                            _buildPriceRow(
                              'rent.total'.tr(),
                              '${NumberFormatter.formatCurrency(_total)} ${'common.currency'.tr()}',
                              isTotal: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Bottom Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading || _totalDays == 0 ? null : _confirmBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'rent.confirm_booking'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: date != null ? AppColors.primaryGreen : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  date != null ? dateFormat.format(date) : 'common.select'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: date != null ? Colors.black87 : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 18 : 16,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.black : Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: isTotal ? AppColors.primaryGreen : Colors.black87,
          ),
        ),
      ],
    );
  }
}

// Location Picker BottomSheet Widget
class _LocationPickerBottomSheet extends StatefulWidget {
  final Point initialLocation;

  const _LocationPickerBottomSheet({required this.initialLocation});

  @override
  State<_LocationPickerBottomSheet> createState() => _LocationPickerBottomSheetState();
}

class _LocationPickerBottomSheetState extends State<_LocationPickerBottomSheet> {
  late YandexMapController _mapController;
  late Point _selectedPoint;
  Point? _currentUserLocation;
  bool _isLoadingLocation = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation;
    _requestLocationPermissionAndGetLocation();
  }

  Future<void> _requestLocationPermissionAndGetLocation() async {
    try {
      // Agar avval tanlangan joylashuv bo'lsa (initialLocation Toshkent emas)
      bool hasInitialLocation = widget.initialLocation.latitude != 41.2995 ||
                                widget.initialLocation.longitude != 69.2401;

      if (hasInitialLocation) {
        // Avval tanlangan joylashuv bor - uni ko'rsatamiz
        setState(() {
          _selectedPoint = widget.initialLocation;
          _isLoadingLocation = false;
        });

        // Xarita tayyor bo'lsa, tanlangan joyga o'tish
        if (_mapReady) {
          _moveToLocation(_selectedPoint);
        }
        return;
      }

      // Avval tanlangan joylashuv yo'q - joriy joylashuvni olamiz
      // Permission tekshirish va so'rash
      final permissionResult = await PermissionService.requestLocationPermission();

      if (!permissionResult.isGranted) {
        setState(() => _isLoadingLocation = false);
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text(permissionResult.errorMessage ?? 'messages.location_permission_not_granted_message'.tr()),
            autoCloseDuration: const Duration(seconds: 5),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      // Joriy joylashuvni olish
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _currentUserLocation = Point(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _selectedPoint = _currentUserLocation!;
        _isLoadingLocation = false;
      });

      // Xarita tayyor bo'lsa, kameraga o'tish
      if (_mapReady) {
        _moveToLocation(_currentUserLocation!);
      }
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      print('Get location error: $e');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('messages.location_error_message'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  // Xarita kamera pozitsiyasi o'zgarganda chaqiriladi
  void _onCameraPositionChanged(CameraPosition position, CameraUpdateReason reason, bool finished) {
    if (finished) {
      // Xarita to'xtaganda markaziy nuqtani yangilaymiz
      setState(() {
        _selectedPoint = position.target;
      });
    }
  }

  Future<void> _moveToLocation(Point point, {double zoom = 17}) async {
    await _mapController.moveCamera(
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1),
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: zoom),
      ),
    );
  }

  Future<void> _zoomIn() async {
    await _mapController.moveCamera(
      CameraUpdate.zoomIn(),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  Future<void> _zoomOut() async {
    await _mapController.moveCamera(
      CameraUpdate.zoomOut(),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  void _goToMyLocation() {
    if (_currentUserLocation != null) {
      _moveToLocation(_currentUserLocation!, zoom: 17);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Swipe bilan yopilmasligi uchun
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(width: 12),
                   Expanded(
                    child: Text(
                      'equipment.select_location'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Map
            Expanded(
              child: _isLoadingLocation
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.primaryGreen),
                          SizedBox(height: 16),
                          Text('messages.detecting_location'.tr()),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        YandexMap(
                          onMapCreated: (controller) async {
                            _mapController = controller;
                            setState(() => _mapReady = true);

                            // Agar location tayyor bo'lsa, darhol o'tish
                            if (_currentUserLocation != null) {
                              await _moveToLocation(_currentUserLocation!, zoom: 17);
                            } else {
                              await _moveToLocation(_selectedPoint, zoom: 17);
                            }
                          },
                          onCameraPositionChanged: _onCameraPositionChanged,
                        ),

                        // Markazda qotib turgan marker
                        Center(
                          child: Icon(
                            Icons.location_on,
                            size: 48,
                            color: Colors.red,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),

                        // Zoom controls
                        Positioned(
                          right: 16,
                          bottom: 100,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                heroTag: 'zoom_in',
                                onPressed: _zoomIn,
                                backgroundColor: Colors.white,
                                child: const Icon(Icons.add, color: Colors.black87),
                              ),
                              const SizedBox(height: 8),
                              FloatingActionButton.small(
                                heroTag: 'zoom_out',
                                onPressed: _zoomOut,
                                backgroundColor: Colors.white,
                                child: const Icon(Icons.remove, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),

                        // My location button
                        if (_currentUserLocation != null)
                          Positioned(
                            right: 16,
                            bottom: 200,
                            child: FloatingActionButton.small(
                              heroTag: 'my_location',
                              onPressed: _goToMyLocation,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.my_location, color: AppColors.primaryGreen),
                            ),
                          ),
                      ],
                    ),
            ),

            // Confirm button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedPoint),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'common.confirm'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

