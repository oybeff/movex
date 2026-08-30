/// Ilova sozlamalari, yig'ish vaqtida beriladi.
///
/// Ilgari server manzili dio_client.dart ichiga qo'lda yozilgan edi —
/// dasturchining uy tarmog'idagi IP (192.168.1.101). Shu holicha yig'ilgan
/// ilova hech kimda ishlamasdi.
///
/// Yig'ish:
///   flutter run   --dart-define=API_BASE_URL=http://192.168.1.101:8000
///   flutter build apk --release --dart-define=API_BASE_URL=https://movex.004.uz
///   flutter build ipa --release --dart-define=API_BASE_URL=https://movex.004.uz
///
/// Hech narsa berilmasa — prod manzili ishlatiladi: tasodifan chiqib ketgan
/// yig'ilma ishlaydigan serverga murojaat qilgani, dasturchining mahalliy
/// IP siga urilib turganidan yaxshiroq.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://movex.004.uz',
  );

  /// Tarmoq so'rovlarining to'liq jurnalini yoqish (token va so'rov tanasi
  /// bilan). Faqat qo'lda yoqiladi, reliz yig'ilmada hech qachon.
  static const bool verboseNetworkLog = bool.fromEnvironment(
    'VERBOSE_NETWORK_LOG',
    defaultValue: false,
  );
}
