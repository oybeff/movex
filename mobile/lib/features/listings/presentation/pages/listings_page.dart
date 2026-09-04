import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import 'create_listing_page.dart';
import 'listings_feed_view.dart';
import 'my_listings_view.dart';
import 'saved_listings_view.dart';

/// E'lonlar bo'limi — ikkala rol uchun BIR XIL ekran.
///
/// E'lon ikki tomonlama: mijoz "gruzchik kerak" deb yozadi, ega "ertaga
/// ekskavator bo'sh" deb yozadi, va ikkalasi ham bir-birining e'loniga javob
/// bera oladi. Shuning uchun rolga qarab boshqa-boshqa ekran ko'rsatishning
/// ma'nosi yo'q: ilgari mijozda faqat "meniki", egada faqat taxta bor edi —
/// natijada ega e'lon joylay olmasdi (tugma yo'q edi), egaga esa hech kim
/// javob bera olmasdi.
///
/// Ikki bo'lim: taxta (begonalarniki, javob berish uchun) va o'ziniki
/// (tasdiqlash va yopish uchun). "Joylash" tugmasi ikkalasida ham turadi.
class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);

  // Bo'limlar o'z ma'lumotini o'zi yuklaydi, lekin e'lon joylangandan keyin
  // ikkalasini ham yangilash kerak: yangi e'lon "meniki" ga tushadi va
  // taxtadagi hisob o'zgarishi mumkin.
  final _feedKey = GlobalKey<ListingsFeedViewState>();
  final _mineKey = GlobalKey<MyListingsViewState>();
  final _savedKey = GlobalKey<SavedListingsViewState>();

  /// Saqlanganlar taxtadan boshqariladi: odam taxtada xatcho'p bosadi,
  /// keyin shu bo'limga o'tadi. Bo'lim ochilganda qayta yuklanmasa, u
  /// eski ro'yxatni ko'rsatib turardi.
  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 2) _savedKey.currentState?.reload();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingPage()),
    );
    if (created != true || !mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('listings.created'.tr())));

    // Yangi e'lon "meniki" da — o'sha bo'limga o'tkazamiz, aks holda odam
    // e'lon joylagach bo'sh taxtaga qarab qoladi va joylanganiga ishonmaydi.
    _tabs.animateTo(1);
    _mineKey.currentState?.reload();
    _feedKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'listings.section_title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primaryGreen,
          labelStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'listings.tab_board'.tr()),
            Tab(text: 'listings.tab_mine'.tr()),
            Tab(text: 'listings.tab_saved'.tr()),
          ],
        ),
      ),
      // Tugma pastki menyudan yuqorida turishi kerak: tashqi Scaffold
      // extendBody bilan, ya'ni sahifa menyu ostidan davom etadi va oddiy
      // tugma o'sha yerda ko'rinmay qolardi.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: _create,
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: Text('listings.create'.tr()),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ListingsFeedView(key: _feedKey),
          MyListingsView(key: _mineKey),
          SavedListingsView(key: _savedKey),
        ],
      ),
    );
  }
}
