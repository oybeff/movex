import 'package:flutter/services.dart' show appFlavor;

/// Какое приложение собрано из этого кода.
///
/// С 21.11.2026 их два (решение владельца продукта): клиентское
/// «MoveXgo» (`uz.movexgo.app`) и «MoveX GO Driver» (`uz.movexgo.driver`)
/// для владельцев техники. Код, вход, сеть и переводы общие; различаются
/// только главная после входа и выбор роли. Flavor задаёт сборка
/// (`flutter run --flavor driver`), без него — client.
abstract final class AppFlavor {
  static bool get isDriver => appFlavor == 'driver';

  /// Куда вести человека после входа, по его роли.
  ///
  /// В приложении водителя клиентский аккаунт не пускается дальше
  /// заставки «это приложение для владельцев техники» — иначе он увидел
  /// бы экраны, которые сервер ему всё равно запретит.
  static String homeFor(String? role) {
    if (isDriver) {
      return role == 'owner' ? '/driverHome' : '/driver-wrong-role';
    }
    if (role == 'client') return '/clientHome';
    if (role == 'owner') return '/ownerHome';
    return '/';
  }
}
