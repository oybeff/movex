import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/material_types.dart';
import '../../../../core/models/material_model.dart';
import '../../../../core/services/material_service.dart';
import '../../../../core/utils/number_formatter.dart';
import 'material_order_page.dart';
import '../../../../core/widgets/material_type_icon.dart';

/// Qurilish materiallari katalogi: g'isht, sement, qum, gazoblok.
///
/// Texnika katalogidan farqi — bu yerda IJARA emas, savdo: narx birlik
/// uchun, muddat yo'q. Buyurtma ekranida miqdor kiritiladi va server
/// og'irlikni, mashinani va yetkazib berishni o'zi hisoblab beradi.
class MaterialsCatalogPage extends StatefulWidget {
  const MaterialsCatalogPage({super.key, this.initialType});

  /// Bosh sahifadagi kategoriyadan kelinganda — o'sha tur bilan ochiladi.
  final String? initialType;

  @override
  State<MaterialsCatalogPage> createState() => _MaterialsCatalogPageState();
}

class _MaterialsCatalogPageState extends State<MaterialsCatalogPage> {
  final MaterialService _service = MaterialService();

  List<MaterialProductModel> _items = [];
  String? _filterType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _filterType = widget.initialType;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.getCatalog(materialType: _filterType);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'materials.title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _typeFilter(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryGreen))
                : RefreshIndicator(
                    color: AppColors.primaryGreen,
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? _empty()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _items.length,
                            itemBuilder: (context, i) => _card(_items[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _typeFilter() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
            child: ChoiceChip(
              selected: _filterType == null,
              onSelected: (_) {
                setState(() => _filterType = null);
                _load();
              },
              label: Text('common.all'.tr(),
                  style: const TextStyle(fontSize: 12)),
              selectedColor: AppColors.primaryGreen.withValues(alpha: 0.18),
              backgroundColor: AppColors.white,
              side: BorderSide(
                color: _filterType == null
                    ? AppColors.primaryGreen
                    : Colors.black12,
              ),
            ),
          ),
          for (final code in MaterialTypes.codes)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: ChoiceChip(
                selected: _filterType == code,
                onSelected: (selected) {
                  setState(() => _filterType = selected ? code : null);
                  _load();
                },
                avatar: MaterialTypeIcon(code, size: 20),
                label: Text(MaterialTypes.label(code),
                    style: const TextStyle(fontSize: 12)),
                selectedColor: AppColors.primaryGreen.withValues(alpha: 0.18),
                backgroundColor: AppColors.white,
                side: BorderSide(
                  color: _filterType == code
                      ? AppColors.primaryGreen
                      : Colors.black12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(MaterialProductModel product) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final ordered = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => MaterialOrderPage(product: product),
          ),
        );
        if (ordered == true && mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product.photos.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  // Server "/static/..." qaytaradi — ildizga nisbatan yo'l,
                  // Image.network uni tushunmaydi.
                  AppConfig.mediaUrl(product.photos.first),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _iconBox(product),
                ),
              )
            else
              _iconBox(product),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.typeLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${NumberFormatter.formatCurrency(product.pricePerUnit)} '
                    '${'common.currency'.tr()} / ${product.unitLabel}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  if (product.availableQuantity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'materials.in_stock'.tr(namedArgs: {
                          'count': NumberFormatter.formatCurrency(
                              product.availableQuantity),
                          'unit': product.unitLabel,
                        }),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  if (product.distanceKm != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'requests.distance_away'.tr(
                            args: [product.distanceKm!.toStringAsFixed(0)]),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
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

  /// Rasmi yo'q tovar uchun — material turi ikonkasi.
  Widget _iconBox(MaterialProductModel product) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: MaterialTypeIcon(product.materialType, size: 46),
      );

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: MaterialTypeIcon(_filterType, size: 72),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text('materials.empty'.tr(),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'materials.empty_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
