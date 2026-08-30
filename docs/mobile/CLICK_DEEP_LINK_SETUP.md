# Click Deep Link - Mobile App Return URL

## 📋 Umumiy Ma'lumot

Bu hujjat Click to'lov tizimidan mobil ilovaga qaytish (deep link) integratsiyasi haqida.

## 🔗 Deep Link Format

```
movexgo://payment/success
```

- **Scheme:** `movexgo`
- **Host:** `payment`
- **Path:** `/success`

## 📱 Mobile App Sozlamalari

### 1. Android (AndroidManifest.xml)

Fayl: `android/app/src/main/AndroidManifest.xml`

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    ...>
    
    <!-- Existing intent filters -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    
    <!-- Deep Link: movexgo://payment/success -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="movexgo" android:host="payment" />
    </intent-filter>
</activity>
```

### 2. iOS (Info.plist)

Fayl: `ios/Runner/Info.plist`

```xml
<dict>
    <!-- Existing keys -->
    ...
    
    <!-- Deep Link: movexgo://payment/success -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.movexgo.app</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>movexgo</string>
            </array>
        </dict>
    </array>
</dict>
```

### 3. Flutter Dependencies

`pubspec.yaml` fayliga qo'shing:

```yaml
dependencies:
  app_links: ^6.4.1
```

O'rnatish:

```bash
flutter pub add app_links
```

### 4. Flutter Code (main.dart)

```dart
import 'package:app_links/app_links.dart';
import 'dart:async';

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Initial link (ilova yopiq holatdan ochilganda)
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _handleDeepLink(uri);
      }
    } catch (e) {
      debugPrint('Deep link error: $e');
    }

    // Link stream (ilova ochiq holatda)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleDeepLink(uri),
      onError: (err) => debugPrint('Deep link stream error: $err'),
    );
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Deep link received: $uri');
    
    // movexgo://payment/success
    if (uri.scheme == 'movexgo' && uri.host == 'payment') {
      if (uri.path == '/success' || uri.pathSegments.contains('success')) {
        // Balance topup page'ga qaytish
        widget.router.go('/balance-topup');
        
        // Snackbar ko'rsatish
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          final context = widget.router.routerDelegate.navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('To\'lov jarayoni yakunlandi. Balans yangilanmoqda...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }
    }
  }
}
```

## 🔧 Backend Sozlamalari

### Environment Variables

`.env` fayliga qo'shing:

```env
# Mobile app uchun
CLICK_RETURN_URL=movexgo://payment/success

# Web uchun (agar kerak bo'lsa)
# CLICK_RETURN_URL=https://yourdomain.com/payment/success
```

### Click Service

`movex_go_backend/app/services/click_service.py`:

```python
class ClickService:
    RETURN_URL = os.getenv("CLICK_RETURN_URL", "movexgo://payment/success")
    
    @classmethod
    def generate_payment_url(cls, transaction_id: int, amount: float) -> str:
        base_url = "https://my.click.uz/services/pay"
        
        params = {
            "service_id": cls.SERVICE_ID,
            "merchant_id": cls.MERCHANT_ID,
            "merchant_user_id": cls.MERCHANT_USER_ID,
            "amount": amount,
            "transaction_param": transaction_id,
            "return_url": cls.RETURN_URL,  # Deep link
        }
        
        query_string = "&".join([f"{key}={value}" for key, value in params.items()])
        return f"{base_url}?{query_string}"
```

## 🧪 Test Qilish

### 1. Android Test

```bash
# ADB orqali deep link test
adb shell am start -W -a android.intent.action.VIEW -d "movexgo://payment/success"
```

### 2. iOS Test (Simulator)

```bash
# Terminal'da
xcrun simctl openurl booted "movexgo://payment/success"
```

### 3. Real Device Test

1. Click to'lovni amalga oshiring
2. To'lov yakunlangandan keyin avtomatik ilovaga qaytadi
3. Balance topup page ochiladi va snackbar ko'rsatiladi

## 📊 To'lov Oqimi

```
1. Foydalanuvchi mobil ilovada summa va telefon kiritadi
   ↓
2. Backend pending transaction yaratadi va Click URL qaytaradi
   ↓
3. Ilova URL launcher orqali Click sahifasini ochadi
   ↓
4. Foydalanuvchi Click'da to'lovni amalga oshiradi
   ↓
5. Click backend'ga prepare va complete callback yuboradi
   ↓
6. Backend balansni yangilaydi va Telegram'ga xabar yuboradi
   ↓
7. Click foydalanuvchini deep link orqali ilovaga qaytaradi
   ↓
8. Ilova deep link'ni qabul qiladi va balance page'ga o'tadi
   ↓
9. Balance page avtomatik yangilanadi (didChangeAppLifecycleState)
   ↓
10. Foydalanuvchi yangilangan balansni ko'radi
```

## ⚠️ Muhim Eslatmalar

### 1. URL Scheme Unique Bo'lishi Kerak

- `movexgo://` - bu sizning ilovangizga xos
- Boshqa ilovalar bilan conflict bo'lmasligi kerak

### 2. Android 12+ (API 31+)

Android 12 va undan yuqori versiyalarda `android:exported="true"` majburiy:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    ...>
```

### 3. iOS Universal Links (Ixtiyoriy)

Agar universal links kerak bo'lsa:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:yourdomain.com</string>
</array>
```

### 4. Web va Mobile Uchun Turli Return URL

Agar bir backend'da web va mobile bo'lsa:

```python
# Request'dan platform aniqlash
def generate_payment_url(transaction_id: int, amount: float, platform: str = "mobile"):
    if platform == "web":
        return_url = "https://yourdomain.com/payment/success"
    else:
        return_url = "movexgo://payment/success"
    
    # ...
```

## 🔍 Debugging

### Android Logs

```bash
adb logcat | grep -i "deep link"
```

### iOS Logs

Xcode → Window → Devices and Simulators → View Device Logs

### Flutter Logs

```dart
debugPrint('Deep link received: $uri');
```

## 📝 Qo'shimcha Ma'lumotlar

### app_links Package

- **Pub.dev:** https://pub.dev/packages/app_links
- **GitHub:** https://github.com/llfbandit/app_links

### Click Documentation

- **Merchant Panel:** https://my.click.uz/
- **Support:** support@click.uz

---

**Muvaffaqiyatli integratsiya! 🚀**

