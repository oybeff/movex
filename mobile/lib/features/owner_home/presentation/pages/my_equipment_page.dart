import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../../core/widgets/bottom_nav_space.dart';
import '../../../driver/presentation/driver_equipment_step.dart';
import '../../../driver/presentation/driver_ui.dart';
import '../../../driver/presentation/delivery_setup_page.dart';
import '../../../driver/data/delivery_api.dart';
import '../../../../core/app_flavor.dart';
import '../../../materials/presentation/pages/my_materials_page.dart';
import '../../../../core/widgets/h_icon.dart';

class MyEquipmentPage extends StatefulWidget {
  const MyEquipmentPage({super.key});

  @override
  State<MyEquipmentPage> createState() => _MyEquipmentPageState();
}

class _MyEquipmentPageState extends State<MyEquipmentPage> {
  final TextEditingController _searchController = TextEditingController();
  final EquipmentService _equipmentService = EquipmentService();

  String _filterStatus = 'all';
  List<EquipmentModel> equipmentList = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchEquipment();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchEquipment() async {
    setState(() => _isLoading = true);
    try {
      final equipment = await _equipmentService.getEquipmentList(
        ownerOnly: true,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          equipmentList = equipment;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('equipment.load_error'.tr())),
        );
      }
    }
  }

  List<EquipmentModel> get filteredList {
    final query = _searchController.text.trim().toLowerCase();
    return equipmentList.where((eq) {
      final matchesSearch = query.isEmpty ||
          EquipmentTypes.label(eq.type).toLowerCase().contains(query) ||
          eq.type.toLowerCase().contains(query) ||
          eq.model.toLowerCase().contains(query);
      final matchesFilter =
          _filterStatus == 'all' || eq.status == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _deleteEquipment(int equipmentId) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('equipment.delete_confirm'.tr(), style: AppTypography.h2),
            const SizedBox(height: 8),
            Text(
              'equipment.delete_message'.tr(),
              style: const TextStyle(fontSize: 14, color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 20),
            DPrimary(
              'common.delete'.tr(),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 8),
            DSecondary(
              'common.cancel'.tr(),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _equipmentService.deleteEquipment(equipmentId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('equipment.deleted'.tr())),
          );
        }
        _fetchEquipment();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('equipment.delete_error'.tr())),
          );
        }
      }
    }
  }

  Future<void> _showChangeStatusSheet(EquipmentModel equipment) async {
    final newStatus = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('messages.change_equipment_status'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text(
              '${EquipmentTypes.label(equipment.type)} ${equipment.model}',
              style: const TextStyle(fontSize: 14, color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 16),
            _statusOption(
              ctx: ctx,
              title: 'messages.status_available'.tr(),
              subtitle: 'messages.status_available_desc'.tr(),
              value: 'available',
              selected: equipment.status == 'available',
              color: AppPalette.textSuccess,
              bgColor: AppPalette.successSubtle,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: 8),
            _statusOption(
              ctx: ctx,
              title: 'messages.status_busy'.tr(),
              subtitle: 'messages.status_busy_desc'.tr(),
              value: 'busy',
              selected: equipment.status == 'busy',
              color: AppPalette.textOnAccent,
              bgColor: AppPalette.accentSubtle,
              icon: Icons.access_time_rounded,
            ),
            const SizedBox(height: 8),
            _statusOption(
              ctx: ctx,
              title: 'messages.status_maintenance'.tr(),
              subtitle: 'messages.status_maintenance_desc'.tr(),
              value: 'maintenance',
              selected: equipment.status == 'maintenance' || equipment.status == 'repair',
              color: AppPalette.textDanger,
              bgColor: AppPalette.dangerSubtle,
              icon: Icons.build_outlined,
            ),
            const SizedBox(height: 16),
            DSecondary('common.cancel'.tr(), onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );

    if (newStatus != null && newStatus != equipment.status) {
      try {
        await _equipmentService.updateEquipmentStatus(equipment.id, newStatus);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('messages.status_changed'.tr())),
          );
          _fetchEquipment();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('errors.something_went_wrong'.tr())),
          );
        }
      }
    }
  }

  Widget _statusOption({
    required BuildContext ctx,
    required String title,
    required String subtitle,
    required String value,
    required bool selected,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? bgColor : AppPalette.page,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.15) : AppPalette.surface,
                shape: BoxShape.circle,
              ),
              child: HIcon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                ],
              ),
            ),
            if (selected)
              HIcon(Icons.check_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEquipmentModal() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('equipment.add'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text(
              'Qanday usulda texnika qoʻshmoqchisiz?',
              style: const TextStyle(fontSize: 14, color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('quick'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DChip.blueBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const HIcon(Icons.flash_on_rounded, color: AppPalette.brand, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Tezkor qoʻshish (1 daqiqa)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppPalette.brand)),
                          SizedBox(height: 2),
                          Text('Model, davlat raqami va narx — buyurtmalar qabul qilish uchun kifoya', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                        ],
                      ),
                    ),
                    const HIcon(Icons.chevron_right_rounded, color: AppPalette.brand),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('full'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.page,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const HIcon(Icons.description_outlined, color: AppPalette.textPrimary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Batafsil maʼlumotlar bilan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppPalette.textPrimary)),
                          SizedBox(height: 2),
                          Text('Rasmlar, oʻlchamlar, tavsif va xaritadagi aniq manzil', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                        ],
                      ),
                    ),
                    const HIcon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DSecondary('common.cancel'.tr(), onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );

    if (choice == 'quick') {
      if (!mounted) return;
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const DriverEquipmentStep()),
      );
      if (added == true) _fetchEquipment();
    } else if (choice == 'full') {
      if (!mounted) return;
      final added = await context.push<bool>('/add-equipment');
      if (added == true) _fetchEquipment();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        title: Text(
          'equipment.my_equipment'.tr(),
          style: AppTypography.h2,
        ),
        backgroundColor: AppPalette.surface,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyMaterialsPage()),
            ),
            icon: const HIcon(Icons.category_outlined, size: 16),
            label: Text(
              'materials.title'.tr(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const HIcon(Icons.add_circle_outline_rounded, color: AppPalette.brand, size: 26),
            tooltip: 'equipment.add'.tr(),
            onPressed: _showAddEquipmentModal,
          ),
        ],
      ),
      body: Column(
        children: [
          // Haydovchi ilovasida yuk mashinasi ham shu yerda (24.11.2026:
          // profildagi alohida «Yuk mashinam» olib tashlandi)
          if (AppFlavor.isDriver) _TruckTile(),
          // Поиск
          Container(
            color: AppPalette.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'equipment.search'.tr(),
                    hintStyle: const TextStyle(color: AppPalette.textSecondary, fontSize: 14),
                    prefixIcon: const HIcon(Icons.search_rounded, color: AppPalette.iconSecondary),
                    filled: true,
                    fillColor: AppPalette.page,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                // Фильтр-чипы
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'common.all'.tr()),
                      const SizedBox(width: 8),
                      _filterChip('available', 'equipment.status_available'.tr()),
                      const SizedBox(width: 8),
                      _filterChip('busy', 'equipment.status_busy'.tr()),
                      const SizedBox(width: 8),
                      _filterChip('repair', 'equipment.status_repair'.tr()),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Список техники
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
                : filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const HIcon(Icons.construction_rounded, size: 64, color: AppPalette.iconSecondary),
                            const SizedBox(height: 12),
                            Text(
                              'equipment.not_found'.tr(),
                              style: const TextStyle(fontSize: 15, color: AppPalette.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _showAddEquipmentModal,
                              icon: const HIcon(Icons.add),
                              label: Text('equipment.add'.tr()),
                              style: FilledButton.styleFrom(backgroundColor: AppPalette.brand),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchEquipment,
                        color: AppPalette.brand,
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomNavInset(context) + 16),
                          itemCount: filteredList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final eq = filteredList[index];
                            return _equipmentCard(eq);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String status, String label) {
    final selected = _filterStatus == status;
    return InkWell(
      onTap: () => setState(() => _filterStatus = status),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppPalette.brand : AppPalette.page,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : AppPalette.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _equipmentCard(EquipmentModel eq) {
    Widget statusChip;
    switch (eq.status) {
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

    final pricePerHour = eq.pricePerHourValue ??
        (eq.pricePerDayValue > 0 ? (eq.pricePerDayValue / 8).round() : null);

    return InkWell(
      onTap: () => context.push('/equipment-detail', extra: eq),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: DChip.blueBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: EquipmentTypeIcon(
                  eq.type,
                  size: 28,
                  color: AppPalette.brand,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${EquipmentTypes.label(eq.type)} ${eq.model}'.trim(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      statusChip,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (pricePerHour != null)
                        Text(
                          '${NumberFormatter.formatCurrency(pricePerHour)} soʻm/soat',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.brand),
                        ),
                      if (pricePerHour != null && eq.pricePerDayValue > 0)
                        const Text(' · ', style: TextStyle(color: AppPalette.textSecondary)),
                      if (eq.pricePerDayValue > 0)
                        Text(
                          '${NumberFormatter.formatCurrency(eq.pricePerDayValue.round())} soʻm/kun',
                          style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const HIcon(Icons.more_vert_rounded, color: AppPalette.iconSecondary, size: 20),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: AppPalette.surface,
              onSelected: (value) async {
                if (value == 'edit') {
                  final result = await context.push('/edit-equipment/${eq.id}');
                  if (result == true) _fetchEquipment();
                } else if (value == 'delete') {
                  await _deleteEquipment(eq.id);
                } else if (value == 'change_status') {
                  await _showChangeStatusSheet(eq);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'change_status',
                  child: Row(
                    children: [
                      const HIcon(Icons.swap_horiz_rounded, color: AppPalette.brand, size: 18),
                      const SizedBox(width: 8),
                      Text('messages.change_equipment_status'.tr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const HIcon(Icons.edit_outlined, color: AppPalette.textPrimary, size: 18),
                      const SizedBox(width: 8),
                      Text('common.edit'.tr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const HIcon(Icons.delete_outline_rounded, color: AppPalette.textDanger, size: 18),
                      const SizedBox(width: 8),
                      Text('common.delete'.tr(), style: const TextStyle(color: AppPalette.textDanger)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// «Yuk mashinam» — yuk tashish va material yetkazish uchun mashina.
class _TruckTile extends StatefulWidget {
  @override
  State<_TruckTile> createState() => _TruckTileState();
}

class _TruckTileState extends State<_TruckTile> {
  DeliveryProfile? _p;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await DeliveryApi().profile();
      if (mounted) setState(() => _p = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final has = p?.registered ?? false;
    return Material(
      color: AppPalette.surface,
      child: ListTile(
        leading: const HIcon(Icons.local_shipping_outlined, color: AppPalette.brand),
        title: Text('driver.delivery_title'.tr(), style: AppTypography.bodyMedium),
        subtitle: Text(has
            ? [p!.vehicleName, p.plate].whereType<String>().where((x) => x.isNotEmpty).join(' · ')
            : 'driver.truck_add'.tr()),
        trailing: const HIcon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliverySetupPage()));
          _load();
        },
      ),
    );
  }
}
