import 'package:intl/intl.dart';

/// Summani formatlash uchun utility funksiyalar
class NumberFormatter {
  /// Summani 1 234 567 formatida qaytaradi
  /// 
  /// Misol:
  /// ```dart
  /// formatCurrency(1234567) // "1 234 567"
  /// formatCurrency(1234567.50) // "1 234 567.50"
  /// formatCurrency(1000) // "1 000"
  /// ```
  static String formatCurrency(dynamic amount) {
    if (amount == null) return '0';
    
    // double yoki int ga o'tkazish
    double value;
    if (amount is String) {
      value = double.tryParse(amount) ?? 0;
    } else if (amount is int) {
      value = amount.toDouble();
    } else if (amount is double) {
      value = amount;
    } else {
      value = 0;
    }
    
    // Agar kasr qismi 0 bo'lsa, faqat butun qismni ko'rsatish
    if (value == value.toInt()) {
      final formatter = NumberFormat('#,###', 'en_US');
      return formatter.format(value.toInt()).replaceAll(',', ' ');
    } else {
      // Kasr qismi bilan
      final formatter = NumberFormat('#,###.##', 'en_US');
      return formatter.format(value).replaceAll(',', ' ');
    }
  }
  
  /// Summa va valyuta belgisi.
  ///
  /// DIQQAT: symbol ni ko'rsatmasa, chaqiruvchi tarjimadan olishi kerak:
  ///   formatCurrencyWithSymbol(x, symbol: 'common.currency'.tr())
  /// Ilgari bu yerda "so'm" qattiq yozilgan edi va ruscha interfeysda ham
  /// o'zbekcha chiqardi — bitta kartochkada "сум" va "so'm" yonma-yon
  /// turardi.
  ///
  /// Misol:
  /// ```dart
  /// formatCurrencyWithSymbol(1234567, symbol: 'сум') // "1 234 567 сум"
  /// ```
  static String formatCurrencyWithSymbol(dynamic amount, {required String symbol}) {
    return '${formatCurrency(amount)} $symbol';
  }
  
  /// Summani qisqartirilgan formatda qaytaradi (K, M)
  /// 
  /// Misol:
  /// ```dart
  /// formatCurrencyCompact(1234567) // "1.2M"
  /// formatCurrencyCompact(12345) // "12.3K"
  /// ```
  static String formatCurrencyCompact(dynamic amount) {
    if (amount == null) return '0';
    
    double value;
    if (amount is String) {
      value = double.tryParse(amount) ?? 0;
    } else if (amount is int) {
      value = amount.toDouble();
    } else if (amount is double) {
      value = amount;
    } else {
      value = 0;
    }
    
    // Butun son bo'lsa kasr qismini ko'rsatmaymiz: "10.0K" emas, "10K".
    String trim(double v) {
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (value >= 1000000) {
      return '${trim(value / 1000000)}M';
    } else if (value >= 1000) {
      return '${trim(value / 1000)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }
}

