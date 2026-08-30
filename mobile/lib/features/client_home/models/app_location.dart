class AppLatLong {
  final double lat;
  final double long;

  const AppLatLong({required this.lat, required this.long});
}

class MoscowLocation extends AppLatLong {
  const MoscowLocation()
      : super(lat: 55.7522200, long: 37.6155600);
}

abstract class AppLocation {
  Future<AppLatLong> getCurrentLocation();
  Future<bool> requestPermission();
  Future<bool> checkPermission();
}
