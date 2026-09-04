import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/material_types.dart';
import '../../../../core/models/material_model.dart';
import '../../../../core/services/material_service.dart';
import '../../../../core/utils/number_formatter.dart';

/// Material buyurtmasi: miqdor → og'irlik → mashina → yetkazish → jami.
///
/// HISOBNI SERVER QILADI. Miqdor o'zgarganda /materials/quote so'raladi
/// va ekranda aynan o'sha raqamlar chiqadi. Ilova o'zi hisoblaganida
/// formula ikki joyda bo'lardi va ular ertami-kechmi ajralib ketardi:
/// ekranda bir summa, balansdan boshqasi yechilardi.
///
/// Mashinani server tanlaydi (og'irlikka qarab eng kichigi), lekin
/// foydalanuvchi o'zgartira oladi — u yo'lni va joyni bizdan yaxshiroq
/// biladi: tor ko'chaga katta mashina kirmasligi mumkin.
class MaterialOrderPage extends StatefulWidget {
  const MaterialOrderPage({super.key, required this.product});

  final MaterialProductModel product;

  @override
  State<MaterialOrderPage> createState() => _MaterialOrderPageState();
}

class _MaterialOrderPageState extends State<MaterialOrderPage> {
  final MaterialService _service = MaterialService();
  final _quantityController = TextEditingController();
  final _addressController = TextEditingController();
  final _commentController = TextEditingController();

  List<DeliveryVehicleModel> _vehicles = [];
  String? _vehicleCode;
  MaterialQuoteModel? _quote;

  /// Serverga har bosilgan raqam uchun so'rov yubormaslik uchun.
  Timer? _debounce;
  bool _isCalculating = false;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantityController.text =
        NumberFormatter.formatCurrency(widget.product.minQuantity)
            .replaceAll(' ', '');
    _quantityController.addListener(_onQuantityChanged);
    _loadVehicles();
    _recalculate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _quantityController.removeListener(_onQuantityChanged);
    _quantityController.dispose();
    _addressController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    try {
      final vehicles = await _service.getVehicles();
      if (mounted) setState(() => _vehicles = vehicles);
    } catch (_) {
      // Mashinalar ro'yxati bo'lmasa ham buyurtma berish ishlaydi:
      // serverning o'zi mos mashinani tanlaydi.
    }
  }

  double get _quantity =>
      double.tryParse(_quantityController.text.replaceAll(' ', '')) ?? 0;

  void _onQuantityChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _recalculate);
  }

  Future<void> _recalculate() async {
    if (_quantity <= 0) {
      setState(() {
        _quote = null;
        _error = null;
      });
      return;
    }

    setState(() => _isCalculating = true);
    try {
      final quote = await _service.quote(
        productId: widget.product.id,
        quantity: _quantity,
        latitude: widget.product.latitude,
        longitude: widget.product.longitude,
        vehicleCode: _vehicleCode,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _error = null;
        _isCalculating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        // Serverdagi sabab foydalanuvchiga aynan kerak: "eng kam partiya",
        // "omborda shuncha yo'q" va hokazo.
        _error = _detail(e);
        _isCalculating = false;
      });
    }
  }

  String? _detail(Object e) {
    try {
      final data = (e as dynamic).response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    } catch (_) {}
    return 'errors.something_went_wrong'.tr();
  }

  Future<void> _submit() async {
    if (_quote == null) return;

    setState(() => _isSending = true);
    try {
      await _service.createOrder(
        productId: widget.product.id,
        quantity: _quantity,
        address: _addressController.text.trim(),
        latitude: widget.product.latitude,
        longitude: widget.product.longitude,
        vehicleCode: _vehicleCode,
        comment: _commentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('materials.order_created'.tr())),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_detail(e) ?? '')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'materials.order_title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _productCard(product),
          const SizedBox(height: 14),
          _quantityCard(product),
          const SizedBox(height: 14),
          if (_error != null) _errorCard(),
          if (_quote != null) ...[
            _vehicleCard(),
            const SizedBox(height: 14),
            _totalCard(),
            const SizedBox(height: 14),
          ],
          _deliveryCard(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_quote == null || _isSending) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'materials.order_button'.tr(),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'materials.escrow_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: child,
      );

  Widget _productCard(MaterialProductModel product) => _card(
        child: Row(
          children: [
            Text(product.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${NumberFormatter.formatCurrency(product.pricePerUnit)} '
                    '${'common.currency'.tr()} / ${product.unitLabel}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  if (product.ownerName != null)
                    Text(product.ownerName!,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _quantityCard(MaterialProductModel product) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('materials.quantity'.tr(),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                suffixText: product.unitLabel,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'materials.min_order'.tr(namedArgs: {
                'count':
                    NumberFormatter.formatCurrency(product.minQuantity),
                'unit': product.unitLabel,
              }),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );

  Widget _errorCard() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _error!,
          style: const TextStyle(fontSize: 13, color: AppColors.error),
        ),
      );

  /// Server tanlagan mashina va uni almashtirish imkoni.
  Widget _vehicleCard() {
    final quote = _quote!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined,
                  size: 20, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'materials.vehicle_needed'.tr(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              if (_isCalculating)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primaryGreen),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'materials.weight_line'.tr(namedArgs: {
              'weight': NumberFormatter.formatCurrency(quote.weightKg),
              'vehicle': DeliveryVehicles.label(quote.vehicleCode),
              'trips': '${quote.trips}',
            }),
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
          if (_vehicles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('materials.vehicle_change'.tr(),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final vehicle in _vehicles)
                  ChoiceChip(
                    selected: quote.vehicleCode == vehicle.code,
                    onSelected: (_) {
                      setState(() => _vehicleCode = vehicle.code);
                      _recalculate();
                    },
                    label: Text(
                      DeliveryVehicles.label(vehicle.code),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selectedColor:
                        AppColors.primaryGreen.withValues(alpha: 0.18),
                    backgroundColor: AppColors.background,
                    side: BorderSide(
                      color: quote.vehicleCode == vehicle.code
                          ? AppColors.primaryGreen
                          : Colors.black12,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalCard() {
    final quote = _quote!;
    return _card(
      child: Column(
        children: [
          _line('materials.goods'.tr(), quote.goodsAmount),
          const SizedBox(height: 8),
          _line(
            quote.deliveryDistanceKm == null
                ? 'materials.delivery'.tr()
                : 'materials.delivery_km'.tr(namedArgs: {
                    'km': quote.deliveryDistanceKm!.toStringAsFixed(0),
                    'trips': '${quote.trips}',
                  }),
            quote.deliveryFee,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _line('materials.total'.tr(), quote.total, bold: true),
        ],
      ),
    );
  }

  Widget _line(String label, double value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                color: bold ? AppColors.black : Colors.grey[700],
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '${NumberFormatter.formatCurrency(value)} ${'common.currency'.tr()}',
            style: TextStyle(
              fontSize: bold ? 17 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      );

  Widget _deliveryCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('materials.delivery_address'.tr(),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                hintText: 'materials.address_hint'.tr(),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'materials.comment_hint'.tr(),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
      );
}
