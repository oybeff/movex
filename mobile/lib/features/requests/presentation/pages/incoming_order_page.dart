import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/models/equipment_request_model.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../../core/widgets/map_or_placeholder.dart';

/// "Yangi buyurtma" — tez buyurtma egaga shu ekran bilan keladi.
///
/// Kim birinchi suring (swipe) qilsa, buyurtma o'shaniki: server zayavkani
/// qulflaydi, kech qolganga 409 qaytaradi. Mijozning ismi va telefoni bu
/// yerda YO'Q — ular olgandan keyin buyurtmada ochiladi.
///
/// Natija: `true` — ega oldi (chaqiruvchi "Buyurtmalar"ga o'tkazadi),
/// `false`/null — rad etdi yoki yopdi.
class IncomingOrderPage extends StatefulWidget {
  const IncomingOrderPage({super.key, required this.order});

  final QuickIncomingModel order;

  @override
  State<IncomingOrderPage> createState() => _IncomingOrderPageState();
}

class _IncomingOrderPageState extends State<IncomingOrderPage> {
  static const _blue = Color(0xFF2D8CF0);
  static const _green = Color(0xFF16A34A);

  final EquipmentRequestService _service = EquipmentRequestService();
  bool _busy = false;

  QuickIncomingModel get o => widget.order;

  String _money(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await _service.quickAccept(o.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('requests.quick_accepted'.tr())),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      int? status;
      String? detail;
      try {
        status = (e as dynamic).response?.statusCode as int?;
        final data = (e as dynamic).response?.data;
        if (data is Map && data['detail'] is String) detail = data['detail'] as String;
      } catch (_) {}
      setState(() => _busy = false);
      final text = status == 409
          ? 'requests.quick_taken'.tr()
          : (detail ?? 'errors.something_went_wrong'.tr());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      if (status == 409) Navigator.of(context).pop(false);
    }
  }

  Future<void> _decline() async {
    try {
      await _service.quickDecline(o.id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final point = Point(latitude: o.deliveryLatitude, longitude: o.deliveryLongitude);
    final start = DateFormat('dd.MM').format(o.startDate);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ------------------------------------------------ xarita
          Positioned.fill(
            bottom: MediaQuery.of(context).size.height * 0.42,
            child: MapOrPlaceholder(
              mapBuilder: (_) => YandexMap(
                onMapCreated: (controller) => controller.moveCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: point, zoom: 14),
                  ),
                ),
                mapObjects: [
                  CircleMapObject(
                    mapId: const MapObjectId('point_halo'),
                    circle: Circle(center: point, radius: 120),
                    fillColor: _blue.withValues(alpha: 0.18),
                    strokeColor: Colors.transparent,
                  ),
                  CircleMapObject(
                    mapId: const MapObjectId('point'),
                    zIndex: 1,
                    circle: Circle(center: point, radius: 28),
                    fillColor: _blue,
                    strokeColor: Colors.white,
                    strokeWidth: 3,
                  ),
                ],
              ),
            ),
          ),

          // ------------------------------------------------ yuqori qator
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  _round(
                    child: const Icon(Icons.arrow_back, size: 20),
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  if (o.clientInitials != null)
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF1F2937),
                      child: Text(o.clientInitials!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  const Spacer(),
                  if (o.distanceKm != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: _green, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text('${o.distanceKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ------------------------------------------------ pastki karta
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _priceCard(start),
                  const SizedBox(height: 14),
                  _addressRow(),
                  const SizedBox(height: 10),
                  _paymentPill(),
                  const SizedBox(height: 14),
                  SwipeToAccept(
                    label: 'requests.quick_accept'.tr(),
                    color: _blue,
                    busy: _busy,
                    onAccepted: _accept,
                  ),
                  TextButton(
                    onPressed: _busy ? null : _decline,
                    child: Text('requests.quick_decline'.tr(),
                        style: const TextStyle(
                            color: Color(0xFFE5484D),
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCard(String start) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'requests.quick_title'.tr(args: [o.typeLabel, '${o.days}']),
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_money(o.price),
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.1)),
                ),
                Text('requests.quick_price_caption'.tr(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                Text(
                  'requests.quick_you_receive'.tr(args: [_money(o.youReceive)]),
                  style: const TextStyle(
                      fontSize: 12, color: _green, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.schedule, color: _green),
              ),
              const SizedBox(height: 6),
              Text('requests.quick_start'.tr(),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              Text(o.startTime == null ? start : '$start · ${o.startTime}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addressRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _blue, width: 2.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o.deliveryAddress?.isNotEmpty == true
                    ? o.deliveryAddress!
                    : '${o.deliveryLatitude.toStringAsFixed(4)}, '
                        '${o.deliveryLongitude.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text('requests.quick_where'.tr(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentPill() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 16),
            const SizedBox(width: 6),
            Text('requests.quick_payment_frozen'.tr(),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _round({required Widget child, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 38, height: 38, child: Center(child: child)),
      ),
    );
  }
}

/// "Qabul qilish ›››" — doirachani o'ngga surish kerak. Oddiy bosish
/// tasodifan bo'lishi mumkin, surish esa — yo'q: bitta harakatda
/// boshqa odamning puli bilan bog'langan buyurtma olinadi.
class SwipeToAccept extends StatefulWidget {
  const SwipeToAccept({
    super.key,
    required this.label,
    required this.onAccepted,
    this.color = const Color(0xFF2D8CF0),
    this.busy = false,
  });

  final String label;
  final VoidCallback onAccepted;
  final Color color;
  final bool busy;

  @override
  State<SwipeToAccept> createState() => _SwipeToAcceptState();
}

class _SwipeToAcceptState extends State<SwipeToAccept> {
  static const double _height = 56;
  static const double _knob = 46;
  double _dx = 0;

  @override
  void didUpdateWidget(SwipeToAccept old) {
    super.didUpdateWidget(old);
    // Xato bo'lsa doiracha joyiga qaytadi
    if (old.busy && !widget.busy) setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final max = constraints.maxWidth - _knob - 10;
      final progress = max <= 0 ? 0.0 : (_dx / max).clamp(0.0, 1.0);
      return Container(
        height: _height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(_height / 2),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Center(
              child: Opacity(
                opacity: 1 - progress * 0.8,
                child: Text(
                  '${widget.label}  ›››',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 5 + _dx,
              child: GestureDetector(
                onHorizontalDragUpdate: widget.busy
                    ? null
                    : (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, max)),
                onHorizontalDragEnd: widget.busy
                    ? null
                    : (_) {
                        if (_dx >= max * 0.85) {
                          setState(() => _dx = max);
                          widget.onAccepted();
                        } else {
                          setState(() => _dx = 0);
                        }
                      },
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: widget.busy
                      ? Padding(
                          padding: const EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: widget.color),
                        )
                      : Icon(Icons.arrow_forward, color: widget.color),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
