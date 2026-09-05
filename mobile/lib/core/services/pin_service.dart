import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN kod va barmoq izi / yuz.
///
/// Nega bu kerak. Kirish tokeni endi MUDDATSIZ: odam bir marta kiradi va
/// ilova uni boshqa so'ramaydi. Telefon boshqa odam qo'liga tushsa, hisob
/// ochiq qolmasligi kerak — shuning uchun himoya ilovaning o'zida.
///
/// PIN KODNING O'ZI SAQLANMAYDI. Bazada faqat sha256(tuz + kod) yotadi.
/// Aks holda telefonga kirgan odam sozlamalar faylidan kodni o'qib olardi.
/// Tuz har bir o'rnatishda yangi — bir xil kodlarning xeshi ham har xil
/// bo'lsin.
class PinService {
  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';
  static const _biometricKey = 'pin_biometric_enabled';

  static const int pinLength = 4;

  static final LocalAuthentication _auth = LocalAuthentication();

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// PIN o'rnatilganmi.
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_hashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Yangi PIN o'rnatadi yoki eskisini almashtiradi.
  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _newSalt();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(pin, salt));
  }

  /// Kiritilgan kod to'g'rimi.
  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  /// PIN ni butunlay olib tashlaydi. Barmoq izi ham o'chadi: usiz
  /// biometriya yagona to'siq bo'lib qolardi, uni esa har doim ham
  /// ishlatib bo'lmaydi (barmoq ho'l, yuz niqob ostida).
  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_biometricKey);
  }

  /// Chiqishda chaqiriladi: boshqa odam kirsa, eski PIN qolmasin.
  static Future<void> resetOnLogout() => clearPin();

  // ---------------------------------------------------------- biometriya

  /// Telefon barmoq izi yoki yuzni umuman qo'llab-quvvatlaydimi va
  /// egasi uni sozlaganmi.
  static Future<bool> biometricsAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      // Qo'llab-quvvatlamaydigan telefon xato beradi — bu xato emas,
      // shunchaki biometriya yo'q.
      return false;
    }
  }

  static Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
  }

  /// Barmoq izi / yuz orqali tekshirish.
  ///
  /// `reason` — tizim oynasida ko'rinadigan matn, foydalanuvchi tilida
  /// bo'lishi kerak.
  static Future<bool> authenticateBiometric(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
