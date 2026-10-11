import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movex_go/core/services/equipment_request_service.dart';
import 'package:movex_go/features/requests/presentation/pages/incoming_order_page.dart';
import 'package:movex_go/features/owner_home/presentation/widgets/bottom_nav_bar.dart';

import 'package:movex_go/features/listings/presentation/pages/listings_page.dart';

import 'dashboard_page.dart';
import 'my_equipment_page.dart';
import 'orders_page.dart';
import 'chat_page.dart';
import 'payments_page.dart';

/// Pastki menyu bo'limlarining raqamlari.
///
/// Nomlangan, chunki ular ekranlar orasida uzatiladi: dashboard "buyurtmalar"
/// tugmasi shu raqam bilan sahifa almashtiradi. Ilgari u yerda oddiy 2 va 3
/// turardi va menyuga bitta band qo'shilishi bilan tugmalar boshqa sahifani
/// ocha boshlardi — hech qanday xatosiz, shunchaki noto'g'ri.
class OwnerTab {
  const OwnerTab._();

  static const int dashboard = 0;
  static const int equipment = 1;
  static const int listings = 2;
  static const int orders = 3;
  static const int chat = 4;
}

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key});

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // ------------------------------------------------ tez buyurtmalar
  //
  // Push hali ulanmagan (Firebase loyihasi yo'q), shuning uchun ilova ochiq
  // turganda server vaqti-vaqti bilan so'raladi. Yangi tez buyurtma kelsa
  // "yangi buyurtma" ekrani o'zi ochiladi — kim birinchi olsa, o'shaniki.
  static const _pollEvery = Duration(seconds: 15);
  final EquipmentRequestService _requests = EquipmentRequestService();
  final Set<int> _seenQuick = {};
  Timer? _poll;
  bool _showingQuick = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fonda so'ramaymiz: batareya va trafik
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _poll?.cancel();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _checkQuick();
    _poll = Timer.periodic(_pollEvery, (_) => _checkQuick());
  }

  Future<void> _checkQuick() async {
    if (_showingQuick || !mounted) return;
    try {
      final items = await _requests.quickIncoming();
      final fresh = items.where((o) => !_seenQuick.contains(o.id)).toList();
      if (fresh.isEmpty || !mounted || _showingQuick) return;
      final order = fresh.first;
      _seenQuick.add(order.id);
      _showingQuick = true;
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingOrderPage(order: order),
        ),
      );
      _showingQuick = false;
      if (accepted == true && mounted) _onTap(OwnerTab.orders);
    } catch (_) {
      _showingQuick = false;
    }
  }

  List<Widget> get _pages => [
    DashboardPage(onNavigate: _onTap),
    const MyEquipmentPage(),
    const ListingsPage(),
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
