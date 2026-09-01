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
