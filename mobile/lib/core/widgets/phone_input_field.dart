import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../constants/app_colors.dart';

/// Phone input field with +998 prefix for Uzbekistan
/// Format: +998 901234567
class PhoneInputField extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final VoidCallback? onChanged;

  const PhoneInputField({
    Key? key,
    required this.controller,
    this.validator,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
    this.onChanged,
  }) : super(key: key);

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  @override
  void initState() {
    super.initState();
    // Set initial value with +998 prefix if empty
    if (widget.controller.text.isEmpty) {
      widget.controller.text = '+998 ';
      widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d\s+()-]')),
        // LengthLimitingTextInputFormatter ataylab YO'Q: u satrni
        // _PhoneNumberFormatter dan OLDIN qirqardi, va takrorlangan 998 ni
        // olib tashlash qoidasi (u faqat 9 tadan uzun raqamda ishlaydi)
        // hech qachon ishga tushmasdi. Uzunlikni formatterning o'zi
        // cheklaydi.
        _PhoneNumberFormatter(),
      ],
      decoration: InputDecoration(
        hintText: widget.hintText ?? '+998 901234567',
        prefixIcon: Icon(
          widget.prefixIcon ?? Icons.phone,
          color: AppColors.primaryGreen,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      validator: widget.validator ??
          (value) {
            // substring(5) EMAS: maydonda prefiks bo'lmasligi ham mumkin
            // (qiymat tashqaridan berilgan holat), va o'sha yerda substring
            // xatolik bilan yiqilardi.
            final phoneDigits = normalizeUzbekPhoneDigits(value ?? '');
            if (phoneDigits.isEmpty) {
              return 'messages.enter_phone_number'.tr();
            }
            if (phoneDigits.length != 9) {
              return 'messages.enter_full_phone_number'.tr();
            }
            return null;
          },
      onChanged: (value) {
        if (widget.onChanged != null) {
          widget.onChanged!();
        }
      },
    );
  }
}

/// Kiritilgan matndan O'ZBEKISTON raqamining 9 ta raqamini ajratib oladi.
///
/// Odam raqamni turlicha yozadi yoki QO'YADI (paste):
///   +998901234567, 998901234567, 00998901234567,
///   +998 90 123 45 67, (90) 123-45-67, 901234567
/// Hammasi bir xil natija berishi kerak: 901234567.
///
/// Nega alohida funksiya. Ilgari tekshiruv `value.substring(5)` qilardi va
/// maydonning boshida aynan "+998 " turishiga tayanardi. Boshqacha yozilgan
/// raqam esa yo TOZALAB tashlanardi, yo noto'g'ri qirqilardi — va eng yomoni,
/// 998901234567 ni yozgan odam "+998 998901234" ni olardi: bu mavjud bo'lmagan
/// raqam, lekin tekshiruvdan O'TARDI (9 ta raqam!). Ilova hech narsa demasdan
/// ro'yxatdan o'tishga olib borardi.
String normalizeUzbekPhoneDigits(String input) {
  var text = input.trimLeft();

  // Maydonda KO'RINIB turgan "+998 " prefiksi — matnning bir qismi. Uni
  // eng avval olib tashlaymiz, aks holda u kiritilgan raqamlarga qo'shilib
  // ketadi: har bosilgan tugmadan keyin matn "+998 9" bo'ladi va prefiks
  // raqam deb hisoblanardi.
  if (text.startsWith('+998')) {
    text = text.substring(4);
  }

  var digits = text.replaceAll(RegExp(r'\D'), '');

  // Xalqaro prefikslar: 00998... va 998...
  if (digits.startsWith('00998')) {
    digits = digits.substring(5);
  } else if (digits.length > 9 && digits.startsWith('998')) {
    digits = digits.substring(3);
  }

  // Eski ichki format: 8 (90) 123-45-67
  if (digits.length == 10 && digits.startsWith('8')) {
    digits = digits.substring(1);
  }

  if (digits.length > 9) {
    digits = digits.substring(0, 9);
  }
  return digits;
}

/// +998 prefiksini doim saqlab turadigan formatter.
/// 901234567 -> +998 901234567
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Matn butunlay normalizatsiyadan o'tadi: prefiks bor-yo'qligiga
    // tayanmaymiz. Ilgari "+998 " bilan boshlanmagan har qanday matn
    // TOZALAB tashlanardi — ya'ni to'liq raqamni qo'ygan odam bo'sh
    // maydon olardi.
    final digits = normalizeUzbekPhoneDigits(newValue.text);
    final formatted = '+998 $digits';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Helper function to get clean phone number (only digits with 998 prefix)
/// Example: +998 901234567 -> 998901234567
String getCleanPhoneNumber(String formattedPhone) {
  final digits = normalizeUzbekPhoneDigits(formattedPhone);
  return digits.length == 9 ? '998$digits' : digits;
}

/// Raqamni KO'RSATISH uchun formatlaydi.
/// 998901234567 -> +998 901234567
///
/// Tanib bo'lmasa — kelgan qiymat o'zgarishsiz qaytariladi: ekranda
/// buzilgan matndan ko'ra odam yozgan narsa turgani yaxshiroq.
String formatPhoneNumber(String phone) {
  final digits = normalizeUzbekPhoneDigits(phone);
  return digits.length == 9 ? '+998 $digits' : phone;
}
