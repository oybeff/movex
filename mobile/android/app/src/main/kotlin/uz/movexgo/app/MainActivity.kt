package uz.movexgo.app

import io.flutter.embedding.android.FlutterFragmentActivity
import com.yandex.mapkit.MapKitFactory

// FlutterFragmentActivity, oddiy FlutterActivity emas: local_auth
// (barmoq izi / yuz) tizim oynasini FragmentActivity ustida ochadi va
// aks holda ishga tushganda yiqiladi.
class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Важно: сначала ключ
        MapKitFactory.setApiKey("d4a9d1e8-3f25-47a4-8ae1-ebbf04682c3d")
        // Язык карты, адресов и поиска. Без него MapKit берёт язык
        // системы, и на телефоне с английским интерфейсом адреса
        // приходили как «Uzbekistan, Tashkent, Writers' Alley». Язык
        // меняется только до инициализации — новый вступит после
        // перезапуска приложения.
        MapKitFactory.setLocale(mapLocale())
        super.onCreate(savedInstanceState)
    }

    /** Язык приложения: shared_preferences пишет ключ с префиксом «flutter.». */
    private fun mapLocale(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return when (prefs.getString("flutter.selected_language", "uz")) {
            "ru" -> "ru_RU"
            else -> "uz_UZ"
        }
    }
}
