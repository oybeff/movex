import 'package:dio/dio.dart';

class GeocodingService {
  final Dio _dio = Dio();
  
  // Yandex Geocoder API key (movex_go uchun)
  static const String _apiKey = 'c5e1e0e5-8f5a-4b5e-8f5a-4b5e8f5a4b5e'; // TODO: Real API key qo'yish kerak
  
  /// Koordinatalardan manzil olish (Reverse Geocoding)
  /// 
  /// [latitude] - Kenglik
  /// [longitude] - Uzunlik
  /// 
  /// Returns: Manzil string yoki null (agar xato bo'lsa)
  Future<String?> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      final response = await _dio.get(
        'https://geocode-maps.yandex.ru/1.x/',
        queryParameters: {
          'apikey': _apiKey,
          'geocode': '$longitude,$latitude', // Yandex'da longitude,latitude tartibida
          'format': 'json',
          'lang': 'uz_UZ', // O'zbek tilida
          'results': 1, // Faqat bitta natija
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        
        // Response structure:
        // response -> GeoObjectCollection -> featureMember -> [0] -> GeoObject -> metaDataProperty -> GeocoderMetaData -> text
        final featureMembers = data['response']?['GeoObjectCollection']?['featureMember'];
        
        if (featureMembers != null && featureMembers is List && featureMembers.isNotEmpty) {
          final geoObject = featureMembers[0]['GeoObject'];
          final address = geoObject?['metaDataProperty']?['GeocoderMetaData']?['text'];
          
          if (address != null && address is String) {
            return address;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }
  
  /// Manzildan koordinatalar olish (Forward Geocoding)
  /// 
  /// [address] - Manzil string
  /// 
  /// Returns: Map with 'latitude' and 'longitude' keys, or null
  Future<Map<String, double>?> getCoordinatesFromAddress(String address) async {
    try {
      final response = await _dio.get(
        'https://geocode-maps.yandex.ru/1.x/',
        queryParameters: {
          'apikey': _apiKey,
          'geocode': address,
          'format': 'json',
          'lang': 'uz_UZ',
          'results': 1,
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        final featureMembers = data['response']?['GeoObjectCollection']?['featureMember'];
        
        if (featureMembers != null && featureMembers is List && featureMembers.isNotEmpty) {
          final geoObject = featureMembers[0]['GeoObject'];
          final pos = geoObject?['Point']?['pos']; // "longitude latitude" format
          
          if (pos != null && pos is String) {
            final parts = pos.split(' ');
            if (parts.length == 2) {
              final longitude = double.tryParse(parts[0]);
              final latitude = double.tryParse(parts[1]);
              
              if (longitude != null && latitude != null) {
                return {
                  'latitude': latitude,
                  'longitude': longitude,
                };
              }
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }
}

