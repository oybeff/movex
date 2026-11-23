import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum DriverCardType { uzcard, humo, visa, mastercard, other }

class DriverPayoutCard {
  final String id;
  final String number; // 16 digits
  final String expiry; // MM/YY
  final String holder;
  final bool isDefault;
  final DriverCardType type;

  DriverPayoutCard({
    required this.id,
    required this.number,
    required this.expiry,
    required this.holder,
    this.isDefault = false,
    DriverCardType? type,
  }) : type = type ?? detectType(number);

  static DriverCardType detectType(String pan) {
    final clean = pan.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('8600')) return DriverCardType.uzcard;
    if (clean.startsWith('9860')) return DriverCardType.humo;
    if (clean.startsWith('4')) return DriverCardType.visa;
    if (clean.startsWith('5')) return DriverCardType.mastercard;
    return DriverCardType.other;
  }

  String get typeName {
    switch (type) {
      case DriverCardType.uzcard:
        return 'Uzcard';
      case DriverCardType.humo:
        return 'Humo';
      case DriverCardType.visa:
        return 'Visa';
      case DriverCardType.mastercard:
        return 'Mastercard';
      default:
        return 'Karta';
    }
  }

  String get maskedPan {
    final clean = number.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 8) return number;
    final first4 = clean.substring(0, 4);
    final last4 = clean.substring(clean.length - 4);
    return '$first4 •••• •••• $last4';
  }

  String get shortMasked {
    final clean = number.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 4) return number;
    return '$typeName •• ${clean.substring(clean.length - 4)}';
  }

  DriverPayoutCard copyWith({
    String? id,
    String? number,
    String? expiry,
    String? holder,
    bool? isDefault,
    DriverCardType? type,
  }) {
    return DriverPayoutCard(
      id: id ?? this.id,
      number: number ?? this.number,
      expiry: expiry ?? this.expiry,
      holder: holder ?? this.holder,
      isDefault: isDefault ?? this.isDefault,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'expiry': expiry,
        'holder': holder,
        'isDefault': isDefault,
        'type': type.name,
      };

  factory DriverPayoutCard.fromJson(Map<String, dynamic> json) => DriverPayoutCard(
        id: json['id'] as String,
        number: json['number'] as String,
        expiry: json['expiry'] as String,
        holder: json['holder'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        type: DriverCardType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => DriverPayoutCard.detectType(json['number'] as String),
        ),
      );
}

class DriverCardsRepository {
  static const _keyPrefix = 'driver_payout_cards_';

  static Future<List<DriverPayoutCard>> getCards(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$userId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => DriverPayoutCard.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCards(String userId, List<DriverPayoutCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(cards.map((c) => c.toJson()).toList());
    await prefs.setString('$_keyPrefix$userId', raw);
  }

  static Future<void> addCard(String userId, DriverPayoutCard card) async {
    final current = await getCards(userId);
    final isFirst = current.isEmpty;
    final updated = [
      if (card.isDefault || isFirst)
        ...current.map((c) => c.copyWith(isDefault: false))
      else
        ...current,
      card.copyWith(isDefault: card.isDefault || isFirst),
    ];
    await saveCards(userId, updated);
  }

  static Future<void> setDefault(String userId, String cardId) async {
    final current = await getCards(userId);
    final updated = current.map((c) => c.copyWith(isDefault: c.id == cardId)).toList();
    await saveCards(userId, updated);
  }

  static Future<void> deleteCard(String userId, String cardId) async {
    final current = await getCards(userId);
    final updated = current.where((c) => c.id != cardId).toList();
    if (updated.isNotEmpty && !updated.any((c) => c.isDefault)) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }
    await saveCards(userId, updated);
  }
}
