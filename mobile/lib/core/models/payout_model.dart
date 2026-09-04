class PayoutRequestModel {
  final int id;

  /// So'ralgan summa — balansdan aynan shu yechiladi.
  final double amount;

  /// Platforma ulushi. Ariza berilgan paytdagi qiymat: sozlama keyin
  /// o'zgarsa ham, eski ariza o'sha holicha qoladi.
  final double commission;

  /// Kartaga haqiqatan tushadigan summa: amount - commission.
  final double payoutAmount;

  /// pending — ko'rib chiqilmoqda, paid — to'langan, rejected — rad etilgan
  final String status;

  /// Karta raqami HECH QACHON to'liq kelmaydi — faqat "•••• 1234"
  final String cardMasked;
  final String? cardHolder;
  final String? comment;
  final String? adminComment;
  final DateTime? processedAt;
  final DateTime createdAt;

  const PayoutRequestModel({
    required this.id,
    required this.amount,
    required this.commission,
    required this.payoutAmount,
    required this.status,
    required this.cardMasked,
    required this.createdAt,
    this.cardHolder,
    this.comment,
    this.adminComment,
    this.processedAt,
  });

  factory PayoutRequestModel.fromJson(Map<String, dynamic> json) {
    final amount = (json['amount'] as num).toDouble();
    return PayoutRequestModel(
      id: json['id'] as int,
      amount: amount,
      commission: (json['commission'] as num?)?.toDouble() ?? 0,
      // Ulushsiz eski ariza: kartaga to'liq summa ketgan.
      payoutAmount: (json['payout_amount'] as num?)?.toDouble() ?? amount,
      status: json['status'] as String,
      cardMasked: json['card_masked'] as String? ?? '••••',
      cardHolder: json['card_holder'] as String?,
      comment: json['comment'] as String?,
      adminComment: json['admin_comment'] as String?,
      processedAt: json['processed_at'] == null
          ? null
          : DateTime.parse(json['processed_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Pul yechish shartlari — serverdan keladi, ilovada qotib qolmaydi.
///
/// Ulush adminkadan o'zgaradi. Agar u ilovaga yozib qo'yilsa, yig'ilgan
/// ilovada eski qiymat qolar va ega ekranda bir summani ko'rib, kartasiga
/// boshqasini olardi.
class PayoutSettingsModel {
  /// 'fixed' — qat'iy summa, 'percent' — ariza summasidan foiz.
  final String mode;
  final double fixed;
  final double percent;
  final double minAmount;

  const PayoutSettingsModel({
    required this.mode,
    required this.fixed,
    required this.percent,
    required this.minAmount,
  });

  bool get isFixed => mode == 'fixed';

  /// Server bilan BIR XIL formula (payout_service.calculate_commission).
  /// Farq qilsa — ega ekranda bir summani ko'rib, boshqasini olardi.
  double commissionFor(double amount) {
    if (amount <= 0) return 0;
    final raw = isFixed ? fixed : amount * percent / 100;
    final rounded = raw.roundToDouble();
    if (rounded < 0) return 0;
    return rounded > amount ? amount : rounded;
  }

  /// Kartaga tushadigan summa.
  double netFor(double amount) => amount - commissionFor(amount);

  factory PayoutSettingsModel.fromJson(Map<String, dynamic> json) {
    return PayoutSettingsModel(
      mode: json['mode'] as String? ?? 'fixed',
      fixed: (json['fixed'] as num?)?.toDouble() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      minAmount: (json['min_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}
