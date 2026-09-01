import 'package:dio/dio.dart';

import '../models/listing_model.dart';
import '../network/dio_client.dart';

/// E'lonlar: mijoz erkin matn bilan nima kerakligini yozadi.
///
/// Zayavkadan farqi — ma'lumotnoma va savdo yo'q. Egasi "olaman" deydi,
/// mijoz uni tasdiqlaydi. Telefon raqami tasdiqlangandan keyingina ochiladi
/// va buni SERVER hal qiladi: ilova faqat kelgan qiymatni ko'rsatadi, o'zi
/// hech qanday shart yozmaydi. Aks holda tekshiruv ikki joyda bo'lib,
/// bittasi eskirardi.
class ListingService {
  final Dio _dio = DioClient.create();

  // ------------------------------------------------------------- rasm

  /// Rasmni yuklaydi va uning manzilini qaytaradi.
  ///
  /// E'lon yaratilishidan OLDIN chaqiriladi: odam avval rasmlarni tanlaydi,
  /// keyin "joylash" bosadi. Olingan manzillar create() ga photos bo'lib
  /// beriladi.
  ///
  /// [bytes] webda kerak: u yerda faylning yo'li yo'q, faqat mazmuni bor.
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
      '/listings/photos',
      data: FormData.fromMap({'file': part}),
    );
    return (response.data as Map<String, dynamic>)['url'] as String;
  }

  // ------------------------------------------------------------ mijozga

  Future<ListingModel> create({
    required String title,
    String? description,
    String? equipmentType,
    double? budget,
    String? address,
    double? latitude,
    double? longitude,
    DateTime? neededFrom,
    DateTime? neededTo,
    String? contactPhone,
    List<String> photos = const [],
  }) async {
    final response = await _dio.post('/listings/', data: {
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (equipmentType != null && equipmentType.isNotEmpty)
        'equipment_type': equipmentType,
      if (budget != null && budget > 0) 'budget': budget,
      if (address != null && address.isNotEmpty) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (neededFrom != null) 'needed_from': _date(neededFrom),
      if (neededTo != null) 'needed_to': _date(neededTo),
      if (contactPhone != null && contactPhone.isNotEmpty)
        'contact_phone': contactPhone,
      if (photos.isNotEmpty) 'photos': photos,
    });
    return ListingModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ListingModel>> getMine({int skip = 0, int limit = 50}) async {
    final response = await _dio.get('/listings/mine', queryParameters: {
      'skip': skip,
      'limit': limit,
    });
    return _list(response);
  }

  /// Mijoz ijrochini tasdiqlaydi — shundan keyin ikkalasi telefonni ko'radi.
  Future<ListingModel> confirm(int id) async =>
      _one(await _dio.post('/listings/$id/confirm'));

  /// Ijrochi yoqmadi — e'lon yana taxtaga qaytadi.
  Future<ListingModel> reject(int id) async =>
      _one(await _dio.post('/listings/$id/reject'));

  Future<ListingModel> cancel(int id) async =>
      _one(await _dio.post('/listings/$id/cancel'));

  // -------------------------------------------------------------- egaga

  /// Taxta: ochiq e'lonlar va shu ega olgan e'lonlar.
  Future<List<ListingModel>> getFeed({
    String? equipmentType,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get('/listings/feed', queryParameters: {
      if (equipmentType != null && equipmentType.isNotEmpty)
        'equipment_type': equipmentType,
      'skip': skip,
      'limit': limit,
    });
    return _list(response);
  }

  /// "Olaman". Kim birinchi bo'lsa — o'shaniki: server qatorni bloklaydi,
  /// ikkinchisiga 400 qaytadi.
  Future<ListingModel> take(int id) async =>
      _one(await _dio.post('/listings/$id/take'));

  // ----------------------------------------------------------- ikkalasi

  Future<ListingModel> getOne(int id) async =>
      _one(await _dio.get('/listings/$id'));

  Future<ListingModel> finish(int id) async =>
      _one(await _dio.post('/listings/$id/finish'));

  // ------------------------------------------------------------- ichki

  ListingModel _one(Response response) =>
      ListingModel.fromJson(response.data as Map<String, dynamic>);

  List<ListingModel> _list(Response response) => (response.data as List<dynamic>)
      .map((e) => ListingModel.fromJson(e as Map<String, dynamic>))
      .toList();

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
