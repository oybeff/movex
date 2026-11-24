import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/app_flavor.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../materials/presentation/pages/materials_catalog_page.dart';
import '../../../taxi/data/app_status.dart';
import 'create_listing_page.dart';
import 'listings_feed_view.dart';
import 'my_listings_view.dart';
import 'saved_listings_view.dart';
import '../../../../core/widgets/h_icon.dart';

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

  /// Кнопка «Qurilish materiallari» над объявлениями (просьба 23.11.2026).
  /// Только в клиентском приложении и только пока раздел включён в админке.
  bool _materials = !AppFlavor.isDriver && (AppStatus.last?.materialsEnabled ?? true);

  @override
  void initState() {
    super.initState();
    if (!AppFlavor.isDriver) {
      AppStatus.fetch().then((s) {
        if (s != null && mounted) setState(() => _materials = s.materialsEnabled);
      });
    }
  }

  void _openMaterials() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MaterialsCatalogPage()),
    );
  }

  Widget _materialsBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
      child: Material(
        color: AppPalette.brandSubtle,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: _openMaterials,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: const HIcon(Icons.inventory_2_outlined, color: AppPalette.iconBrand),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('listings.materials_button'.tr(),
                          style: AppTypography.bodyMedium.copyWith(
                              color: AppPalette.textPrimary, fontWeight: FontWeight.w600)),
                      Text('listings.materials_hint'.tr(),
                          style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                    ],
                  ),
                ),
                const HIcon(Icons.chevron_right, color: AppPalette.iconBrand),
              ],
            ),
          ),
        ),
      ),
    );
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
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        // «Назад» показывается сам, только если есть куда вернуться: у
        // клиента раздел открывается из профиля, у владельца — вкладка.
        title: Text(
          'listings.section_title'.tr(),
          style: AppTypography.h3.copyWith(
              color: AppPalette.textPrimary, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppPalette.brand,
          unselectedLabelColor: AppPalette.textSecondary,
          indicatorColor: AppPalette.brand,
          labelStyle: AppTypography.bodyMMedium.copyWith(
              fontWeight: FontWeight.w600),
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
          backgroundColor: AppPalette.brand,
          foregroundColor: AppPalette.textOnBrand,
          icon: const HIcon(Icons.add),
          label: Text('listings.create'.tr()),
        ),
      ),
      body: Column(
        children: [
          if (_materials) _materialsBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListingsFeedView(key: _feedKey),
                MyListingsView(key: _mineKey),
                SavedListingsView(key: _savedKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
