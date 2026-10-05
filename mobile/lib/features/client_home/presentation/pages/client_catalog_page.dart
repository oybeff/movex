import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/constants/material_types.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../materials/presentation/pages/materials_catalog_page.dart';
import '../../../../core/widgets/material_type_icon.dart';

class ClientCatalogPage extends StatefulWidget {
  const ClientCatalogPage({super.key});

  @override
  State<ClientCatalogPage> createState() => _ClientCatalogPageState();
}

class _ClientCatalogPageState extends State<ClientCatalogPage> {
  final EquipmentService _equipmentService = EquipmentService();
  final TextEditingController _searchController = TextEditingController();

  List<EquipmentModel> _equipmentList = [];
  List<EquipmentModel> _filteredList = [];
  bool _isLoading = false;
  String _selectedType = 'all';
  String _selectedStatus = 'all'; // Yangi: status filter
  String _sortBy = 'price_asc';
  Position? _currentLocation; // Yangi: foydalanuvchi joylashuvi

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadEquipment();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Foydalanuvchi joylashuvini olish
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _currentLocation = position;
      });
    } catch (e) {
      print('Location error: $e');
    }
  }

  Future<void> _loadEquipment() async {
    setState(() => _isLoading = true);

    try {
      // Status filter bo'yicha backend'dan ma'lumot olish
      String? statusFilter;
      if (_selectedStatus == 'available') {
        statusFilter = 'available';
      } else if (_selectedStatus == 'busy') {
        statusFilter = 'busy';
      }
      // 'all' bo'lsa, statusFilter null bo'ladi va barcha texnikalar qaytadi

      final equipment = await _equipmentService.getEquipmentList(
        status: statusFilter,
        limit: 100,
      );

      setState(() {
        _equipmentList = equipment;
        _filteredList = equipment;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('equipment.load_error'.tr())),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredList = _equipmentList.where((eq) {
        // Search filter
        // Qidiruv tur KODI bo'yicha emas, foydalanuvchi ko'rayotgan NOM
        // bo'yicha ishlashi kerak: "ekskavator" deb yozganda 'excavator'
        // kodli texnika topilsin
        final query = _searchController.text.toLowerCase();
        final searchMatch = query.isEmpty ||
            EquipmentTypes.label(eq.type).toLowerCase().contains(query) ||
            eq.type.toLowerCase().contains(query) ||
            eq.model.toLowerCase().contains(query);

        // Type filter
        final typeMatch = _selectedType == 'all' || eq.type == _selectedType;

        // Status filter
        final statusMatch = _selectedStatus == 'all' ||
            (_selectedStatus == 'available' && eq.status == 'available' && (eq.available ?? false)) ||
            (_selectedStatus == 'busy' && (eq.status != 'available' || !(eq.available ?? true)));

        return searchMatch && typeMatch && statusMatch;
      }).toList();

      // Sort
      if (_sortBy == 'status') {
        // Avval "Bo'sh" (available), keyin "Band" (busy)
        _filteredList.sort((a, b) {
          final aAvailable = a.status == 'available' && (a.available ?? false);
          final bAvailable = b.status == 'available' && (b.available ?? false);
          if (aAvailable && !bAvailable) return -1;
          if (!aAvailable && bAvailable) return 1;
          return 0;
        });
      } else if (_sortBy == 'price_asc') {
        // ...Value getterlari — matnni emas, sonni solishtiradi.
        _filteredList
            .sort((a, b) => a.pricePerDayValue.compareTo(b.pricePerDayValue));
      } else if (_sortBy == 'price_desc') {
        _filteredList
            .sort((a, b) => b.pricePerDayValue.compareTo(a.pricePerDayValue));
      } else if (_sortBy == 'name') {
        _filteredList.sort((a, b) => (a.model ?? '').compareTo(b.model ?? ''));
      }
    });
  }

  /// Filtrda ko'rsatiladigan turlar — faqat ro'yxatda bor texnika turlari.
  /// Bular kodlar ('excavator'), nomi EquipmentTypes.label orqali olinadi.
  List<String> get _equipmentTypes {
    final types = _equipmentList.map((e) => e.type).toSet().toList()..sort();
    return ['all', ...types];
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'common.filter_sort'.tr(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Type filter
              Text(
                'equipment.type'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _equipmentTypes.map((type) {
                  final isSelected = _selectedType == type;
                  return FilterChip(
                    // Bazada tur KODI turadi ('excavator'), foydalanuvchiga esa
                    // uning tilidagi nomi ko'rsatilishi kerak
                    label: Text(
                      type == 'all'
                          ? 'common.all'.tr()
                          : EquipmentTypes.label(type),
                    ),
                    avatar: type == 'all'
                        ? null
                        : EquipmentTypeIcon(type, size: 18, color: AppColors.grey),
                    selected: isSelected,
                    onSelected: (selected) {
                      setModalState(() {
                        _selectedType = type;
                      });
                      setState(() {
                        _selectedType = type;
                      });
                      _applyFilters();
                    },
                    selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primaryGreen,
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Status filter
              Text(
                'equipment.status'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text('messages.all'.tr()),
                    selected: _selectedStatus == 'all',
                    onSelected: (selected) {
                      setModalState(() {
                        _selectedStatus = 'all';
                      });
                      setState(() {
                        _selectedStatus = 'all';
                      });
                      _loadEquipment();
                    },
                    selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primaryGreen,
                  ),
                  FilterChip(
                    label: Text('messages.available'.tr()),
                    selected: _selectedStatus == 'available',
                    onSelected: (selected) {
                      setModalState(() {
                        _selectedStatus = 'available';
                      });
                      setState(() {
                        _selectedStatus = 'available';
                      });
                      _loadEquipment();
                    },
                    selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primaryGreen,
                  ),
                  FilterChip(
                    label: Text('messages.busy'.tr()),
                    selected: _selectedStatus == 'busy',
                    onSelected: (selected) {
                      setModalState(() {
                        _selectedStatus = 'busy';
                      });
                      setState(() {
                        _selectedStatus = 'busy';
                      });
                      _loadEquipment();
                    },
                    selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primaryGreen,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Sort options
              Text(
                'common.sort'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: Text('messages.sort_available_first'.tr()),
                value: 'status',
                groupValue: _sortBy,
                onChanged: (value) {
                  if (value != null) {
                    setModalState(() {
                      _sortBy = value;
                    });
                    setState(() {
                      _sortBy = value;
                    });
                    _applyFilters();
                  }
                },
                activeColor: AppColors.primaryGreen,
              ),
              RadioListTile<String>(
                title: Text('common.price_low_high'.tr()),
                value: 'price_asc',
                groupValue: _sortBy,
                onChanged: (value) {
                  if (value != null) {
                    setModalState(() {
                      _sortBy = value;
                    });
                    setState(() {
                      _sortBy = value;
                    });
                    _applyFilters();
                  }
                },
                activeColor: AppColors.primaryGreen,
              ),
              RadioListTile<String>(
                title: Text('common.price_high_low'.tr()),
                value: 'price_desc',
                groupValue: _sortBy,
                onChanged: (value) {
                  if (value != null) {
                    setModalState(() {
                      _sortBy = value;
                    });
                    setState(() {
                      _sortBy = value;
                    });
                    _applyFilters();
                  }
                },
                activeColor: AppColors.primaryGreen,
              ),
              RadioListTile<String>(
                title: Text('common.name'.tr()),
                value: 'name',
                groupValue: _sortBy,
                onChanged: (value) {
                  if (value != null) {
                    setModalState(() {
                      _sortBy = value;
                    });
                    setState(() {
                      _sortBy = value;
                    });
                    _applyFilters();
                  }
                },
                activeColor: AppColors.primaryGreen,
              ),

              const SizedBox(height: 16),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'common.apply'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text('client.catalog'.tr()),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _materialsStrip(),
            // Search and filters
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'equipment.search'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (_) => _applyFilters(),
                  ),
                  const SizedBox(height: 12),
                  // Filter button
                  OutlinedButton.icon(
                    onPressed: _showFilterBottomSheet,
                    icon: const Icon(Icons.filter_list),
                    label: Text('common.filter_sort'.tr(), style: const TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Equipment list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
                  : _filteredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.construction, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'equipment.not_found'.tr(),
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadEquipment,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) {
                              final equipment = _filteredList[index];
                              return _buildEquipmentCard(equipment);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Qurilish materiallari — katalogning eng tepasida.
  ///
  /// Nega shu yerda. Odam texnika qidirib kelganda ham unga g'isht,
  /// sement va qum kerak bo'ladi; alohida bo'limga yashirilsa, uni
  /// umuman topmaydi. Bosilgan kategoriya materiallar katalogini
  /// darhol o'sha tur bilan ochadi.
  Widget _materialsStrip() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'materials.strip_title'.tr(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MaterialsCatalogPage(),
                    ),
                  ),
                  child: Text('common.all'.tr(),
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 86,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: MaterialTypes.codes.length,
              itemBuilder: (context, i) {
                final code = MaterialTypes.codes[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MaterialsCatalogPage(initialType: code),
                    ),
                  ),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: MaterialTypeIcon(code, size: 30),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          MaterialTypes.label(code),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const BorderRadius _cardTopRadius =
      BorderRadius.vertical(top: Radius.circular(16));

  Widget _buildEquipmentCard(EquipmentModel equipment) {
    // Masofa hisoblash
    String? distanceText;
    if (_currentLocation != null && equipment.latitude != null && equipment.longitude != null) {
      final techLat = double.tryParse(equipment.latitude!);
      final techLng = double.tryParse(equipment.longitude!);
      if (techLat != null && techLng != null) {
        final distance = _calculateDistance(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          techLat,
          techLng,
        );
        if (distance < 1) {
          distanceText = '${(distance * 1000).toStringAsFixed(0)} m';
        } else {
          distanceText = '${distance.toStringAsFixed(1)} km';
        }
      }
    }

    // Holat tekshirish
    // Faqat status='available' bo'lsa buyurtma berish mumkin
    // busy va maintenance holatida ham texnika ko'rsatiladi, lekin buyurtma berib bo'lmaydi
    final isAvailable = equipment.status == 'available';

    return GestureDetector(
      onTap: () => _showEquipmentDetails(equipment),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: equipment.photos != null && equipment.photos!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Image.network(
                            AppConfig.mediaUrl(equipment.photos!.first.url),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            // Rasm bo'lmasa — umumiy belgi emas, aynan shu
                            // texnika turining ikonkasi
                            errorBuilder: (_, __, ___) => EquipmentPhotoPlaceholder(
                              equipment.type,
                              borderRadius: _cardTopRadius,
                            ),
                          ),
                        )
                      : EquipmentPhotoPlaceholder(
                          equipment.type,
                          borderRadius: _cardTopRadius,
                        ),
                ),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EquipmentTypeChip(
                          equipment.type,
                          iconSize: 14,
                          textStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          equipment.model ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              NumberFormatter.formatCurrency(equipment.pricePerDay),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            Text(
                              ' ${'common.currency'.tr()}/${'common.day'.tr()}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Holat badge'i (o'ng yuqori burchak)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAvailable ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isAvailable
                        ? 'messages.available'.tr()
                        : (equipment.status == 'maintenance'
                            ? 'Ta\'mirda'
                            : 'messages.busy'.tr()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Masofa (agar mavjud bo'lsa)
            if (distanceText != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEquipmentDetails(EquipmentModel equipment) {
    // Faqat status='available' bo'lsa buyurtma berish mumkin
    final isAvailable = equipment.status == 'available';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Stack(
            children: [
              ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Rasm (agar mavjud bo'lsa)
                  if (equipment.photos.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        AppConfig.mediaUrl(equipment.photos.first.url),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 200,
                          color: Colors.grey[300],
                          child: Center(
                            child: EquipmentTypeIcon(equipment.type, size: 60),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Nomi va holati
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${EquipmentTypes.label(equipment.type)} ${equipment.model}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAvailable ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isAvailable
                            ? 'messages.available'.tr()
                            : (equipment.status == 'maintenance'
                                ? 'Ta\'mirda'
                                : 'messages.busy'.tr()),
                          style: TextStyle(
                            color: isAvailable ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Tavsif
                  if (equipment.description != null && equipment.description!.isNotEmpty) ...[
                    Text(
                      equipment.description!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Texnik ma'lumotlar
                  Text(
                    'equipment.technical_info'.tr(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow('equipment.year'.tr(), equipment.year?.toString() ?? '-'),
                  _buildDetailRow('equipment.power_hp'.tr(), equipment.powerHp != null ? '${equipment.powerHp} HP' : '-'),
                  _buildDetailRow('equipment.payload_kg'.tr(), equipment.payloadKg != null ? '${equipment.payloadKg} kg' : '-'),
                  if (equipment.dimensions != null && equipment.dimensions!.isNotEmpty)
                    _buildDetailRow('equipment.dimensions'.tr(), equipment.dimensions!),
                  if (equipment.address != null && equipment.address!.isNotEmpty)
                    _buildDetailRow('equipment.address'.tr(), equipment.address!),

                  const Divider(height: 32),

                  // Narxlar
                  Text(
                    'equipment.prices'.tr(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (equipment.pricePerHour != null && equipment.pricePerHour!.isNotEmpty)
                    _buildPriceRow('equipment.price_per_hour'.tr(), equipment.pricePerHour!, 'common.hour'.tr()),
                  if (equipment.pricePerShift != null && equipment.pricePerShift!.isNotEmpty)
                    _buildPriceRow('equipment.price_per_shift'.tr(), equipment.pricePerShift!, 'common.shift'.tr()),
                  _buildPriceRow('equipment.price_per_day'.tr(), equipment.pricePerDay, 'common.day'.tr()),
                  if (equipment.deliveryPricePerKm != null && equipment.deliveryPricePerKm!.isNotEmpty)
                    // Faqat "km": _buildPriceRow o'zi "so'm/" ni qo'shadi.
                    // Ilgari bu yerda "so'm/km" uzatilardi va kartochkada
                    // "15 000 сум/сум/км" chiqardi.
                    _buildPriceRow('equipment.delivery'.tr(), equipment.deliveryPricePerKm!, 'common.km'.tr()),

                  const SizedBox(height: 24),

                  // Ijaraga olish tugmasi
                  ElevatedButton(
                    onPressed: isAvailable ? () async {
                      Navigator.pop(context);
                      final result = await context.push('/rent-equipment', extra: equipment);
                      if (result == true && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('rent.booking_success'.tr()),
                            backgroundColor: AppColors.primaryGreen,
                          ),
                        );
                      }
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isAvailable
                        ? 'client.rent'.tr()
                        : (equipment.status == 'maintenance'
                            ? 'Ta\'mirda - buyurtma berib bo\'lmaydi'
                            : 'equipment.busy_cannot_order'.tr()),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),

              // X tugmasi
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String price, String unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Text(
                NumberFormatter.formatCurrency(price),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryGreen,
                ),
              ),
              Text(
                ' ${'common.currency'.tr()}/$unit',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Masofa hisoblash (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}

