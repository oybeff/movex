import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/constants/equipment_types.dart';

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

  Future<void> _fetchEquipment() async {
    setState(() => _isLoading = true);

    try {
      final equipment = await _equipmentService.getEquipmentList(
        ownerOnly: true,
        limit: 100,
      );

      setState(() {
        equipmentList = equipment;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('equipment.load_error'.tr())),
        );
      }
    }
  }

  String _mapStatus(String? backendStatus) {
    switch (backendStatus) {
      case "available":
        return 'equipment.status_available'.tr();
      case "busy":
        return 'equipment.status_busy'.tr();
      case "repair":
        return 'equipment.status_repair'.tr();
      default:
        return 'equipment.status_unknown'.tr();
    }
  }

  List<EquipmentModel> get filteredList {
    return equipmentList.where((eq) {
      final matchesSearch = (eq.model ?? '')
          .toLowerCase()
          .contains(_searchController.text.toLowerCase());
      final matchesFilter =
          _filterStatus == 'all' || eq.status == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();
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

  Future<void> _deleteEquipment(int equipmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('equipment.delete_confirm'.tr()),
        content: Text('equipment.delete_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
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
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('equipment.delete_error'.tr())),
          );
        }
      }
    }
  }

  Future<void> _showChangeStatusDialog(EquipmentModel equipment) async {
    String? selectedStatus = equipment.status;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text('messages.change_equipment_status'.tr(), style: const TextStyle(color: AppColors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${EquipmentTypes.label(equipment.type)} ${equipment.model}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: Text('messages.status_available'.tr()),
                subtitle: Text('messages.status_available_desc'.tr()),
                value: 'available',
                groupValue: selectedStatus,
                activeColor: AppColors.primaryGreen,
                onChanged: (value) {
                  setState(() => selectedStatus = value);
                },
              ),
              RadioListTile<String>(
                title: Text('messages.status_busy'.tr()),
                subtitle: Text('messages.status_busy_desc'.tr()),
                value: 'busy',
                groupValue: selectedStatus,
                activeColor: Colors.orange,
                onChanged: (value) {
                  setState(() => selectedStatus = value);
                },
              ),
              RadioListTile<String>(
                title: Text('messages.status_maintenance'.tr()),
                subtitle: Text('messages.status_maintenance_desc'.tr()),
                value: 'maintenance',
                groupValue: selectedStatus,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() => selectedStatus = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: selectedStatus == equipment.status
                  ? null
                  : () => Navigator.pop(context, selectedStatus),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != equipment.status) {
      try {
        // Loading dialog
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            ),
          );
        }

        await _equipmentService.updateEquipmentStatus(equipment.id, result);

        if (mounted) {
          Navigator.pop(context); // Close loading dialog

          // Success dialog
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.primaryGreen),
                  const SizedBox(width: 8),
                  Text('messages.success'.tr()),
                ],
              ),
              content: Text('messages.status_changed'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('messages.ok'.tr()),
                ),
              ],
            ),
          );

          _fetchEquipment();
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog

          // Error dialog
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Text('errors.error'.tr()),
                ],
              ),
              content: Text(e.toString()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('messages.ok'.tr()),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  String _getStatusName(String status) {
    switch (status) {
      case 'available':
        return 'Bo\'sh';
      case 'busy':
        return 'Band';
      case 'maintenance':
        return 'Ta\'mirda';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cardRadius = 16;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('equipment.my_equipment'.tr()),
        backgroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await context.push('/add-equipment');
              if (result == true) {
                _fetchEquipment();
              }
            },
            tooltip: 'equipment.add'.tr(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Поиск и фильтр
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'equipment.search'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                    onTapOutside: (event) => FocusScope.of(context).unfocus(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                // Zamonaviy Dropdown Filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterStatus,
                      icon: const Icon(Icons.filter_list, color: AppColors.primaryGreen),
                      elevation: 2,
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Row(
                            children: [
                              const Icon(Icons.all_inclusive, size: 18, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('common.all'.tr()),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'available',
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 18, color: Colors.green),
                              const SizedBox(width: 8),
                              Text('equipment.status_available'.tr()),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'busy',
                          child: Row(
                            children: [
                              const Icon(Icons.work, size: 18, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text('equipment.status_busy'.tr()),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'repair',
                          child: Row(
                            children: [
                              const Icon(Icons.build, size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text('equipment.status_repair'.tr()),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _filterStatus = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Список техники
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                  : filteredList.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.construction, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'equipment.not_found'.tr(),
                              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                            ),
                          ],
                        ),)
                      : RefreshIndicator(
                          onRefresh: _fetchEquipment,
                          child: ListView.separated(
                            itemCount: filteredList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final eq = filteredList[index];
                              return GestureDetector(
                                onTap: () {
                                  context.push('/equipment-detail', extra: eq);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(cardRadius),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: _statusColor(eq.status),
                                      child: const Icon(
                                        Icons.construction,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${EquipmentTypes.label(eq.type)} ${eq.model ?? ''}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${'equipment.status'.tr()}: ${_mapStatus(eq.status)}',
                                            style: TextStyle(
                                              color: _statusColor(eq.status),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (eq.pricePerDay != null)
                                            Text(
                                              '${eq.pricePerDay} ${'common.currency'.tr()}/${'common.day'.tr()}',
                                              style: const TextStyle(color: Colors.grey),
                                            ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.more_vert,
                                          color: Colors.black87,
                                          size: 20,
                                        ),
                                      ),
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      color: Colors.white,
                                      offset: const Offset(0, 40),
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          final result = await context.push('/edit-equipment/${eq.id}');
                                          if (result == true) {
                                            _fetchEquipment();
                                          }
                                        } else if (value == 'delete') {
                                          await _deleteEquipment(eq.id);
                                        } else if (value == 'change_status') {
                                          await _showChangeStatusDialog(eq);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.edit_outlined,
                                                  color: AppColors.primaryGreen,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'common.edit'.tr(),
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(height: 1),
                                        PopupMenuItem(
                                          value: 'change_status',
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.swap_horiz,
                                                  color: Colors.blue,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'messages.change_equipment_status'.tr(),
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(height: 1),
                                        PopupMenuItem(
                                          value: 'delete',
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'common.delete'.tr(),
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
