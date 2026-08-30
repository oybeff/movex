import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

/// Permission boshqarish uchun service
class PermissionService {
  /// Location permission tekshirish va so'rash
  static Future<LocationPermissionResult> requestLocationPermission() async {
    try {
      // 1. Location service yoniqligini tekshirish
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.serviceDisabled,
          errorMessage: 'messages.location_service_disabled_message',
        );
      }

      // 2. Permission statusini tekshirish
      PermissionStatus status = await Permission.location.status;

      // 3. Agar ruxsat berilmagan bo'lsa, so'rash
      if (status.isDenied) {
        status = await Permission.location.request();
      }

      // 4. Agar hali ham rad etilgan bo'lsa
      if (status.isDenied) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.denied,
          errorMessage: 'messages.location_permission_not_granted_message',
        );
      }

      // 5. Agar butunlay rad etilgan bo'lsa (permanently denied)
      if (status.isPermanentlyDenied) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.permanentlyDenied,
          errorMessage: 'messages.location_permission_not_granted_message',
          canOpenSettings: true,
        );
      }

      // 6. Agar ruxsat berilgan bo'lsa
      if (status.isGranted || status.isLimited) {
        return LocationPermissionResult(
          isGranted: true,
          errorType: null,
          errorMessage: null,
        );
      }

      // 7. Boshqa holatlar
      return LocationPermissionResult(
        isGranted: false,
        errorType: LocationPermissionError.unknown,
        errorMessage: 'errors.unknown_error',
      );
    } catch (e) {
      return LocationPermissionResult(
        isGranted: false,
        errorType: LocationPermissionError.unknown,
        errorMessage: e.toString(),
      );
    }
  }

  /// Sozlamalarni ochish
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Location service sozlamalarini ochish
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}

/// Location permission natijasi
class LocationPermissionResult {
  final bool isGranted;
  final LocationPermissionError? errorType;
  final String? errorMessage;
  final bool canOpenSettings;

  LocationPermissionResult({
    required this.isGranted,
    this.errorType,
    this.errorMessage,
    this.canOpenSettings = false,
  });
}

/// Location permission xatolari
enum LocationPermissionError {
  serviceDisabled,
  denied,
  permanentlyDenied,
  unknown,
}

