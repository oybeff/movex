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
  });

  final ListingModel listing;
  final List<Widget> actions;
  final VoidCallback? onTap;

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

            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
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
