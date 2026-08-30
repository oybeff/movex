# Как потестить на телефоне

Два способа. Первый работает сразу и без установок, но без карты. Второй —
настоящее приложение.

## Способ 1: через браузер телефона (сразу)

Телефон и компьютер должны быть в **одной Wi-Fi сети**.

1. Узнайте адрес компьютера:

   ```bash
   ipconfig getifaddr en0
   ```

2. Запустите сервисы **на всю сеть**, а не только на себя:

   ```bash
   # API
   cd backend
   venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

   # Приложение — в другом окне терминала
   cd mobile
   flutter build web --release --dart-define=API_BASE_URL=http://ВАШ_IP:8000
   cd build/web && python3 -m http.server 8091 --bind 0.0.0.0
   ```

   `--host 0.0.0.0` обязателен: по умолчанию сервер слушает только
   `127.0.0.1`, и телефон до него не достучится.

3. На телефоне откройте `http://ВАШ_IP:8091`

**Карта не заработает.** `yandex_mapkit` существует только под iOS и Android,
в браузере его нет — на главном экране клиента будет пустое место. Всё
остальное живое: каталог, заявки, заказы, чат, баланс, уведомления.

## Способ 2: APK на Android (настоящее приложение)

### Что нужно один раз

```bash
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
sdkmanager --licenses          # принять лицензии
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools
```

Java: подойдёт JDK 17 или 21. С 23 бывают сюрпризы у Android Gradle Plugin,
поэтому в проекте явно указан 21:

```bash
flutter config --jdk-dir="/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
```

### Сборка

```bash
cd mobile

# для теста на локальном сервере
flutter build apk --release --dart-define=API_BASE_URL=http://ВАШ_IP:8000

# для прода
flutter build apk --release --dart-define=API_BASE_URL=https://movex.004.uz
```

APK окажется в `build/app/outputs/flutter-apk/app-release.apk`.

### Установка на телефон

Через кабель:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Без кабеля: скопируйте файл на телефон любым способом и откройте его.
Android спросит разрешение на установку из этого источника — разрешите.

### Важно про локальный сервер

Android с 9-й версии **блокирует незашифрованный HTTP**. Приложение просто
не достучится до `http://192.168.x.x:8000`, причём ошибка будет невнятной —
«не удалось подключиться».

Поэтому в `android/app/src/main/res/xml/network_security_config.xml` есть
список адресов, которым HTTP разрешён. **IP адреса там записаны точно** —
`includeSubdomains` для них не работает, Android сверяет адрес целиком.

Сменилась сеть или роутер выдал другой адрес — допишите новый в этот файл.
Для прода это не нужно: `movex.004.uz` работает по HTTPS, а всему
остальному HTTPS в том же файле оставлен обязательным.

### Про подпись

`flutter build apk --release` подписывает **отладочным** ключом
(`signingConfig = signingConfigs.getByName("debug")` в
`android/app/build.gradle.kts`). Для установки на свой телефон этого хватает.

Для Google Play нужен свой ключ:

```bash
keytool -genkey -v -keystore ~/movexgo-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias movexgo
```

Потом `android/key.properties` (в git не класть) и `signingConfigs` в
`build.gradle.kts`. Потерянный ключ означает, что обновить приложение в Play
уже нельзя — храните его отдельно от репозитория.

## Способ 3: iPhone

Нужен полный Xcode (~17 ГБ) и CocoaPods. Дальше:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo gem install cocoapods
cd mobile/ios && pod install
```

Для установки на своё устройство хватит бесплатного Apple ID (приложение
проживёт 7 дней), для TestFlight и App Store нужен платный Developer Program.

Ключ Яндекс-карт на iOS читается из `Info.plist`
(`YandexMapKitApiKey`), запасное значение зашито в `AppDelegate.swift`.
Забудете про него — карта на iPhone не запустится, так уже было.
