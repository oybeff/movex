package uz.movexgo.app

import io.flutter.embedding.android.FlutterActivity
import com.yandex.mapkit.MapKitFactory

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Важно: сначала ключ
        MapKitFactory.setApiKey("d4a9d1e8-3f25-47a4-8ae1-ebbf04682c3d")
        super.onCreate(savedInstanceState)
    }
}

