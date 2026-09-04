import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_config.dart';
import '../../../../core/models/listing_model.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';

/// E'lon kartochkasi — mijozning ro'yxatida ham, ega taxtasida ham bir xil.
///
/// Tugmalar tashqaridan beriladi: mijoz "tasdiqlash/rad etish" ni ko'radi,
/// ega esa "olaman" ni. Kartochkaning o'zi kim ekanini bilmaydi va bilishi
/// ham shart emas.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    this.actions = const [],
    this.onTap,
    this.onToggleLike,
    this.onToggleSave,
  });

  final ListingModel listing;
  final List<Widget> actions;
  final VoidCallback? onTap;

  /// Berilsa — yurakcha va xatcho'p bosiladigan bo'ladi. Berilmasa faqat
  /// raqamlar ko'rinadi: o'z e'loningni yoqtirishning ma'nosi yo'q.
  final VoidCallback? onToggleLike;
  final VoidCallback? onToggleSave;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
                if (listing.equipmentType != null) ...[
                  EquipmentTypeIcon(listing.equipmentType, size: 40),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd.MM.yyyy HH:mm')
                            .format(listing.createdAt.toLocal()),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _statusChip(),
              ],
            ),

            if (listing.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: listing.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      AppConfig.mediaUrl(listing.photos[i]),
                      width: 120,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 90,
                        color: AppColors.lightGrey,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            if (listing.description != null &&
                listing.description!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                listing.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
            ],

            if (listing.address != null && listing.address!.isNotEmpty)
              _row(Icons.place_outlined, listing.address!),

            if (listing.neededFrom != null)
              _row(
                Icons.calendar_today_outlined,
                listing.neededTo == null
                    ? DateFormat('dd.MM.yyyy').format(listing.neededFrom!)
                    : '${DateFormat('dd.MM.yyyy').format(listing.neededFrom!)} — '
                        '${DateFormat('dd.MM.yyyy').format(listing.neededTo!)}',
              ),

            if (listing.budget != null)
              _row(
                Icons.payments_outlined,
                '${'listings.budget'.tr()}: '
                '${NumberFormatter.formatCurrency(listing.budget)} '
                '${'common.currency'.tr()}',
              ),

            if (listing.distanceKm != null)
              _row(
                Icons.near_me_outlined,
                'requests.distance_away'
                    .tr(args: [listing.distanceKm!.toStringAsFixed(0)]),
              ),

            if (listing.takerName != null)
              _row(Icons.person_outline,
                  '${'listings.taken_by'.tr()}: ${listing.takerName}'),

            // Telefon serverdan kelgan bo'lsa — demak ko'rsatishga ruxsat bor.
            // Ilova o'zi hech qanday shart tekshirmaydi.
            if (listing.hasPhone)
              _row(Icons.phone_outlined, listing.contactPhone!, bold: true),

            _stats(),

            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              // Uchta tugma bitta qatorga sig'maydi: telefon ekranida
              // yozuvlar qirqilib ketadi. Shuning uchun birinchisi (odatda
              // "Marshrut") alohida qatorda turadi.
              if (actions.length > 2) ...[
                SizedBox(width: double.infinity, child: actions.first),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (int i = 1; i < actions.length; i++) ...[
                      if (i > 1) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ] else
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ko'rishlar, yoqtirishlar, xatcho'plar va takliflar bitta qatorda.
  ///
  /// Muallif uchun bu javob: e'lonim ko'rinyaptimi va unga qiziqish
  /// bormi. Ijrochi uchun — qanchalik raqobat borligi.
  Widget _stats() {
    final canReact = onToggleLike != null || onToggleSave != null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _stat(Icons.visibility_outlined, listing.viewsCount),
          const SizedBox(width: 14),

          if (onToggleLike != null)
            _tappable(
              icon: listing.likedByMe ? Icons.favorite : Icons.favorite_border,
              color: listing.likedByMe ? Colors.redAccent : null,
              count: listing.likesCount,
              onTap: onToggleLike!,
            )
          else
            _stat(Icons.favorite_border, listing.likesCount),
          const SizedBox(width: 14),

          if (onToggleSave != null)
            _tappable(
              icon: listing.savedByMe ? Icons.bookmark : Icons.bookmark_border,
              color: listing.savedByMe ? AppColors.primaryGreen : null,
              count: listing.savesCount,
              onTap: onToggleSave!,
            )
          else
            _stat(Icons.bookmark_border, listing.savesCount),

          if (listing.offersCount > 0) ...[
            const SizedBox(width: 14),
            _stat(Icons.local_offer_outlined, listing.offersCount,
                highlight: !canReact),
          ],
        ],
      ),
    );
  }

  Widget _stat(IconData icon, int count, {bool highlight = false}) {
    final color = highlight ? AppColors.primaryGreen : Colors.grey[600];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _tappable({
    required IconData icon,
    required int count,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      // Barmoq uchun kattaroq maydon: 16px ikonka o'zi juda kichik nishon.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color ?? Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12.5,
                color: color ?? Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: bold ? AppColors.black : Colors.grey[700],
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _statusChip() {
    final (Color color, String key) = switch (listing.status) {
      'open' => (AppColors.primaryGreen, 'listings.status_open'),
      'taken' => (Colors.orange, 'listings.status_taken'),
      'confirmed' => (Colors.blue, 'listings.status_confirmed'),
      'done' => (Colors.grey, 'listings.status_done'),
      'cancelled' => (Colors.grey, 'listings.status_cancelled'),
      'expired' => (Colors.grey, 'listings.status_expired'),
      _ => (Colors.grey, 'listings.status_open'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        key.tr(),
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
