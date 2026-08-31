import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Joylashuvga ruxsat so'rash.
///
/// Servis TARJIMA KALITINI qaytaradi, tayyor matnni emas: matnni tanlash —
/// interfeys ishi, servis tilni bilmasligi kerak.
///
/// Ilgari bu maydon `errorMessage` deb atalgan va ichida ikki xil narsa
/// yotardi: goh kalit ('messages.location_...'), goh istisnoning matni
/// (e.toString()). Ekran uni to'g'ridan-to'g'ri chiqarardi, natijada
/// foydalanuvchi dialogda kalitning o'zini ko'rardi.
class PermissionService {
  static Future<LocationPermissionResult> requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.serviceDisabled,
          messageKey: 'messages.location_service_disabled_message',
        );
      }

      var status = await Permission.location.status;
      if (status.isDenied) {
        status = await Permission.location.request();
      }

      if (status.isDenied) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.denied,
          messageKey: 'messages.location_permission_not_granted_message',
        );
      }

      if (status.isPermanentlyDenied) {
        return LocationPermissionResult(
          isGranted: false,
          errorType: LocationPermissionError.permanentlyDenied,
          messageKey: 'messages.location_permission_not_granted_message',
          canOpenSettings: true,
        );
      }

      if (status.isGranted || status.isLimited) {
        return LocationPermissionResult(isGranted: true);
      }

      return LocationPermissionResult(
        isGranted: false,
        errorType: LocationPermissionError.unknown,
        messageKey: 'errors.unknown_error',
      );
    } catch (e) {
      // Istisnoning matni foydalanuvchiga ko'rsatilmaydi — u inglizcha va
      // hech narsa tushuntirmaydi. Tafsilot jurnalda qoladi.
      // ignore: avoid_print
      print('Location permission error: $e');
      return LocationPermissionResult(
        isGranted: false,
        errorType: LocationPermissionError.unknown,
        messageKey: 'errors.unknown_error',
        debugDetails: e.toString(),
      );
    }
  }

  static Future<bool> openSettings() async => openAppSettings();

  static Future<bool> openLocationSettings() async =>
      Geolocator.openLocationSettings();
}

class LocationPermissionResult {
  final bool isGranted;
  final LocationPermissionError? errorType;

  /// Tarjima KALITI. Ekranga chiqarishdan oldin [message] dan foydalaning.
  final String? messageKey;

  /// Istisnoning matni — faqat jurnal uchun, ekranga chiqarilmaydi.
  final String? debugDetails;

  final bool canOpenSettings;

  LocationPermissionResult({
    required this.isGranted,
    this.errorType,
    this.messageKey,
    this.debugDetails,
    this.canOpenSettings = false,
  });

  /// Foydalanuvchiga ko'rsatiladigan matn, uning tilida.
  String get message =>
      messageKey == null ? '' : messageKey!.tr();
}

enum LocationPermissionError {
  serviceDisabled,
  denied,
  permanentlyDenied,
  unknown,
}
