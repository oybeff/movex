import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movex_go/features/taxi/presentation/pages/taxi_home_page.dart';

/// Главная клиента.
///
/// Во втором макете (12.11.2026) у клиента НЕТ нижнего меню: экран — заказ
/// техники «как такси» на всю высоту, а заказы, баланс, каталог, объявления
/// и настройки открываются из профиля (кнопка слева сверху). Прежние пять
/// вкладок убраны, сами разделы остались — см. TaxiProfilePage.
class ClientHomePage extends StatelessWidget {
  const ClientHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: TaxiHomePage(),
    );
  }
}
