import Flutter
import UIKit
import YandexMapsMobile

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Xarita kaliti ishga tushishdan OLDIN berilishi shart.
    //
    // Android tomonida bu MainActivity da qilingan, iOS da esa umuman
    // yo'q edi — ya'ni iPhone da xarita ishlamas edi. Ilovada xarita
    // asosiy narsa: mijoz texnikani xaritada tanlaydi va yetkazib berish
    // nuqtasini ko'rsatadi.
    //
    // Kalit Info.plist dagi YandexMapKitApiKey dan olinadi, u yerda
    // bo'lmasa — Android bilan bir xil qiymat ishlatiladi.
    let apiKey = (Bundle.main.object(forInfoDictionaryKey: "YandexMapKitApiKey") as? String)
      .flatMap { $0.isEmpty ? nil : $0 }
      ?? "d4a9d1e8-3f25-47a4-8ae1-ebbf04682c3d"

    YMKMapKit.setApiKey(apiKey)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
