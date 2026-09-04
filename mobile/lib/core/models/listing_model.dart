import '../constants/equipment_types.dart';

/// E'lon — mijozning erkin matnli so'rovi.
///
/// Zayavkadan farqi: ma'lumotnomaga bog'lanmagan va savdo yo'q. Egasi
/// "olaman" deydi, mijoz tasdiqlaydi.
class ListingModel {
  final int id;
  final int clientId;

  final String title;
  final String? description;

  /// Ixtiyoriy: ko'rsatilsa ikonka chiqadi va filtr ishlaydi.
  final String? equipmentType;

  final double? budget;

  final String? address;
  final double? latitude;
  final double? longitude;

  final DateTime? neededFrom;
  final DateTime? neededTo;

  /// open | taken | confirmed | done | cancelled | expired
  final String status;

  final int? takenBy;
  final DateTime? takenAt;
  final DateTime? confirmedAt;
  final int viewsCount;
  final DateTime? expiresAt;
  final DateTime createdAt;

  final List<String> photos;

  final String? clientName;
  final String? takerName;

  /// Faqat ishtirokchilarga keladi. Boshqalarda null — bu ataylab:
  /// aks holda taxta raqamlarni yig'ish uchun ochiq manba bo'lardi.
  final String? contactPhone;

  final bool takenByMe;
  final double? distanceKm;

  /// Sanoqlar. Serverda ustun sifatida saqlanmaydi — so'rovda sanaladi,
  /// shuning uchun ular har doim haqiqatga mos.
  final int likesCount;
  final int savesCount;
  final int offersCount;

  /// Ko'ruvchining o'ziga nisbatan
  final bool likedByMe;
  final bool savedByMe;
  final bool offeredByMe;

  const ListingModel({
    required this.id,
    required this.clientId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.description,
    this.equipmentType,
    this.budget,
    this.address,
    this.latitude,
    this.longitude,
    this.neededFrom,
    this.neededTo,
    this.takenBy,
    this.takenAt,
    this.confirmedAt,
    this.viewsCount = 0,
    this.expiresAt,
    this.photos = const [],
    this.clientName,
    this.takerName,
    this.contactPhone,
    this.takenByMe = false,
    this.distanceKm,
    this.likesCount = 0,
    this.savesCount = 0,
    this.offersCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.offeredByMe = false,
  });

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _toDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory ListingModel.fromJson(Map<String, dynamic> json) {
    return ListingModel(
      id: json['id'] as int,
      clientId: json['client_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      equipmentType: json['equipment_type'] as String?,
      budget: _toDouble(json['budget']),
      address: json['address'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      neededFrom: _toDate(json['needed_from']),
      neededTo: _toDate(json['needed_to']),
      status: json['status'] as String? ?? 'open',
      takenBy: json['taken_by'] as int?,
      takenAt: _toDate(json['taken_at']),
      confirmedAt: _toDate(json['confirmed_at']),
      viewsCount: json['views_count'] as int? ?? 0,
      expiresAt: _toDate(json['expires_at']),
      createdAt: DateTime.parse(json['created_at'] as String),
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => (e as Map<String, dynamic>)['url'] as String)
              .toList() ??
          const [],
      clientName: json['client_name'] as String?,
      takerName: json['taker_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      takenByMe: json['taken_by_me'] as bool? ?? false,
      distanceKm: _toDouble(json['distance_km']),
      likesCount: json['likes_count'] as int? ?? 0,
      savesCount: json['saves_count'] as int? ?? 0,
      offersCount: json['offers_count'] as int? ?? 0,
      likedByMe: json['liked_by_me'] as bool? ?? false,
      savedByMe: json['saved_by_me'] as bool? ?? false,
      offeredByMe: json['offered_by_me'] as bool? ?? false,
    );
  }

  bool get isOpen => status == 'open';
  bool get isTaken => status == 'taken';
  bool get isConfirmed => status == 'confirmed';
  bool get isDone => status == 'done';

  /// Telefon ochiqmi — server hal qiladi, ilova faqat natijani ko'radi.
  bool get hasPhone => contactPhone != null && contactPhone!.isNotEmpty;

  String? get typeLabel =>
      equipmentType == null ? null : EquipmentTypes.label(equipmentType);
}

/// E'longa aytilgan narx.
///
/// "Olaman" dan farqi: u muallif byudjetiga rozilik, taklif esa o'z summasi.
/// Muallif kelganlaridan birini tanlaydi.
class ListingOfferModel {
  final int id;
  final int listingId;
  final int userId;
  final double price;
  final String? comment;

  /// pending | accepted | declined | withdrawn
  final String status;
  final DateTime createdAt;

  final String? userName;

  /// Faqat muallifga va faqat QABUL QILINGANDAN keyin keladi. Aks holda
  /// taklif berish raqam olishning oson yo'liga aylanardi.
  final String? userPhone;

  const ListingOfferModel({
    required this.id,
    required this.listingId,
    required this.userId,
    required this.price,
    required this.status,
    required this.createdAt,
    this.comment,
    this.userName,
    this.userPhone,
  });

  bool get isAccepted => status == 'accepted';
  bool get isPending => status == 'pending';
  bool get hasPhone => userPhone != null && userPhone!.isNotEmpty;

  factory ListingOfferModel.fromJson(Map<String, dynamic> json) {
    return ListingOfferModel(
      id: json['id'] as int,
      listingId: json['listing_id'] as int,
      userId: json['user_id'] as int,
      // Narx serverdan SATR bo'lib keladi ("950000.00") — num deb o'qib
      // bo'lmaydi, shuning uchun umumiy ko'rinishga keltiriladi.
      price: ListingModel._toDouble(json['price']) ?? 0,
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['user_name'] as String?,
      userPhone: json['user_phone'] as String?,
    );
  }
}
