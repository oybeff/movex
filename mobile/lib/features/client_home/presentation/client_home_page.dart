import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_main_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_catalog_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_history_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/client_profile_page.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ClientMainPage(),
    ClientCatalogPage(),
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
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
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
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              selectedIconTheme: const IconThemeData(size: 28),
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
