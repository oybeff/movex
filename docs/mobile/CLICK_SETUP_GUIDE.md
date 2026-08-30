# Click To'lov Tizimi - O'rnatish Qo'llanmasi

## ✅ Bajarilgan Ishlar

Click to'lov tizimi to'liq integratsiya qilindi:

### Backend (Python/FastAPI)
- ✅ Click service yaratildi (`movex_go_backend/app/services/click_service.py`)
- ✅ Click prepare endpoint (`POST /api/balance/click/prepare`)
- ✅ Click complete endpoint (`POST /api/balance/click/complete`)
- ✅ Balance topup endpoint yangilandi - Click URL qaytaradi
- ✅ Database migration - `click_trans_id` va `click_prepare_id` ustunlari qo'shildi
- ✅ Signature verification (MD5 hash)
- ✅ Error handling va logging

### Mobile App (Flutter)
- ✅ Balance model yangilandi - `BalanceTopUpResponse` qo'shildi
- ✅ Balance service yangilandi - Click URL olish
- ✅ URL launcher integratsiyasi
- ✅ App lifecycle management - ortga qaytganda avtomatik yangilash
- ✅ Payment status tekshirish

## 🔧 Kerakli Sozlamalar

### 1. Click Merchant Account

Sizga Click'dan quyidagi ma'lumotlar kerak:

1. **CLICK_MERCHANT_ID** - Merchant ID
2. **CLICK_SERVICE_ID** - Service ID
3. **CLICK_SECRET_KEY** - Secret Key
4. **CLICK_MERCHANT_USER_ID** - Merchant User ID

**Qayerdan olish:**
- Click merchant panel: https://my.click.uz/
- Yoki Click support bilan bog'laning: support@click.uz

### 1.1. Telegram Bot (Yangi!)

Telegram guruhga xabar yuborish uchun:

1. **TELEGRAM_BOT_TOKEN** - BotFather'dan oling
2. **TELEGRAM_GROUP_ID** - Guruh ID
3. **TELEGRAM_GROUP_TOPIC_ID** - Topic ID (ixtiyoriy)

**Qanday olish:**
- `@BotFather` orqali bot yarating
- Guruhga bot qo'shing va admin qiling
- `@getidsbot` orqali guruh ID oling

**Batafsil:** `CLICK_PHONE_TELEGRAM_SETUP.md` faylini o'qing

### 2. Backend Environment Variables

`movex_go_backend/.env` fayliga qo'shing:

```env
# Click to'lov tizimi
CLICK_MERCHANT_ID=12345
CLICK_SERVICE_ID=67890
CLICK_SECRET_KEY=your_secret_key_here
CLICK_MERCHANT_USER_ID=1
CLICK_RETURN_URL=movexgo://payment/success

# Telegram Notification (Yangi!)
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_GROUP_ID=-1001234567890
TELEGRAM_GROUP_TOPIC_ID=123
```

### 3. Click Merchant Panel Sozlamalari

Click merchant panelingizda callback URL'larni sozlang:

**Prepare URL:**
```
https://your-domain.com/api/balance/click/prepare
```

**Complete URL:**
```
https://your-domain.com/api/balance/click/complete
```

**Eslatma:** 
- Test uchun: `http://your-test-server.com/api/balance/click/prepare`
- Production uchun: `https://api.movexgo.com/api/balance/click/prepare`

### 4. Database Migration

Backend papkasida:

```bash
cd movex_go_backend

# Alembic migration
alembic upgrade head

# Yoki qo'lda SQL
psql -U postgres -d movex_go -c "
ALTER TABLE balance_transactions 
ADD COLUMN click_trans_id INTEGER,
ADD COLUMN click_prepare_id INTEGER;
"
```

### 5. Backend Ishga Tushirish

```bash
cd movex_go_backend

# Virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
# yoki
venv\Scripts\activate  # Windows

# Dependencies
pip install -r requirements.txt

# Run
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 6. Mobile App Build

```bash
cd movex_go

# Dependencies
flutter pub get

# Run
flutter run

# Build APK
flutter build apk --release
```

## 📝 Click Merchant Panel'da Sozlash

### Prepare va Complete URL'larni Qo'shish

1. Click merchant panelga kiring: https://my.click.uz/
2. **Settings** → **Service Settings** ga o'ting
3. **Prepare URL** maydoniga kiriting:
   ```
   https://your-domain.com/api/balance/click/prepare
   ```
4. **Complete URL** maydoniga kiriting:
   ```
   https://your-domain.com/api/balance/click/complete
   ```
5. **Save** tugmasini bosing

### Test Muhitda Sozlash

Test uchun Click test credentials va test URL'larni ishlating:
- Test Prepare URL: `http://your-test-server.com/api/balance/click/prepare`
- Test Complete URL: `http://your-test-server.com/api/balance/click/complete`

## 🧪 Test Qilish

### 1. Backend Test

```bash
# Backend ishga tushiring
cd movex_go_backend
uvicorn app.main:app --reload

# Boshqa terminalda test qiling
curl -X POST http://localhost:8000/api/balance/topup \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 50000, "payment_method": "click"}'
```

Javob:
```json
{
  "transaction_id": 1,
  "amount": 50000,
  "payment_method": "click",
  "status": "pending",
  "payment_url": "https://my.click.uz/services/pay?..."
}
```

### 2. Mobile App Test

1. Ilovani ishga tushiring
2. Balance sahifasiga o'ting
3. "Hisob to'ldirish" tugmasini bosing
4. Summa kiriting (masalan, 50000)
5. "Click" to'lov usulini tanlang
6. "To'ldirish" tugmasini bosing
7. Click to'lov sahifasi ochiladi
8. Test karta ma'lumotlarini kiriting
9. To'lovni tasdiqlang
10. Ilovaga qaytib, balansning yangilanganini tekshiring

### 3. Click Callback Test

Click'dan kelgan so'rovlarni test qilish uchun:

```bash
# Prepare test
curl -X POST http://localhost:8000/api/balance/click/prepare \
  -d "click_trans_id=123456" \
  -d "service_id=12345" \
  -d "merchant_trans_id=1" \
  -d "amount=50000" \
  -d "action=0" \
  -d "sign_time=2025-11-13 12:00:00" \
  -d "sign_string=CALCULATED_SIGNATURE"
```

## 📊 Monitoring va Debugging

### Backend Logs

```bash
# Backend logs
tail -f movex_go_backend/logs/app.log
```

### Database Tekshirish

```sql
-- Pending transactions
SELECT * FROM balance_transactions WHERE status = 'pending';

-- Click transactions
SELECT * FROM balance_transactions WHERE payment_method = 'click';

-- User balance
SELECT * FROM balances WHERE user_id = 1;
```

### Click Merchant Panel

- Transaction history: https://my.click.uz/transactions
- Callback logs: https://my.click.uz/logs

## ⚠️ Muhim Eslatmalar

1. **Production'da:**
   - HTTPS ishlatish majburiy
   - Secret key'ni xavfsiz saqlang
   - Rate limiting qo'shing
   - Logging va monitoring sozlang

2. **Test Muhitda:**
   - Click test credentials ishlatiladi
   - Test karta: `8600 0000 0000 0000`
   - Test SMS kod: `666666`

3. **Xavfsizlik:**
   - Signature har doim tekshiriladi
   - Transaction amount va status validatsiya qilinadi
   - Duplicate to'lovlar oldini olinadi

## 🔗 Foydali Linklar

- **Click API Docs:** https://docs.click.uz/
- **Click Merchant Panel:** https://my.click.uz/
- **Click Support:** support@click.uz
- **Click Test Environment:** https://test.click.uz/

## 📞 Yordam

Agar muammolar yuzaga kelsa:

1. Backend logs'ni tekshiring
2. Click merchant panel'da transaction'larni ko'ring
3. Database'da transaction status'ni tekshiring
4. Click support bilan bog'laning

---

**Muvaffaqiyatli integratsiya! 🎉**

