import 'package:dio/dio.dart';

import '../models/material_model.dart';
import '../network/dio_client.dart';

/// Qurilish materiallari: katalog, hisob va buyurtma.
///
/// NARXNI ILOVA HISOBLAMAYDI. Miqdor o'zgarganda serverdan `quote`
/// so'raladi va ekranda o'sha ko'rsatiladi. Ilova o'zi sanaganida ikki
/// xil formula paydo bo'lardi: ekranda bir summa, balansdan boshqasi —
/// bu loyihada texnika ijarasida allaqachon bo'lgan.
class MaterialService {
  final Dio _dio = DioClient.create();

  // -------------------------------------------------- ma'lumotnomalar

  Future<List<DeliveryVehicleModel>> getVehicles() async {
    final response = await _dio.get('/materials/vehicles');
    return (response.data as List<dynamic>)
        .map((e) => DeliveryVehicleModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------- katalog

  Future<List<MaterialProductModel>> getCatalog({
    String? materialType,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get('/materials/products', queryParameters: {
      if (materialType != null && materialType.isNotEmpty)
        'material_type': materialType,
      'skip': skip,
      'limit': limit,
    });
    return _products(response);
  }

  Future<MaterialProductModel> getProduct(int id) async =>
      MaterialProductModel.fromJson(
          (await _dio.get('/materials/products/$id')).data
              as Map<String, dynamic>);

  /// Sotuvchining o'z tovarlari — moderatsiyada turganlari bilan.
  Future<List<MaterialProductModel>> getMyProducts() async =>
      _products(await _dio.get('/materials/products/mine'));

  Future<String> uploadPhoto({
    String? filePath,
    List<int>? bytes,
    String fileName = 'photo.jpg',
  }) async {
    final MultipartFile part;
    if (bytes != null) {
      part = MultipartFile.fromBytes(bytes, filename: fileName);
    } else if (filePath != null) {
      part = await MultipartFile.fromFile(filePath, filename: fileName);
    } else {
      throw ArgumentError('kerak: filePath yoki bytes');
    }
    final response = await _dio.post(
      '/materials/products/photos',
      data: FormData.fromMap({'file': part}),
    );
    return (response.data as Map<String, dynamic>)['url'] as String;
  }

  Future<MaterialProductModel> createProduct({
    required String materialType,
    required String title,
    required double pricePerUnit,
    String? description,
    String? unit,
    double? unitWeightKg,
    double? minQuantity,
    double? availableQuantity,
    double? deliveryPricePerKm,
    String? address,
    double? latitude,
    double? longitude,
    List<String> photos = const [],
  }) async {
    final response = await _dio.post('/materials/products', data: {
      'material_type': materialType,
      'title': title,
      'price_per_unit': pricePerUnit,
      if (description != null && description.isNotEmpty) 'description': description,
      if (unit != null) 'unit': unit,
      if (unitWeightKg != null) 'unit_weight_kg': unitWeightKg,
      if (minQuantity != null) 'min_quantity': minQuantity,
      if (availableQuantity != null) 'available_quantity': availableQuantity,
      if (deliveryPricePerKm != null) 'delivery_price_per_km': deliveryPricePerKm,
      if (address != null && address.isNotEmpty) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (photos.isNotEmpty) 'photos': photos,
    });
    return MaterialProductModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('/materials/products/$id');
  }

  // ------------------------------------------------------------ hisob

  /// Jonli hisob: miqdor → og'irlik → mashina → reyslar → jami.
  Future<MaterialQuoteModel> quote({
    required int productId,
    required double quantity,
    double? latitude,
    double? longitude,
    String? vehicleCode,
  }) async {
    final response = await _dio.post('/materials/quote', data: {
      'product_id': productId,
      'quantity': quantity,
      if (latitude != null) 'delivery_latitude': latitude,
      if (longitude != null) 'delivery_longitude': longitude,
      if (vehicleCode != null) 'vehicle_code': vehicleCode,
    });
    return MaterialQuoteModel.fromJson(response.data as Map<String, dynamic>);
  }

  // ------------------------------------------------------- buyurtmalar

  Future<MaterialOrderModel> createOrder({
    required int productId,
    required double quantity,
    String? address,
    double? latitude,
    double? longitude,
    String? vehicleCode,
    String? comment,
  }) async {
    final response = await _dio.post('/materials/orders', data: {
      'product_id': productId,
      'quantity': quantity,
      if (address != null && address.isNotEmpty) 'delivery_address': address,
      if (latitude != null) 'delivery_latitude': latitude,
      if (longitude != null) 'delivery_longitude': longitude,
      if (vehicleCode != null) 'vehicle_code': vehicleCode,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return MaterialOrderModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<MaterialOrderModel>> getOrders({bool asSeller = false}) async {
    final response = await _dio.get('/materials/orders',
        queryParameters: {'as_seller': asSeller});
    return (response.data as List<dynamic>)
        .map((e) => MaterialOrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MaterialOrderModel> confirmOrder(int id) async =>
      _order(await _dio.post('/materials/orders/$id/confirm'));

  /// Yetkazilganini XARIDOR tasdiqlaydi — shundan keyin pul sotuvchiga
  /// o'tadi. Sotuvchining o'zi bosa olganida, u yetkazmasdan turib pulni
  /// olib qo'ya olardi.
  Future<MaterialOrderModel> confirmDelivery(int id) async =>
      _order(await _dio.post('/materials/orders/$id/deliver'));

  Future<MaterialOrderModel> cancelOrder(int id) async =>
      _order(await _dio.post('/materials/orders/$id/cancel'));

  Future<MaterialOrderModel> rejectOrder(int id) async =>
      _order(await _dio.post('/materials/orders/$id/reject'));

  // ------------------------------------------------------------- ichki

  MaterialOrderModel _order(Response response) =>
      MaterialOrderModel.fromJson(response.data as Map<String, dynamic>);

  List<MaterialProductModel> _products(Response response) =>
      (response.data as List<dynamic>)
          .map((e) => MaterialProductModel.fromJson(e as Map<String, dynamic>))
          .toList();
}
