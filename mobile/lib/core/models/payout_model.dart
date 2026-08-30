class PayoutRequestModel {
  final int id;
  final double amount;

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
    required this.status,
    required this.cardMasked,
    required this.createdAt,
    this.cardHolder,
    this.comment,
    this.adminComment,
    this.processedAt,
  });

  factory PayoutRequestModel.fromJson(Map<String, dynamic> json) {
    return PayoutRequestModel(
      id: json['id'] as int,
      amount: (json['amount'] as num).toDouble(),
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
