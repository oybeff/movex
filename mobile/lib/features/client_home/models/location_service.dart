import 'package:geolocator/geolocator.dart';
import 'app_location.dart';

class LocationService implements AppLocation {
  final defLocation = const MoscowLocation();

  @override
  Future<AppLatLong> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      return AppLatLong(lat: position.latitude, long: position.longitude);
    } catch (_) {
      return defLocation;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final perm = await Geolocator.requestPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> checkPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}
