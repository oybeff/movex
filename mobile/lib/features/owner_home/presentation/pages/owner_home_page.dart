import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movex_go/features/owner_home/presentation/widgets/bottom_nav_bar.dart';

import 'dashboard_page.dart';
import 'my_equipment_page.dart';
import 'orders_page.dart';
import 'chat_page.dart';
import 'payments_page.dart';

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key});

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  int _currentIndex = 0;

  List<Widget> get _pages => [
    DashboardPage(onNavigate: _onTap),
    const MyEquipmentPage(),
    const OrdersPage(),
    const ChatPage(),
    // const PaymentsPage(),
  ];

  void _onTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

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
        bottomNavigationBar: OwnerBottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
        ),
      ),
    );
  }
}
