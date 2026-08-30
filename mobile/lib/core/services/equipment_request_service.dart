import 'package:dio/dio.dart';

import '../models/equipment_request_model.dart';
import '../network/dio_client.dart';

/// Zayavkalar: mijoz texnikani "chaqiradi", egalar narx taklif qiladi.
///
/// Bu yerda hech qanday hisob-kitob yo'q va bo'lmasligi kerak. Byudjet va
/// taklifdagi narx — mo'ljal; buyurtmaning haqiqiy summasini server
/// hisoblaydi. Ekranda ko'rsatiladigan "taxminiy" summa ham serverdan
/// keladi (estimated_subtotal), ilova o'zi ko'paytirmaydi — aks holda ikki
/// joyda ikki xil raqam chiqardi.
class EquipmentRequestService {
  final Dio _dio = DioClient.create();

  // ------------------------------------------------------------ mijozga

  Future<EquipmentRequestModel> createRequest({
    required String equipmentType,
    required DateTime startDate,
    required DateTime endDate,
    required double latitude,
    required double longitude,
    String? address,
    double? budget,
    String? comment,
  }) async {
    final response = await _dio.post('/requests/', data: {
      'equipment_type': equipmentType,
      'start_date': _date(startDate),
      'end_date': _date(endDate),
      'delivery_latitude': latitude,
      'delivery_longitude': longitude,
      if (address != null && address.isNotEmpty) 'delivery_address': address,
      if (budget != null && budget > 0) 'budget': budget,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return EquipmentRequestModel.fromJson(
        response.data as Map<String, dynamic>);
  }

  Future<List<EquipmentRequestModel>> getMyRequests({
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get('/requests/', queryParameters: {
      'skip': skip,
      'limit': limit,
    });
    return (response.data as List<dynamic>)
        .map((e) => EquipmentRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Bitta zayavka takliflari bilan.
  Future<EquipmentRequestModel> getRequest(int id) async {
    final response = await _dio.get('/requests/$id');
    return EquipmentRequestModel.fromJson(
        response.data as Map<String, dynamic>);
  }

  Future<EquipmentRequestModel> cancelRequest(int id) async {
    final response = await _dio.post('/requests/$id/cancel');
    return EquipmentRequestModel.fromJson(
        response.data as Map<String, dynamic>);
  }

  /// Taklifni tanlash. Shu paytda buyurtma yaratiladi va pul muzlatiladi;
  /// mablag' yetmasa server 400 qaytaradi va zayavka ochiq qoladi.
  ///
  /// Yaratilgan buyurtma raqamini qaytaradi.
  Future<int> acceptOffer(int requestId, int offerId) async {
    final response =
        await _dio.post('/requests/$requestId/offers/$offerId/accept');
    return (response.data as Map<String, dynamic>)['order_id'] as int;
  }

  // -------------------------------------------------------------- egaga

  /// Egaga: turi mos va radiusiga tushadigan ochiq zayavkalar.
  Future<List<EquipmentRequestModel>> getFeed({
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get('/requests/feed', queryParameters: {
      'skip': skip,
      'limit': limit,
    });
    return (response.data as List<dynamic>)
        .map((e) => EquipmentRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RequestOfferModel> createOffer({
    required int requestId,
    required int equipmentId,
    required double pricePerDay,
    String? comment,
  }) async {
    final response = await _dio.post('/requests/$requestId/offers', data: {
      'equipment_id': equipmentId,
      'price_per_day': pricePerDay,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return RequestOfferModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> withdrawOffer(int requestId, int offerId) async {
    await _dio.delete('/requests/$requestId/offers/$offerId');
  }

  // ------------------------------------------------------------- radius

  Future<SearchAreaModel> getSearchArea() async {
    final response = await _dio.get('/requests/area');
    return SearchAreaModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SearchAreaModel> setSearchArea({
    double? latitude,
    double? longitude,
    required int radiusKm,
  }) async {
    final response = await _dio.put('/requests/area', data: {
      'latitude': latitude,
      'longitude': longitude,
      'radius_km': radiusKm,
    });
    return SearchAreaModel.fromJson(response.data as Map<String, dynamic>);
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
