import 'package:go_router/go_router.dart';
import 'package:movex_go/features/owner_home/presentation/pages/franchise_manage_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/owner_home_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/add_equipment_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/edit_equipment_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/equipment_detail_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/rent_equipment_page.dart';
import 'package:movex_go/core/models/equipment_model.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/role_select_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleSelectPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) {
        final role = state.extra as String? ?? 'client';
        return RegisterPage(role: role);
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/owner',
      builder: (context, state) => const OwnerHomePage(),
    ),
    GoRoute(
      path: '/franchise',
      builder: (context, state) => const FranchiseManagePage(),
    ),
    GoRoute(
      path: '/add-equipment',
      builder: (context, state) => const AddEquipmentPage(),
    ),
    GoRoute(
      path: '/edit-equipment/:id',
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return EditEquipmentPage(equipmentId: id);
      },
    ),
    GoRoute(
      path: '/equipment-detail',
      builder: (context, state) {
        final equipment = state.extra as EquipmentModel;
        return EquipmentDetailPage(equipment: equipment);
      },
    ),
    GoRoute(
      path: '/rent-equipment',
      builder: (context, state) {
        final equipment = state.extra as EquipmentModel;
        return RentEquipmentPage(equipment: equipment);
      },
    ),
  ],
);
