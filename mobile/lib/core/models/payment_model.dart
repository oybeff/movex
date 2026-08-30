class PaymentModel {
  final int id;
  final int orderId;
  final double amount;
  final double commission;
  final String? paymentMethod;
  final String status;
  final DateTime? paidAt;

  PaymentModel({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.commission,
    this.paymentMethod,
    required this.status,
    this.paidAt,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] as int,
      orderId: json['order_id'] as int,
      amount: (json['amount'] as num).toDouble(),
      commission: (json['commission'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String?,
      status: json['status'] as String,
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'amount': amount,
      'commission': commission,
      'payment_method': paymentMethod,
      'status': status,
      'paid_at': paidAt?.toIso8601String(),
    };
  }
}

