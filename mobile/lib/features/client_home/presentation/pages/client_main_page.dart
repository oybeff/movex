import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:movex_go/core/constants/app_config.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import 'package:movex_go/core/constants/equipment_types.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../../core/widgets/map_or_placeholder.dart';

class ClientMainPage extends StatefulWidget {
  const ClientMainPage({super.key});

  @override
  State<ClientMainPage> createState() => _ClientMainPageState();
}

class _ClientMainPageState extends State<ClientMainPage> with WidgetsBindingObserver {
  YandexMapController? _controller;
  final EquipmentService _equipmentService = EquipmentService();
  List<EquipmentModel> _techList = [];
  bool _isLoading = true;

  Point? _currentLocation;
  final List<MapObject> _mapObjects = [];
  EquipmentModel? _selectedTech;
  // Brauzerda darhol ro'yxat ochiladi: xarita u yerda ishlamaydi
  // (yandex_mapkit faqat Android va iOS uchun), va mijoz bo'sh ekranga
  // tushib qolardi — ilovaning birinchi ko'rinishi shu.
  bool _showList = MapOrPlaceholder.isWeb;
  bool _isRequestingPermission = false;

  // Xarita stili
  MapType _mapType = MapType.map;

  // O'zbekiston markazi
  static const Point _uzbekistanCenter = Point(latitude: 41.2995, longitude: 69.2401);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Foydalanuvchi sozlamalardan qaytganda
    if (state == AppLifecycleState.resumed && !_isRequestingPermission) {
      print('DEBUG: App resumed, checking location again');
      _checkLocationAfterResume();
    }
  }

  Future<void> _checkLocationAfterResume() async {
    // Agar lokatsiya hali olinmagan bo'lsa, qayta tekshiramiz
    if (_currentLocation == null) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('DEBUG: After resume - Location service enabled: $serviceEnabled');

      if (serviceEnabled) {
        // Service yoniq - ruxsatni tekshiramiz
        final permissionResult = await PermissionService.requestLocationPermission();
        print('DEBUG: After resume - Permission granted: ${permissionResult.isGranted}');

        if (permissionResult.isGranted) {
          await _getCurrentLocation();
        }
      }
    }
  }

  Future<void> _initializeApp() async {
    // Birinchi navbatda lokatsiya ruxsatini so'raymiz
    await _requestLocationPermission();
    // Keyin texnikalarni yuklaymiz
    await _loadEquipment();
  }

  Future<void> _requestLocationPermission() async {
    // 1. Avval location service yoniqligini tekshiramiz
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('DEBUG: Location service enabled: $serviceEnabled');

    if (!serviceEnabled) {
      print('DEBUG: Location service disabled, showing dialog');
      // Location service o'chirilgan - foydalanuvchiga yoqishni so'raymiz
      if (mounted) {
        await _showLocationServiceDialog();
      }
      return;
    }

    // 2. Location service yoniq - endi ruxsat so'raymiz
    print('DEBUG: Requesting location permission');
    final permissionResult = await PermissionService.requestLocationPermission();
    print('DEBUG: Permission result: ${permissionResult.isGranted}');

    if (!permissionResult.isGranted) {
      // Agar ruxsat berilmagan bo'lsa, foydalanuvchiga xabar beramiz
      print('DEBUG: Permission not granted, showing dialog');
      if (mounted) {
        _showLocationPermissionDialog(permissionResult);
      }
      // Ruxsat berilmasa ham, O'zbekiston markaziga o'tamiz
      return;
    }

    // Agar ruxsat berilgan bo'lsa, joriy joylashuvni olamiz
    print('DEBUG: Permission granted, getting location');
    await _getCurrentLocation();
  }

  Future<void> _showLocationServiceDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('messages.location_service_disabled_title'.tr()),
        content: Text(
          'messages.location_service_disabled_message'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('messages.later'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text(
              'common.enable'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      // Foydalanuvchi "Yoqish" tugmasini bosdi
      // System location settings ni ochamiz
      setState(() => _isRequestingPermission = true);

      final opened = await Geolocator.openLocationSettings();
      print('DEBUG: Location settings opened: $opened');

      // Sozlamalar ochildi yoki ochilmadi, foydalanuvchi qaytganda tekshiramiz
      // didChangeAppLifecycleState orqali avtomatik tekshiriladi
      setState(() => _isRequestingPermission = false);
    }
  }

  void _showLocationPermissionDialog(LocationPermissionResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('messages.location_permission'.tr()),
        content: Text(
          result.message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('messages.later'.tr()),
          ),
          if (result.canOpenSettings)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: Text(
                'settings.title'.tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _currentLocation = Point(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });

      // Markerlarni yangilaymiz
      await _addTechMarkers();

      // Agar xarita tayyor bo'lsa, kamerani o'tkazamiz
      if (_controller != null && _currentLocation != null) {
        _controller!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentLocation!, zoom: 12),
          ),
        );
      }
    } catch (e) {
      print('Error getting location: $e');
      // Xatolik bo'lsa ham davom etamiz
    }
  }

  Future<void> _loadEquipment() async {
    try {
      setState(() => _isLoading = true);
      final equipment = await _equipmentService.getEquipmentList(limit: 100);
      setState(() {
        _techList = equipment;
        _isLoading = false;
      });
      _addTechMarkers();
    } catch (e) {
      print('Load equipment error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addTechMarkers() async {
    _mapObjects.clear();

    for (var tech in _techList) {
      if (tech.latitude != null && tech.longitude != null) {
        try {
          final lat = double.parse(tech.latitude!);
          final lng = double.parse(tech.longitude!);
          final isAvailable = tech.status == 'available' && (tech.available ?? false);

          // Har bir tur o'z markeriga ega — ilgari butun texnika bitta
          // ekskavator belgisi bilan ko'rsatilardi.
          final icon = BitmapDescriptor.fromAssetImage(
            EquipmentTypes.markerAsset(tech.type),
          );
          _mapObjects.add(
            PlacemarkMapObject(
              mapId: MapObjectId('tech_${tech.id}'),
              point: Point(latitude: lat, longitude: lng),
              icon: PlacemarkIcon.single(
                PlacemarkIconStyle(
                  image: icon,
                  // Rasm 256x308: 256 px kvadrat va pastida 52 px dum.
                  // 0.42 => ekranda ~108 px kenglik.
                  scale: 0.42,
                  // Anchor rasmning nisbiy nuqtasi: (0.5, 1.0) — dumning
                  // uchi. Aynan shu nuqta koordinataga tushishi kerak,
                  // aks holda marker texnikadan yuqorida turadi.
                  anchor: const Offset(0.5, 1.0),
                ),
              ),
              opacity: isAvailable ? 1.0 : 0.5,
              onTap: (mapObject, point) {
                setState(() => _selectedTech = tech);
                _animateToSelectedTech();
              },
            ),
          );
        } catch (e) {
          print('Error parsing coordinates: $e');
        }
      }
    }

    if (_currentLocation != null) {
      final myIcon = BitmapDescriptor.fromAssetImage('assets/my_location.png');
      _mapObjects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('my_location'),
          point: _currentLocation!,
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(image: myIcon, scale: 0.10),
          ),
          opacity: 1.0
        ),
      );
    }

    setState(() {});
  }



  void _moveToUzbekistan() {
    if (_controller != null) {
      _controller!.moveCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: _uzbekistanCenter, zoom: 6),
        ),
      );
    }
  }

  Future<void> _animateToPoint(Point target, {double zoom = 15}) async {
    if (_controller != null) {
      await _controller!.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: zoom)),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.0),
      );
    }
  }

  Future<void> _animateToSelectedTech() async {
    if (_selectedTech != null && _selectedTech!.latitude != null && _selectedTech!.longitude != null) {
      try {
        final lat = double.parse(_selectedTech!.latitude!);
        final lng = double.parse(_selectedTech!.longitude!);
        final point = Point(latitude: lat, longitude: lng);
        await _animateToPoint(point);
        _showBottomSheet();
      } catch (e) {
        print('Error animating: $e');
      }
    }
  }

  void _showBottomSheet() {
    if (_selectedTech == null) return;

    final imageUrl = _selectedTech!.photos.isNotEmpty ? _selectedTech!.photos.first.url : null;
    final isAvailable = _selectedTech!.status == 'available' && (_selectedTech!.available ?? false);

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

                  // Rasm
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        AppConfig.mediaUrl(imageUrl),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => SizedBox(
                          height: 200,
                          child: EquipmentPhotoPlaceholder(
                            _selectedTech!.type,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: EquipmentPhotoPlaceholder(
                        _selectedTech!.type,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Nomi va holati
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${EquipmentTypes.label(_selectedTech!.type)} '
                          '${_selectedTech!.model}',
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
                          isAvailable ? 'messages.available'.tr() : 'messages.busy'.tr(),
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
                  if (_selectedTech!.description != null && _selectedTech!.description!.isNotEmpty) ...[
                    Text(
                      _selectedTech!.description!,
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
                  if (_selectedTech!.year != null)
                    _buildDetailRow('equipment.year'.tr(), _selectedTech!.year.toString()),
                  if (_selectedTech!.powerHp != null)
                    _buildDetailRow('equipment.power'.tr(), '${_selectedTech!.powerHp} HP'),
                  if (_selectedTech!.payloadKg != null)
                    _buildDetailRow('equipment.payload'.tr(), '${_selectedTech!.payloadKg} kg'),
                  if (_selectedTech!.dimensions != null && _selectedTech!.dimensions!.isNotEmpty)
                    _buildDetailRow('equipment.dimensions'.tr(), _selectedTech!.dimensions!),
                  if (_selectedTech!.address != null && _selectedTech!.address!.isNotEmpty)
                    _buildDetailRow('equipment.address'.tr(), _selectedTech!.address!),

                  const Divider(height: 32),

                  // Narxlar
                  Text(
                    'equipment.prices'.tr(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedTech!.pricePerHour != null && _selectedTech!.pricePerHour!.isNotEmpty)
                    _buildPriceRow('equipment.hourly'.tr(), _selectedTech!.pricePerHour!, 'equipment.hour'.tr()),
                  if (_selectedTech!.pricePerShift != null && _selectedTech!.pricePerShift!.isNotEmpty)
                    _buildPriceRow('equipment.shift'.tr(), _selectedTech!.pricePerShift!, 'equipment.shift_unit'.tr()),
                  _buildPriceRow('equipment.daily'.tr(), _selectedTech!.pricePerDay, 'equipment.day'.tr()),

                  const SizedBox(height: 24),

                  // Ijaraga olish tugmasi
                  ElevatedButton(
                    onPressed: isAvailable ? () => _rentEquipment() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'client.rent'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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

  void _rentEquipment() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('messages.rent_equipment'.tr()),
        content: Text('${EquipmentTypes.label(_selectedTech!.type)} '
            '${_selectedTech!.model} '
            '${'messages.rent_equipment_confirm'.tr()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('messages.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/rent-equipment', extra: _selectedTech);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: Text('messages.confirm'.tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _zoomIn() async {
    if (_controller != null) {
      await _controller!.moveCamera(
        CameraUpdate.zoomIn(),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
      );
    }
  }

  Future<void> _zoomOut() async {
    if (_controller != null) {
      await _controller!.moveCamera(
        CameraUpdate.zoomOut(),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
      );
    }
  }

  void _goToMyLocation() {
    if (_currentLocation != null) {
      _animateToPoint(_currentLocation!, zoom: 15);
    }
  }

  void _showMapTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
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
                    'equipment.map_view'.tr(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Map type options
              _buildMapTypeOption(
                MapType.map,
                'Sxema',
                Icons.map_outlined,
                'Standart xarita ko\'rinishi',
              ),
              const SizedBox(height: 12),
              _buildMapTypeOption(
                MapType.satellite,
                'Suniy yo\'ldosh',
                Icons.satellite_alt,
                'Suniy yo\'ldosh tasviri',
              ),
              const SizedBox(height: 12),
              _buildMapTypeOption(
                MapType.hybrid,
                'Gibrid',
                Icons.layers,
                'Sxema + suniy yo\'ldosh',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapTypeOption(MapType type, String title, IconData icon, String description) {
    final isSelected = _mapType == type;

    return InkWell(
      onTap: isSelected ? null : () {
        setState(() {
          _mapType = type;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen.withValues(alpha: 0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryGreen : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.primaryGreen : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Check icon
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryGreen,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  IconData _getMapTypeIcon() {
    switch (_mapType) {
      case MapType.map:
        return Icons.map_outlined;
      case MapType.satellite:
        return Icons.satellite_alt;
      case MapType.hybrid:
        return Icons.layers;
      default:
        return Icons.map_outlined;
    }
  }

  Widget _buildMapButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 24),
        onPressed: onPressed,
        color: AppColors.primaryGreen,
        padding: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Xarita yoki ro'yxat
          if (!_showList)
            MapOrPlaceholder(mapBuilder: (_) => YandexMap(
              mapType: _mapType,
              onMapCreated: (controller) {
                _controller = controller;
                // Agar lokatsiya mavjud bo'lsa, u yerga o'tamiz, aks holda O'zbekistonga
                if (_currentLocation != null) {
                  _controller!.moveCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: _currentLocation!, zoom: 12),
                    ),
                  );
                } else {
                  _moveToUzbekistan();
                }
              },
              mapObjects: _mapObjects,
            ))
          else
            _buildListView(),

          // Loading indicator
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),

          // Xarita stili tugmasi (yuqori o'ng tomonda, faqat xarita ko'rinishida)
          if (!_showList)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: _buildMapButton(_getMapTypeIcon(), _showMapTypeDialog),
            ),

          // Map control tugmalari (faqat xarita ko'rinishida)
          if (!_showList)
            Positioned(
              right: 16,
              bottom: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMapButton(Icons.add, _zoomIn),
                  const SizedBox(height: 8),
                  _buildMapButton(Icons.remove, _zoomOut),
                  const SizedBox(height: 8),
                  if (_currentLocation != null)
                    _buildMapButton(Icons.my_location, _goToMyLocation),
                ],
              ),
            ),

          // Toggle view tugmasi
          Positioned(
            left: 16,
            bottom: 100,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(_showList ? Icons.map : Icons.list, size: 24),
                onPressed: () {
                  setState(() => _showList = !_showList);
                },
                color: AppColors.primaryGreen,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    if (_techList.isEmpty) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'equipment.none_found'.tr(),
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        );
    }

    return Container(
      margin: const EdgeInsets.only(top: 40),
      child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _techList.length,
          itemBuilder: (context, index) {
            final tech = _techList[index];
            final imageUrl = tech.photos.isNotEmpty ? tech.photos.first.url : null;
            final isAvailable = tech.status == 'available' && (tech.available ?? false);
        
            // Masofa hisoblash (agar user location va tech location mavjud bo'lsa)
            String? distanceText;
            if (_currentLocation != null && tech.latitude != null && tech.longitude != null) {
              final techLat = double.tryParse(tech.latitude!);
              final techLng = double.tryParse(tech.longitude!);
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
        
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedTech = tech);
                  _showBottomSheet();
                },
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Container(
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Chap tomon - Rasm
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? Image.network(
                                    AppConfig.mediaUrl(imageUrl),
                                    width: 100,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => SizedBox(
                                      width: 100,
                                      height: 96,
                                      child: EquipmentPhotoPlaceholder(tech.type),
                                    ),
                                  )
                                : SizedBox(
                                    width: 100,
                                    height: 96,
                                    child: EquipmentPhotoPlaceholder(
                                      tech.type,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          // O'ng tomon - Ma'lumotlar
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Yuqori qism - Nom va tavsif
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      EquipmentTypes.label(tech.type),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tech.model,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (tech.description != null && tech.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        tech.description!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                                // Pastki qism - Narx va masofa
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Narx
                                    Row(
                                      children: [
                                        Text(
                                          NumberFormatter.formatCurrency(tech.pricePerDay),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            color: AppColors.primaryGreen,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${'common.currency'.tr()}/${'common.day'.tr()}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // O'ng chetdagi strelka
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey[400],
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                    // Masofa (agar mavjud bo'lsa)
                                    if (distanceText != null)
                                      Positioned(
                                        bottom: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(12),
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
                    // Holat indikatori - o'ng yuqori burchak
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isAvailable ? AppColors.primaryGreen : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: (isAvailable ? AppColors.primaryGreen : Colors.red).withValues(alpha: 0.3),
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
                              isAvailable ? 'messages.available'.tr() : 'messages.busy'.tr(),
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
                  ],
                ),
              ),
            );
          },
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
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
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
                ' so\'m/$unit',
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
}
