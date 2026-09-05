class BalanceModel {
  final int id;
  final int userId;
  final double balance;
  final double frozenBalance;

  /// Sovg'aning ishlatilmagan qismi. Ilova ichida ishlatiladi, lekin
  /// KARTAGA YECHILMAYDI — shuning uchun u alohida yuradi.
  final double bonusBalance;

  final DateTime createdAt;
  final DateTime? updatedAt;

  BalanceModel({
    required this.id,
    required this.userId,
    required this.balance,
    required this.frozenBalance,
    this.bonusBalance = 0,
    required this.createdAt,
    this.updatedAt,
  });

  /// Ilovada SARFLASH mumkin bo'lgan summa. Sovg'a bunga kiradi.
  double get availableBalance => balance - frozenBalance;

  /// KARTAGA yechish mumkin bo'lgan summa. Sovg'a bunga KIRMAYDI.
  ///
  /// Ikkita alohida son ataylab: sovg'ani ilova ichida ishlatsa bo'ladi,
  /// yechsa bo'lmaydi. Bittasi bilan cheklansak, yechish ekrani yechib
  /// bo'lmaydigan pulni ko'rsatardi va odam rad javobini tushunmasdi.
  double get withdrawableBalance {
    final value = balance - frozenBalance - bonusBalance;
    return value > 0 ? value : 0;
  }

  factory BalanceModel.fromJson(Map<String, dynamic> json) {
    return BalanceModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      balance: (json['balance'] is String)
          ? double.parse(json['balance'])
          : (json['balance'] as num).toDouble(),
      frozenBalance: (json['frozen_balance'] is String)
          ? double.parse(json['frozen_balance'])
          : (json['frozen_balance'] as num).toDouble(),
      bonusBalance: json['bonus_balance'] == null
          ? 0
          : (json['bonus_balance'] is String)
              ? double.parse(json['bonus_balance'])
              : (json['bonus_balance'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'balance': balance,
      'frozen_balance': frozenBalance,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class BalanceTransactionModel {
  final int id;
  final int userId;
  final double amount;
  final String type; // 'topup' or 'payment'
  final String status; // 'pending', 'completed', 'failed'
  final String? paymentMethod; // 'click', 'payme', etc.
  final String? description;
  final DateTime createdAt;

  BalanceTransactionModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.status,
    this.paymentMethod,
    this.description,
    required this.createdAt,
  });

  factory BalanceTransactionModel.fromJson(Map<String, dynamic> json) {
    return BalanceTransactionModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      status: json['status'] as String,
      paymentMethod: json['payment_method'] as String?,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'type': type,
      'status': status,
      'payment_method': paymentMethod,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Click to'lov uchun response model
class BalanceTopUpResponse {
  final int transactionId;
  final double amount;
  final String paymentMethod;
  final String status;
  final String? paymentUrl;

  BalanceTopUpResponse({
    required this.transactionId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.paymentUrl,
  });

  factory BalanceTopUpResponse.fromJson(Map<String, dynamic> json) {
    return BalanceTopUpResponse(
      transactionId: json['transaction_id'] as int,
      amount: (json['amount'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String,
      status: json['status'] as String,
      paymentUrl: json['payment_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transaction_id': transactionId,
      'amount': amount,
      'payment_method': paymentMethod,
      'status': status,
      'payment_url': paymentUrl,
    };
  }
}

