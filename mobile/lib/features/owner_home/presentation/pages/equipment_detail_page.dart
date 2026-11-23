import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:map_launcher/map_launcher.dart' as map_launcher;
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/models/equipment_model.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/widgets/map_or_placeholder.dart';
import '../../../driver/presentation/driver_ui.dart';

class EquipmentDetailPage extends StatefulWidget {
  final EquipmentModel equipment;

  const EquipmentDetailPage({
    super.key,
    required this.equipment,
  });

  @override
  State<EquipmentDetailPage> createState() => _EquipmentDetailPageState();
}

class _EquipmentDetailPageState extends State<EquipmentDetailPage> {
  YandexMapController? _mapController;
  bool _mapReady = false;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _moveToLocation(Point point) async {
    if (_mapController != null && _mapReady) {
      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: point,
            zoom: 15,
          ),
        ),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.0),
      );
    }
  }

  Widget _buildInfoRow(String label, String? value, {IconData? icon}) {
    if (value == null || value.isEmpty || value == '-') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppPalette.brand),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInMap() async {
    try {
      final availableMaps = await map_launcher.MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('errors.no_maps_available'.tr())),
          );
        }
        return;
      }

      if (availableMaps.length == 1) {
        await availableMaps.first.showMarker(
          coords: map_launcher.Coords(
            double.parse(widget.equipment.latitude!),
            double.parse(widget.equipment.longitude!),
          ),
          title: widget.equipment.address ?? '',
          description: widget.equipment.address ?? '',
        );
        return;
      }

      if (mounted) {
        await showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => DSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'orders.open_in_map'.tr(),
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 12),
                ...availableMaps.map((map) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppPalette.page,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: SvgPicture.asset(
                        map.icon,
                        height: 28.0,
                        width: 28.0,
                      ),
                      title: Text(map.mapName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(context);
                        map.showMarker(
                          coords: map_launcher.Coords(
                            double.parse(widget.equipment.latitude!),
                            double.parse(widget.equipment.longitude!),
                          ),
                          title: widget.equipment.address ?? '',
                          description: widget.equipment.address ?? '',
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.h3,
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.equipment.latitude != null &&
        widget.equipment.longitude != null &&
        widget.equipment.latitude!.isNotEmpty &&
        widget.equipment.longitude!.isNotEmpty;

    Point? equipmentLocation;
    if (hasLocation) {
      try {
        equipmentLocation = Point(
          latitude: double.parse(widget.equipment.latitude!),
          longitude: double.parse(widget.equipment.longitude!),
        );
      } catch (_) {}
    }

    Widget statusChip;
    switch (widget.equipment.status) {
      case 'available':
        statusChip = DChip('equipment.status_available'.tr(), bg: AppPalette.successSubtle, fg: AppPalette.textSuccess);
        break;
      case 'busy':
        statusChip = DChip('equipment.status_busy'.tr(), bg: AppPalette.accentSubtle, fg: AppPalette.textOnAccent);
        break;
      case 'maintenance':
      case 'repair':
        statusChip = DChip('equipment.status_repair'.tr(), bg: AppPalette.dangerSubtle, fg: AppPalette.textDanger);
        break;
      default:
        statusChip = DChip('equipment.status_unknown'.tr(), bg: AppPalette.page, fg: AppPalette.textSecondary);
    }

    final pricePerHour = widget.equipment.pricePerHourValue ??
        (widget.equipment.pricePerDayValue > 0 ? (widget.equipment.pricePerDayValue / 8).round() : null);

    return Scaffold(
      backgroundColor: AppPalette.page,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppPalette.brand,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${EquipmentTypes.label(widget.equipment.type)} ${widget.equipment.model}'.trim(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppPalette.brand,
                      Color(0xFF1B4FA0),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.construction_rounded,
                    size: 72,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Badge
                    Row(
                      children: [
                        statusChip,
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description
                    if (widget.equipment.description != null && widget.equipment.description!.isNotEmpty)
                      _buildSection(
                        'equipment.description'.tr(),
                        [
                          Text(
                            widget.equipment.description!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppPalette.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),

                    // Technical Info
                    _buildSection(
                      'equipment.technical_info'.tr(),
                      [
                        _buildInfoRow(
                          'equipment.type'.tr(),
                          EquipmentTypes.label(widget.equipment.type),
                          icon: Icons.category_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.model'.tr(),
                          widget.equipment.model,
                          icon: Icons.precision_manufacturing_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.year'.tr(),
                          widget.equipment.year?.toString(),
                          icon: Icons.calendar_today_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.power_hp'.tr(),
                          widget.equipment.powerHp != null ? '${widget.equipment.powerHp} HP' : null,
                          icon: Icons.speed_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.payload_kg'.tr(),
                          widget.equipment.payloadKg != null ? '${widget.equipment.payloadKg} kg' : null,
                          icon: Icons.fitness_center_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.dimensions'.tr(),
                          widget.equipment.dimensions,
                          icon: Icons.straighten_rounded,
                        ),
                      ],
                    ),

                    // Pricing Info
                    _buildSection(
                      'equipment.pricing'.tr(),
                      [
                        if (pricePerHour != null)
                          _buildInfoRow(
                            'equipment.price_per_hour'.tr(),
                            '${NumberFormatter.formatCurrency(pricePerHour)} ${'common.currency'.tr()}',
                            icon: Icons.access_time_rounded,
                          ),
                        _buildInfoRow(
                          'equipment.price_per_shift'.tr(),
                          widget.equipment.pricePerShiftValue != null
                              ? '${NumberFormatter.formatCurrency(widget.equipment.pricePerShiftValue!.round())} ${'common.currency'.tr()}'
                              : null,
                          icon: Icons.work_history_rounded,
                        ),
                        _buildInfoRow(
                          'equipment.price_per_day'.tr(),
                          '${NumberFormatter.formatCurrency(widget.equipment.pricePerDayValue.round())} ${'common.currency'.tr()}',
                          icon: Icons.calendar_month_rounded,
                        ),
                      ],
                    ),

                    // Location Info
                    if (widget.equipment.address != null && widget.equipment.address!.isNotEmpty)
                      _buildSection(
                        'equipment.location'.tr(),
                        [
                          _buildInfoRow(
                            'equipment.address'.tr(),
                            widget.equipment.address,
                            icon: Icons.location_on_rounded,
                          ),
                        ],
                      ),

                    // Map
                    if (hasLocation && equipmentLocation != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              MapOrPlaceholder(mapBuilder: (_) => YandexMap(
                                onMapCreated: (controller) async {
                                  _mapController = controller;
                                  setState(() => _mapReady = true);
                                  await _moveToLocation(equipmentLocation!);
                                },
                              )),
                              Center(
                                child: Icon(
                                  Icons.location_on,
                                  size: 44,
                                  color: AppPalette.textDanger,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withAlpha(80),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Material(
                                  color: AppPalette.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: _openInMap,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.map_rounded, size: 18, color: AppPalette.brand),
                                          const SizedBox(width: 6),
                                          Text(
                                            'orders.open_in_map'.tr(),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppPalette.brand,
                                              fontWeight: FontWeight.w600,
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
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
