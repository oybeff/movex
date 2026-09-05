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
        super.onCreate(savedInstanceState)
    }
}

