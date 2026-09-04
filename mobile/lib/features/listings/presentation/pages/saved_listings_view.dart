import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/listing_model.dart';
import '../../../../core/services/listing_service.dart';
import '../widgets/listing_card.dart';

/// Saqlanganlar — xatcho'p bosilgan e'lonlar.
///
/// Nima uchun alohida bo'lim. Taxta tez yangilanadi va yoqqan e'lonni
/// keyin topib bo'lmasdi: odam uni ko'radi, o'ylab ko'rmoqchi bo'ladi, va
/// bir kundan keyin e'lon ellikta yangisining ostida qolib ketadi.
///
/// Bu Scaffold EMAS: ekranni ListingsPage tutadi, bu yerda faqat tanasi.
class SavedListingsView extends StatefulWidget {
  const SavedListingsView({super.key});

  @override
  State<SavedListingsView> createState() => SavedListingsViewState();
}

class SavedListingsViewState extends State<SavedListingsView> {
  final ListingService _service = ListingService();

  List<ListingModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getSaved();
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

  /// Tashqaridan yangilash — bo'limga o'tilganda ListingsPage chaqiradi.
  Future<void> reload() => _load();

  /// Xatcho'pni olib tashlash. E'lon ro'yxatdan DARHOL ketadi: u shu
  /// yerda faqat xatcho'p tufayli turibdi, va joyida qolsa odam uni
  /// yechilmadi deb o'ylardi.
  Future<void> _unsave(ListingModel listing) async {
    try {
      await _service.setSaved(listing.id, false);
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.id == listing.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('errors.something_went_wrong'.tr())),
      );
    }
  }

  Future<void> _toggleLike(ListingModel listing) async {
    try {
      final updated = await _service.setLike(listing.id, !listing.likedByMe);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((x) => x.id == listing.id);
        if (index != -1) _items[index] = updated;
      });
    } catch (_) {
      // Yurakcha — ikkinchi darajali amal, xato uchun ekranni bezovta
      // qilishning hojati yo'q.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _load,
      child: _items.isEmpty
          ? _empty()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _items.length,
              itemBuilder: (context, i) => ListingCard(
                listing: _items[i],
                onToggleLike: () => _toggleLike(_items[i]),
                onToggleSave: () => _unsave(_items[i]),
              ),
            ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.bookmark_border, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'listings.saved_empty'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'listings.saved_empty_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
