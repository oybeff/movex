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
        FilteringTextInputFormatter.allow(RegExp(r'[\d\s+]')),
        LengthLimitingTextInputFormatter(14), // +998 + space + 9 digits
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
            if (value == null || value.isEmpty || value == '+998 ') {
              return 'messages.enter_phone_number'.tr();
            }
            // Get phone digits after +998 prefix
            final phoneDigits = value.substring(5).replaceAll(RegExp(r'\D'), '');
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

/// Phone number formatter to keep +998 prefix
/// Formats: 901234567 -> +998 901234567
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Always keep +998 prefix
    if (!text.startsWith('+998 ')) {
      return TextEditingValue(
        text: '+998 ',
        selection: const TextSelection.collapsed(offset: 5),
      );
    }

    // Get only the part after +998
    String phoneDigits = text.substring(5).replaceAll(RegExp(r'\D'), '');

    // Limit to 9 digits after +998
    if (phoneDigits.length > 9) {
      phoneDigits = phoneDigits.substring(0, 9);
    }

    // Build formatted string
    final formatted = '+998 $phoneDigits';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Helper function to get clean phone number (only digits with 998 prefix)
/// Example: +998 901234567 -> 998901234567
String getCleanPhoneNumber(String formattedPhone) {
  final digitsOnly = formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
  if (digitsOnly.length == 9) {
    return '998$digitsOnly';
  }
  return digitsOnly;
}

/// Helper function to format phone number for display
/// Example: 998901234567 -> +998 901234567
String formatPhoneNumber(String phone) {
  // Remove all non-digit characters
  String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

  // Remove 998 prefix if present
  if (digitsOnly.startsWith('998') && digitsOnly.length == 12) {
    digitsOnly = digitsOnly.substring(3);
  }

  if (digitsOnly.length != 9) {
    return phone; // Return original if not valid
  }

  return '+998 $digitsOnly';
}

