import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_main_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_catalog_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_history_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_profile_page.dart';
import 'package:movex_go/features/listings/presentation/pages/listings_page.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  int _currentIndex = 0;

  // E'lonlar katalog bilan buyurtmalar orasida: katalogda topilmagan narsa
  // shu yerda so'raladi, natijasi esa buyurtmalarga yaqin turadi.
  final List<Widget> _pages = const [
    ClientMainPage(),
    ClientCatalogPage(),
    ListingsPage(),
    ClientHistoryPage(),
    ClientProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        body: _pages[_currentIndex],
        bottomNavigationBar: Container(
          // Pastdagi chekka telefonning JEST CHIZIG'Ini hisobga oladi:
          // qat'iy 6 px da menyu Android 10+ va iPhone X+ da chiziq
          // ustiga tushib, pastki tugmalar bosilmay qolardi.
          margin: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: 6 + MediaQuery.of(context).padding.bottom,
          ),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: BottomNavigationBar(
              backgroundColor: Colors.white,
              currentIndex: _currentIndex,
              selectedItemColor: Colors.green,
              // Shrift kichraytirildi: 400 px li telefonda besh bo'limning
              // nomlari sig'masdi va "Obyavleniya" — "Obyavle..." bo'lib
              // qirqilardi.
              selectedFontSize: 11,
              unselectedFontSize: 11,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              selectedIconTheme: const IconThemeData(size: 26),
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.home_rounded),
                  label: 'client.home'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.search_rounded),
                  label: 'client.catalog'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.campaign_rounded),
                  label: 'client.listings'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.history_rounded),
                  label: 'client.orders'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.person_rounded),
                  label: 'client.profile'.tr(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
