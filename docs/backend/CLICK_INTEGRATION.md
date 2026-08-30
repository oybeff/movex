# Click To'lov Tizimi Integratsiyasi

## 📋 Umumiy Ma'lumot

Bu loyihaga Click to'lov tizimi to'liq integratsiya qilingan. Foydalanuvchilar mobil ilova orqali Click to'lov tizimi orqali hisoblarini to'ldirishlari mumkin.

## 🔧 O'rnatish va Sozlash

### 1. Environment Variables

`.env` faylingizga quyidagi ma'lumotlarni qo'shing:

```env
# Click to'lov tizimi
CLICK_MERCHANT_ID=your_click_merchant_id
CLICK_SERVICE_ID=your_click_service_id
CLICK_SECRET_KEY=your_click_secret_key
CLICK_MERCHANT_USER_ID=your_click_merchant_user_id
CLICK_RETURN_URL=movexgo://payment/success
```

**Eslatma:** Bu ma'lumotlarni Click'dan olishingiz kerak. Test uchun Click test credentials'larini ishlating.

### 2. Database Migration

Click uchun qo'shimcha ustunlarni qo'shish:

```bash
cd movex_go_backend
alembic upgrade head
```

Yoki qo'lda SQL:

```sql
ALTER TABLE balance_transactions 
ADD COLUMN click_trans_id INTEGER,
ADD COLUMN click_prepare_id INTEGER;
```

### 3. Click Merchant Panel Sozlamalari

Click merchant panelingizda quyidagi callback URL'larni sozlang:

- **Prepare URL:** `https://your-domain.com/api/balance/click/prepare`
- **Complete URL:** `https://your-domain.com/api/balance/click/complete`

## 🚀 Qanday Ishlaydi?

### Backend Flow

1. **Transaction Yaratish** (`POST /balance/topup`)
   - Foydalanuvchi summa va `payment_method: "click"` yuboradi
   - Backend pending transaction yaratadi
   - Click to'lov URL'ini qaytaradi

2. **Click Prepare** (`POST /balance/click/prepare`)
   - Click bu endpoint'ga prepare so'rovi yuboradi
   - Backend transaction mavjudligini va summa to'g'riligini tekshiradi
   - Signature tekshiradi
   - Success yoki error javob qaytaradi

3. **Click Complete** (`POST /balance/click/complete`)
   - Click to'lov muvaffaqiyatli bo'lganda bu endpoint'ga so'rov yuboradi
   - Backend transaction'ni `completed` qiladi
   - Foydalanuvchi balansini yangilaydi

### Mobile App Flow

1. Foydalanuvchi summa kiritadi va Click'ni tanlaydi
2. Backend'dan Click to'lov URL'ini oladi
3. URL launcher orqali Click sahifasini ochadi
4. Foydalanuvchi Click'da to'lovni amalga oshiradi
5. Ilova foreground'ga qaytganda avtomatik balansni yangilaydi
6. To'lov muvaffaqiyatli bo'lsa, yangilangan balansni ko'rsatadi

## 📝 API Endpoints

### 1. Hisob To'ldirish

**Request:**
```http
POST /api/balance/topup
Authorization: Bearer {token}
Content-Type: application/json

{
  "amount": 50000,
  "payment_method": "click"
}
```

**Response:**
```json
{
  "transaction_id": 123,
  "amount": 50000,
  "payment_method": "click",
  "status": "pending",
  "payment_url": "https://my.click.uz/services/pay?service_id=...&merchant_id=...&amount=50000&transaction_param=123"
}
```

### 2. Click Prepare Callback

**Request (Click'dan keladi):**
```http
POST /api/balance/click/prepare
Content-Type: application/x-www-form-urlencoded

click_trans_id=123456
service_id=12345
merchant_trans_id=123
amount=50000
action=0
sign_time=2025-11-13 12:00:00
sign_string=abc123...
```

**Response:**
```json
{
  "click_trans_id": 123456,
  "merchant_trans_id": 123,
  "merchant_prepare_id": 123,
  "error": 0,
  "error_note": "Success"
}
```

### 3. Click Complete Callback

**Request (Click'dan keladi):**
```http
POST /api/balance/click/complete
Content-Type: application/x-www-form-urlencoded

click_trans_id=123456
service_id=12345
merchant_trans_id=123
amount=50000
action=1
error=0
sign_time=2025-11-13 12:00:00
sign_string=abc123...
```

**Response:**
```json
{
  "click_trans_id": 123456,
  "merchant_trans_id": 123,
  "merchant_confirm_id": 123,
  "error": 0,
  "error_note": "Success"
}
```

## 🔒 Xavfsizlik

- Barcha Click callback'larda signature tekshiriladi
- MD5 hash orqali signature yaratiladi va tekshiriladi
- Transaction amount va status tekshiriladi
- Duplicate to'lovlar oldini olinadi

## 🧪 Test Qilish

### Test Credentials

Click test muhitida test qilish uchun:
- Test merchant ID va credentials'larni Click'dan oling
- `.env` fayliga test credentials'larni qo'ying

### Test Scenario

1. Mobil ilovada Click to'lovni tanlang
2. Test summa kiriting (masalan, 10000)
3. Click test sahifasida test karta ma'lumotlarini kiriting
4. To'lovni tasdiqlang
5. Ilovaga qaytib, balansning yangilanganini tekshiring

## 📞 Yordam

Agar muammolar yuzaga kelsa:
- Backend logs'ni tekshiring
- Click merchant panel'da transaction'larni ko'ring
- Database'da transaction status'ni tekshiring

## 🔗 Foydali Linklar

- [Click API Documentation](https://docs.click.uz/)
- [Click Merchant Panel](https://my.click.uz/)

