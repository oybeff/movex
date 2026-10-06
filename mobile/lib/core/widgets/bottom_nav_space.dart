import 'package:flutter/material.dart';

/// Pastki suzuvchi menyu balandligi (chekkalari bilan).
///
/// Ikkala rolda ham menyu `Scaffold(extendBody: true)` ustida suzadi,
/// ya'ni sahifa UNING OSTIDAN davom etadi. Shuning uchun ro'yxatning
/// oxiriga shuncha bo'sh joy qo'shilishi kerak — aks holda oxirgi
/// kartochka menyu ostida qolib ketadi: ko'rinmaydi ham, bosilmaydi ham.
///
/// Raqam: BottomNavigationBar ~56 + paddingi 12 + tashqi chekka 6 ≈ 74,
/// ustiga ozgina havo.
const double kFloatingNavHeight = 80;

/// Menyu ostida qoladigan joy + telefonning o'z pastki chekkasi
/// (jest chizig'i). Ro'yxatlarning pastki `padding` iga shu qo'shiladi.
double bottomNavInset(BuildContext context) =>
    kFloatingNavHeight + MediaQuery.of(context).padding.bottom;

/// Ro'yxat oxiriga qo'yiladigan bo'shliq.
///
/// `padding` ni o'zgartirib bo'lmaydigan joylarda ishlatiladi: masalan
/// Column ichidagi oxirgi element sifatida.
class BottomNavSpace extends StatelessWidget {
  const BottomNavSpace({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: bottomNavInset(context));
}
