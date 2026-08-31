import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/models/equipment_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/widgets/equipment_type_icon.dart';
import '../../../../core/widgets/map_or_placeholder.dart';

class AddEquipmentPage extends StatefulWidget {
  const AddEquipmentPage({super.key});

  @override
  State<AddEquipmentPage> createState() => _AddEquipmentPageState();
}

class _AddEquipmentPageState extends State<AddEquipmentPage> {
  final _formKey = GlobalKey<FormState>();
  final EquipmentService _equipmentService = EquipmentService();

  // Tur ma'lumotnomadan tanlanadi, shuning uchun controller emas — oddiy holat
  String? _selectedType;

  // Controllers
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _powerController = TextEditingController();
  final _pricePerHourController = TextEditingController();
  final _pricePerShiftController = TextEditingController();
  final _pricePerDayController = TextEditingController();
  final _deliveryPricePerKmController = TextEditingController();
  final _addressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _payloadController = TextEditingController();
  final _dimensionsController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _status = 'available';
  bool _isLoading = false;
  Point? _selectedLocation;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _strictMode = true; // Barcha maydonlar majburiy bo'lishi uchun

  @override
  void initState() {
    super.initState();
    // Qo'shishda faqat avval tanlangan joylashuv bo'lmasa joriy joylashuvni olish
    // (BottomSheet ochilganda esa har doim joriy joylashuvni oladi)
  }

  Future<void> _showLocationPicker() async {
    final result = await showModalBottomSheet<Point>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // Swipe bilan yopilmasligi uchun
      enableDrag: false, // Drag qilish o'chirilgan
      builder: (context) => _LocationPickerBottomSheet(
        initialLocation: _selectedLocation ?? const Point(latitude: 41.2995, longitude: 69.2401), // Toshkent
      ),
    );

    if (result != null) {
      setState(() {
        _selectedLocation = result;
        _latitudeController.text = result.latitude.toStringAsFixed(6);
        _longitudeController.text = result.longitude.toStringAsFixed(6);
      });
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    _yearController.dispose();
    _powerController.dispose();
    _pricePerHourController.dispose();
    _pricePerShiftController.dispose();
    _pricePerDayController.dispose();
    _deliveryPricePerKmController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _payloadController.dispose();
    _dimensionsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveEquipment() async {
    // Validatsiyani yoqish
    setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);

    if (!_formKey.currentState!.validate()) {
      // Birinchi xatoga scroll qilish
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('messages.fill_required_fields'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    // Bo'sh stringlarni tekshirish
    if (_selectedType == null || _modelController.text.trim().isEmpty) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('messages.type_model_required'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final equipment = EquipmentCreateModel(
        type: _selectedType!,
        model: _modelController.text.trim(),
        year: int.tryParse(_yearController.text),
        powerHp: int.tryParse(_powerController.text),
        pricePerHour: double.tryParse(_pricePerHourController.text),
        pricePerShift: double.tryParse(_pricePerShiftController.text),
        pricePerDay: double.tryParse(_pricePerDayController.text) ?? 0.0,
        deliveryPricePerKm: double.tryParse(_deliveryPricePerKmController.text),
        address: _addressController.text.isEmpty ? null : _addressController.text,
        latitude: double.tryParse(_latitudeController.text),
        longitude: double.tryParse(_longitudeController.text),
        payloadKg: int.tryParse(_payloadController.text),
        dimensions: _dimensionsController.text.isEmpty ? null : _dimensionsController.text,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        status: _status,
      );

      await _equipmentService.createEquipment(equipment);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('equipment.created'.tr())),
        );
        context.pop(true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('equipment.create_error'.tr())),
        );
      }
    }
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
          title: Text('equipment.add'.tr()),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: _autovalidateMode,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Strict Mode Switch
              // Container(
              //   padding: const EdgeInsets.all(16),
              //   margin: const EdgeInsets.only(bottom: 16),
              //   decoration: BoxDecoration(
              //     color: Colors.white,
              //     borderRadius: BorderRadius.circular(12),
              //     boxShadow: [
              //       BoxShadow(
              //         color: Colors.black.withAlpha(13),
              //         blurRadius: 4,
              //         offset: const Offset(0, 2),
              //       ),
              //     ],
              //   ),
              //   child: Row(
              //     children: [
              //       Expanded(
              //         child: Column(
              //           crossAxisAlignment: CrossAxisAlignment.start,
              //           children: [
              //             Text(
              //               'Qat\'iy rejim',
              //               style: TextStyle(
              //                 fontSize: 16,
              //                 fontWeight: FontWeight.bold,
              //                 color: Colors.grey[800],
              //               ),
              //             ),
              //             const SizedBox(height: 4),
              //             Text(
              //               'Barcha maydonlarni to\'ldirish majburiy',
              //               style: TextStyle(
              //                 fontSize: 12,
              //                 color: Colors.grey[600],
              //               ),
              //             ),
              //           ],
              //         ),
              //       ),
              //       Switch(
              //         value: _strictMode,
              //         onChanged: (value) {
              //           setState(() {
              //             _strictMode = value;
              //           });
              //         },
              //         activeColor: AppColors.primaryGreen,
              //       ),
              //     ],
              //   ),
              // ),
              
              // Tur endi erkin matn emas — ma'lumotnomadan tanlanadi.
              // Shu tufayli katalogdagi filtr va turga mos ikonka ishlaydi.
              _buildSection(
                title: 'equipment.type'.tr(),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  isExpanded: true,
                  decoration: _inputDecoration('equipment.type'.tr()),
                  items: EquipmentTypes.codes.map((code) {
                    return DropdownMenuItem<String>(
                      value: code,
                      child: Row(
                        children: [
                          EquipmentTypeIcon(code, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              EquipmentTypes.label(code),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedType = value),
                  validator: (value) =>
                      value == null ? 'Bu maydon to\'ldirilishi shart' : null,
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.model'.tr(),
                child: TextFormField(
                  controller: _modelController,
                  decoration: _inputDecoration('equipment.model'.tr()),
                  maxLength: 100,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value.length > 100) {
                      return 'Maksimal 100 ta belgi';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSection(
                      title: 'equipment.year'.tr(),
                      child: TextFormField(
                        controller: _yearController,
                        decoration: _inputDecoration('equipment.year'.tr()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4), // Maksimal 4 raqam
                        ],
                        validator: (value) {
                          if (_strictMode && (value == null || value.isEmpty)) {
                            return 'Bu maydon to\'ldirilishi shart';
                          }
                          if (value != null && value.isNotEmpty) {
                            final year = int.tryParse(value);
                            if (year == null) {
                              return 'Noto\'g\'ri yil';
                            }
                            final currentYear = DateTime.now().year;
                            if (year <= 1900 || year > currentYear) {
                              return 'errors.year_range'.tr(args: ['\$currentYear']);
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSection(
                      title: 'equipment.power_hp'.tr(),
                      child: TextFormField(
                        controller: _powerController,
                        decoration: _inputDecoration('equipment.power_hp'.tr()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (_strictMode && (value == null || value.isEmpty)) {
                            return 'Bu maydon to\'ldirilishi shart';
                          }
                          if (value != null && value.isNotEmpty) {
                            final power = int.tryParse(value);
                            if (power == null) {
                              return 'Noto\'g\'ri qiymat';
                            }
                            if (power < 0) {
                              return 'errors.negative_not_allowed'.tr();
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.price_per_hour'.tr(),
                child: TextFormField(
                  controller: _pricePerHourController,
                  decoration: _inputDecoration('equipment.price_per_hour'.tr()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.isNotEmpty) {
                      final price = double.tryParse(value);
                      if (price == null) {
                        return 'Noto\'g\'ri narx';
                      }
                      if (price <= 0) {
                        return 'errors.price_positive'.tr();
                      }
                      if (price > 99999999.99) {
                        return 'Narx juda katta';
                      }
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.price_per_shift'.tr(),
                child: TextFormField(
                  controller: _pricePerShiftController,
                  decoration: _inputDecoration('equipment.price_per_shift'.tr()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.isNotEmpty) {
                      final price = double.tryParse(value);
                      if (price == null) {
                        return 'Noto\'g\'ri narx';
                      }
                      if (price <= 0) {
                        return 'errors.price_positive'.tr();
                      }
                      if (price > 99999999.99) {
                        return 'Narx juda katta';
                      }
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.price_per_day'.tr(),
                child: TextFormField(
                  controller: _pricePerDayController,
                  decoration: _inputDecoration('equipment.price_per_day'.tr()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    final price = double.tryParse(value);
                    if (price == null) {
                      return 'Noto\'g\'ri narx';
                    }
                    if (price <= 0) {
                      return 'errors.price_positive'.tr();
                    }
                    if (price > 99999999.99) {
                      return 'Narx juda katta';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.delivery_price'.tr(),
                child: TextFormField(
                  controller: _deliveryPricePerKmController,
                  decoration: _inputDecoration('equipment.delivery_price_hint'.tr()).copyWith(
                    suffixText: '${'common.currency'.tr()}/${'common.km'.tr()}',
                    helperText: 'equipment.delivery_price_help'.tr(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final price = double.tryParse(value);
                      if (price == null) {
                        return 'Noto\'g\'ri narx';
                      }
                      if (price < 0) {
                        return 'errors.negative_not_allowed'.tr();
                      }
                      if (price > 99999999.99) {
                        return 'Narx juda katta';
                      }
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.address'.tr(),
                child: TextFormField(
                  controller: _addressController,
                  decoration: _inputDecoration('equipment.address'.tr()),
                  maxLines: 2,
                  maxLength: 200,
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.length > 200) {
                      return 'Maksimal 200 ta belgi';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.location'.tr(),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latitudeController,
                            decoration: _inputDecoration('equipment.latitude'.tr()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d+\.?\d{0,6}'))],
                            readOnly: true,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final lat = double.tryParse(value);
                                if (lat == null) {
                                  return 'Noto\'g\'ri qiymat';
                                }
                                if (lat < -90 || lat > 90) {
                                  return 'errors.latitude_range'.tr();
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _longitudeController,
                            decoration: _inputDecoration('equipment.longitude'.tr()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d+\.?\d{0,6}'))],
                            readOnly: true,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final lon = double.tryParse(value);
                                if (lon == null) {
                                  return 'Noto\'g\'ri qiymat';
                                }
                                if (lon < -180 || lon > 180) {
                                  return 'errors.longitude_range'.tr();
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showLocationPicker,
                        icon: const Icon(Icons.map),
                        label: Text('equipment.select_on_map'.tr()),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.payload_kg'.tr(),
                child: TextFormField(
                  controller: _payloadController,
                  decoration: _inputDecoration('equipment.payload_kg'.tr()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.isNotEmpty) {
                      final payload = int.tryParse(value);
                      if (payload == null) {
                        return 'Noto\'g\'ri qiymat';
                      }
                      if (payload < 0) {
                        return 'errors.negative_not_allowed'.tr();
                      }
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.dimensions'.tr(),
                child: TextFormField(
                  controller: _dimensionsController,
                  decoration: _inputDecoration('equipment.dimensions'.tr()),
                  maxLength: 100,
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.length > 100) {
                      return 'Maksimal 100 ta belgi';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.description'.tr(),
                child: TextFormField(
                  controller: _descriptionController,
                  decoration: _inputDecoration('equipment.description'.tr()),
                  maxLines: 4,
                  maxLength: 1000,
                  validator: (value) {
                    if (_strictMode && (value == null || value.isEmpty)) {
                      return 'Bu maydon to\'ldirilishi shart';
                    }
                    if (value != null && value.length > 1000) {
                      return 'Maksimal 1000 ta belgi';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'equipment.status'.tr(),
                child: DropdownButtonFormField<String>(
                  value: _status,
                  dropdownColor: Colors.white,
                  decoration: _inputDecoration('equipment.status'.tr()).copyWith(
                    // prefixIcon: Icon(
                    //   _status == 'available'
                    //       ? Icons.check_circle
                    //       : _status == 'busy'
                    //           ? Icons.work
                    //           : Icons.build,
                    //   color: _status == 'available'
                    //       ? Colors.green
                    //       : _status == 'busy'
                    //           ? Colors.orange
                    //           : Colors.red,
                    // ),
                  ),
                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.primaryGreen),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'available',
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 20, color: Colors.green),
                          const SizedBox(width: 12),
                          Text('equipment.status_available'.tr()),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'busy',
                      child: Row(
                        children: [
                          const Icon(Icons.work, size: 20, color: Colors.orange),
                          const SizedBox(width: 12),
                          Text('equipment.status_busy'.tr()),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'repair',
                      child: Row(
                        children: [
                          const Icon(Icons.build, size: 20, color: Colors.red),
                          const SizedBox(width: 12),
                          Text('equipment.status_repair'.tr()),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _status = value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveEquipment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'equipment.save'.tr(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}

// Location Picker BottomSheet Widget
class _LocationPickerBottomSheet extends StatefulWidget {
  final Point initialLocation;

  const _LocationPickerBottomSheet({required this.initialLocation});

  @override
  State<_LocationPickerBottomSheet> createState() => _LocationPickerBottomSheetState();
}

class _LocationPickerBottomSheetState extends State<_LocationPickerBottomSheet> {
  late YandexMapController _mapController;
  late Point _selectedPoint;
  Point? _currentUserLocation;
  bool _isLoadingLocation = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation;
    _requestLocationPermissionAndGetLocation();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _requestLocationPermissionAndGetLocation() async {
    try {
      // Agar avval tanlangan joylashuv bo'lsa (initialLocation Toshkent emas)
      bool hasInitialLocation = widget.initialLocation.latitude != 41.2995 ||
                                widget.initialLocation.longitude != 69.2401;

      if (hasInitialLocation) {
        // Avval tanlangan joylashuv bor - uni ko'rsatamiz
        setState(() {
          _selectedPoint = widget.initialLocation;
          _isLoadingLocation = false;
        });

        // Xarita tayyor bo'lsa, tanlangan joyga o'tish
        if (_mapReady) {
          _moveToLocation(_selectedPoint);
        }
        return;
      }

      // Avval tanlangan joylashuv yo'q - joriy joylashuvni olamiz
      // Permission tekshirish va so'rash
      final permissionResult = await PermissionService.requestLocationPermission();

      if (!permissionResult.isGranted) {
        setState(() => _isLoadingLocation = false);
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.warning,
            style: ToastificationStyle.flatColored,
            title: Text(permissionResult.message),
            autoCloseDuration: const Duration(seconds: 5),
            alignment: Alignment.topCenter,
          );
        }
        return;
      }

      // Joriy joylashuvni olish
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _currentUserLocation = Point(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _selectedPoint = _currentUserLocation!;
        _isLoadingLocation = false;
      });

      // Xarita tayyor bo'lsa, kameraga o'tish
      if (_mapReady) {
        _moveToLocation(_currentUserLocation!);
      }
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      print('Get location error: $e');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('messages.location_error_message'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  // Xarita kamera pozitsiyasi o'zgarganda chaqiriladi
  void _onCameraPositionChanged(CameraPosition position, CameraUpdateReason reason, bool finished) {
    if (finished) {
      // Xarita to'xtaganda markaziy nuqtani yangilaymiz
      setState(() {
        _selectedPoint = position.target;
      });
    }
  }

  Future<void> _moveToLocation(Point point, {double zoom = 17}) async {
    await _mapController.moveCamera(
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1),
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: zoom),
      ),
    );
  }

  Future<void> _zoomIn() async {
    await _mapController.moveCamera(
      CameraUpdate.zoomIn(),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  Future<void> _zoomOut() async {
    await _mapController.moveCamera(
      CameraUpdate.zoomOut(),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  void _goToMyLocation() {
    if (_currentUserLocation != null) {
      _moveToLocation(_currentUserLocation!, zoom: 17);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Swipe bilan yopilmasligi uchun
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'equipment.select_location'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Map
            Expanded(
              child: _isLoadingLocation
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: AppColors.primaryGreen,),
                          const SizedBox(height: 16),
                          Text('messages.detecting_location'.tr()),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        MapOrPlaceholder(mapBuilder: (_) => YandexMap(
                          onMapCreated: (controller) async {
                            _mapController = controller;
                            setState(() => _mapReady = true);

                            // Agar location tayyor bo'lsa, darhol o'tish
                            if (_currentUserLocation != null) {
                              await _moveToLocation(_currentUserLocation!, zoom: 17);
                            } else {
                              await _moveToLocation(_selectedPoint, zoom: 17);
                            }
                          },
                          onCameraPositionChanged: _onCameraPositionChanged,
                        )),

                        // Markazda qotib turgan marker
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

                        // Koordinatalarni ko'rsatish
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'equipment.selected_coordinates'.tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_selectedPoint.latitude.toStringAsFixed(6)}, ${_selectedPoint.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Control tugmalari (o'ng tepada)
                        Positioned(
                          right: 16,
                          top: 100,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Zoom In
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.add, size: 24),
                                  onPressed: _zoomIn,
                                  color: AppColors.primaryGreen,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Zoom Out
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.remove, size: 24),
                                  onPressed: _zoomOut,
                                  color: AppColors.primaryGreen,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // My Location
                              if (_currentUserLocation != null)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.my_location, size: 24),
                                    onPressed: _goToMyLocation,
                                    color: AppColors.primaryGreen,
                                    padding: const EdgeInsets.all(12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // Confirm button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedPoint),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'common.confirm'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

