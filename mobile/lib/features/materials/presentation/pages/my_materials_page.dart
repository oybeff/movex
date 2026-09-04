import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/material_types.dart';
import '../../../../core/models/material_model.dart';
import '../../../../core/services/material_service.dart';
import '../../../../core/utils/number_formatter.dart';

/// Sotuvchining materiallari: qo'shish, ko'rish, o'chirish.
///
/// Yangi tovar MODERATSIYAGA tushadi va tasdiqlangunicha katalogda
/// ko'rinmaydi — buni sahifada ochiq aytamiz, aks holda sotuvchi tovarini
/// qo'shib, uni katalogdan izlab yurardi.
///
/// Rolga bog'liq emas: material sotuvchi texnika egasi bo'lishi shart
/// emas, va server ham bu yerda rol tekshirmaydi.
class MyMaterialsPage extends StatefulWidget {
  const MyMaterialsPage({super.key});

  @override
  State<MyMaterialsPage> createState() => _MyMaterialsPageState();
}

class _MyMaterialsPageState extends State<MyMaterialsPage> {
  final MaterialService _service = MaterialService();

  List<MaterialProductModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.getMyProducts();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String? _detail(Object e) {
    try {
      final data = (e as dynamic).response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    } catch (_) {}
    return null;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete(MaterialProductModel product) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text('materials.delete_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.no'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('common.yes'.tr()),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    try {
      await _service.deleteProduct(product.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      _snack(_detail(e) ?? 'errors.something_went_wrong'.tr());
    }
  }

  Future<void> _add() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddMaterialPage()),
    );
    if (created == true && mounted) {
      _snack('materials.sent_to_moderation'.tr());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'materials.my_products'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: _add, icon: const Icon(Icons.add)),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _load,
              child: _items.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, i) => _card(_items[i]),
                    ),
            ),
    );
  }

  Widget _card(MaterialProductModel product) {
    final (Color color, String key) = switch (product.status) {
      'approved' => (AppColors.primaryGreen, 'materials.status_approved'),
      'rejected' => (AppColors.error, 'materials.status_rejected'),
      _ => (Colors.orange, 'materials.status_pending'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(product.typeLabel,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(key.tr(),
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${NumberFormatter.formatCurrency(product.pricePerUnit)} '
            '${'common.currency'.tr()} / ${product.unitLabel}'
            '  ·  ${product.unitWeightKg.toStringAsFixed(1)} kg',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (product.availableQuantity != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'materials.in_stock'.tr(namedArgs: {
                  'count':
                      NumberFormatter.formatCurrency(product.availableQuantity),
                  'unit': product.unitLabel,
                }),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          if (product.isRejected && product.moderationComment != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(product.moderationComment!,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.error)),
            ),
          if (product.isPending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('materials.pending_hint'.tr(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _delete(product),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('common.delete'.tr()),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 100),
          const Center(child: Text('🧱', style: TextStyle(fontSize: 56))),
          const SizedBox(height: 16),
          Center(
            child: Text('materials.my_empty'.tr(),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'materials.my_empty_hint'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
        ],
      );
}

/// Yangi tovar qo'shish.
///
/// Birlik va og'irlik ma'lumotnomadan avtomatik to'ldiriladi (g'isht →
/// dona, 3.5 kg), lekin sotuvchi o'zgartira oladi: og'irlikka qarab
/// MASHINA tanlanadi, ya'ni noto'g'ri qiymat noto'g'ri mashinani
/// chaqiradi.
class AddMaterialPage extends StatefulWidget {
  const AddMaterialPage({super.key});

  @override
  State<AddMaterialPage> createState() => _AddMaterialPageState();
}

class _AddMaterialPageState extends State<AddMaterialPage> {
  final _formKey = GlobalKey<FormState>();
  final MaterialService _service = MaterialService();

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _weightController = TextEditingController();
  final _minController = TextEditingController(text: '1');
  final _stockController = TextEditingController();
  final _deliveryController = TextEditingController();
  final _addressController = TextEditingController();

  String _type = MaterialTypes.codes.first;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _applyDefaults();
  }

  /// Ma'lumotnomadagi odatdagi og'irlik. Turi almashganda yangilanadi,
  /// lekin sotuvchi qo'lda yozgani ustun turadi.
  void _applyDefaults() {
    const weights = <String, double>{
      'brick': 3.5, 'gas_block': 18, 'cement': 50, 'sand': 1500,
      'gravel': 1400, 'stone': 1600, 'rebar': 1000, 'concrete': 2400,
      'lumber': 600, 'other': 1,
    };
    _weightController.text = (weights[_type] ?? 1).toString();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _weightController.dispose();
    _minController.dispose();
    _stockController.dispose();
    _deliveryController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  double? _number(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    try {
      await _service.createProduct(
        materialType: _type,
        title: _titleController.text.trim(),
        pricePerUnit: _number(_priceController)!,
        unitWeightKg: _number(_weightController),
        minQuantity: _number(_minController),
        availableQuantity: _number(_stockController),
        deliveryPricePerKm: _number(_deliveryController),
        address: _addressController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      String? detail;
      try {
        final data = (e as dynamic).response?.data;
        if (data is Map && data['detail'] is String) detail = data['detail'] as String;
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(detail ?? 'errors.something_went_wrong'.tr())),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'materials.add_title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('materials.type'.tr(),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in MaterialTypes.codes)
                  ChoiceChip(
                    selected: _type == code,
                    onSelected: (_) {
                      setState(() => _type = code);
                      _applyDefaults();
                    },
                    avatar: Text(MaterialTypes.emoji(code),
                        style: const TextStyle(fontSize: 14)),
                    label: Text(MaterialTypes.label(code),
                        style: const TextStyle(fontSize: 12)),
                    selectedColor:
                        AppColors.primaryGreen.withValues(alpha: 0.18),
                    backgroundColor: AppColors.white,
                    side: BorderSide(
                      color: _type == code
                          ? AppColors.primaryGreen
                          : Colors.black12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Matn AYNAN shu yerda tarjima qilinadi, kalit o'zi uzatilmaydi.
            // Kalitni o'zgaruvchiga solib yuborish loyihada allaqachon
            // bo'lgan xato: ekranda "messages.location_permission..." degan
            // yozuv chiqib turardi. tool/verify_translations.py buni ushlaydi.
            _field(_titleController, 'materials.field_title'.tr(), required: true),
            _field(_priceController, 'materials.field_price'.tr(),
                required: true, number: true),
            _field(_weightController, 'materials.field_weight'.tr(),
                required: true, number: true,
                hint: 'materials.field_weight_hint'.tr()),
            _field(_minController, 'materials.field_min'.tr(), number: true),
            _field(_stockController, 'materials.field_stock'.tr(), number: true),
            _field(_deliveryController, 'materials.field_delivery'.tr(),
                number: true, hint: 'materials.field_delivery_hint'.tr()),
            _field(_addressController, 'materials.field_address'.tr()),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'materials.moderation_hint'.tr(),
                style: const TextStyle(
                    fontSize: 12.5, color: Colors.deepOrange),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSending ? null : _submit,
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
                    : Text('materials.add_button'.tr(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  /// [label] va [hint] TAYYOR matn, kalit emas: tarjima chaqiruv joyida
  /// qilinadi, aks holda kalit ekranga chiqib ketishi mumkin.
  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool number = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType:
            number ? const TextInputType.numberWithOptions(decimal: true) : null,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = (value ?? '').trim();
          if (required && text.isEmpty) return 'materials.field_required'.tr();
          if (number && text.isNotEmpty && _number(controller) == null) {
            return 'materials.field_number'.tr();
          }
          return null;
        },
      ),
    );
  }
}
