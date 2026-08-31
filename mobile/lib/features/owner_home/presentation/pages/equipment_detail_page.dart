import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:map_launcher/map_launcher.dart' as map_launcher;
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/widgets/map_or_placeholder.dart';

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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'available':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      case 'repair':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _mapStatus(String? status) {
    switch (status) {
      case 'available':
        return 'equipment.status_available'.tr();
      case 'busy':
        return 'equipment.status_busy'.tr();
      case 'repair':
        return 'equipment.status_repair'.tr();
      default:
        return 'equipment.status_unknown'.tr();
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'available':
        return Icons.check_circle;
      case 'busy':
        return Icons.work;
      case 'repair':
        return Icons.build;
      default:
        return Icons.help_outline;
    }
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      print('Error opening in map: $e');
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
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
      } catch (e) {
        // Parse error
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primaryGreen,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${EquipmentTypes.label(widget.equipment.type)} ${widget.equipment.model}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryGreen,
                      AppColors.primaryGreen.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.construction,
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.3),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _statusColor(widget.equipment.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _statusColor(widget.equipment.status).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(widget.equipment.status),
                            color: _statusColor(widget.equipment.status),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _mapStatus(widget.equipment.status),
                            style: TextStyle(
                              color: _statusColor(widget.equipment.status),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Description
                    if (widget.equipment.description != null && widget.equipment.description!.isNotEmpty)
                      _buildSection(
                        'equipment.description'.tr(),
                        [
                          Text(
                            widget.equipment.description!,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[700],
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
                          icon: Icons.category,
                        ),
                        _buildInfoRow(
                          'equipment.model'.tr(),
                          widget.equipment.model,
                          icon: Icons.precision_manufacturing,
                        ),
                        _buildInfoRow(
                          'equipment.year'.tr(),
                          widget.equipment.year?.toString(),
                          icon: Icons.calendar_today,
                        ),
                        _buildInfoRow(
                          'equipment.power_hp'.tr(),
                          widget.equipment.powerHp != null ? '${widget.equipment.powerHp} HP' : null,
                          icon: Icons.speed,
                        ),
                        _buildInfoRow(
                          'equipment.payload_kg'.tr(),
                          widget.equipment.payloadKg != null ? '${widget.equipment.payloadKg} kg' : null,
                          icon: Icons.fitness_center,
                        ),
                        _buildInfoRow(
                          'equipment.dimensions'.tr(),
                          widget.equipment.dimensions,
                          icon: Icons.straighten,
                        ),
                      ],
                    ),

                    // Pricing Info
                    _buildSection(
                      'equipment.pricing'.tr(),
                      [
                        _buildInfoRow(
                          'equipment.price_per_hour'.tr(),
                          widget.equipment.pricePerHour != null
                              ? '${NumberFormatter.formatCurrency(widget.equipment.pricePerHour)} ${'common.currency'.tr()}'
                              : null,
                          icon: Icons.access_time,
                        ),
                        _buildInfoRow(
                          'equipment.price_per_shift'.tr(),
                          widget.equipment.pricePerShift != null
                              ? '${NumberFormatter.formatCurrency(widget.equipment.pricePerShift)} ${'common.currency'.tr()}'
                              : null,
                          icon: Icons.work_history,
                        ),
                        _buildInfoRow(
                          'equipment.price_per_day'.tr(),
                          '${NumberFormatter.formatCurrency(widget.equipment.pricePerDay)} ${'common.currency'.tr()}',
                          icon: Icons.calendar_today,
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
                            icon: Icons.location_on,
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                              // Marker in center
                              Center(
                                child: Icon(
                                  Icons.location_on,
                                  size: 48,
                                  color: Colors.red,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withAlpha(100),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),

                              //open in maps
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: () => _openInMap(),
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
                                              color: AppColors.primaryGreen,
                                              fontWeight: FontWeight.w500,
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

                    // const SizedBox(height: 80),
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
