# Click To'lov - Telefon Raqam va Telegram Notification

## ✅ Yangi Qo'shilgan Funksiyalar

### 1. Telefon Raqam Integratsiyasi
- ✅ Foydalanuvchi Click to'lov qilishda telefon raqamini kiritadi
- ✅ Telefon raqam avtomatik formatlashtiriladi (+998901234567)
- ✅ Probel va belgilar avtomatik olib tashlanadi
- ✅ O'zbekiston telefon raqamlari validatsiyasi
- ✅ Telefon raqam database'da saqlanadi

### 2. Telegram Notification
- ✅ To'lov muvaffaqiyatli bo'lganda Telegram guruhga xabar yuboriladi
- ✅ Xabarda: foydalanuvchi ismi, telefon raqam, summa, vaqt
- ✅ HTML formatda chiroyli xabar
- ✅ Topic support (supergroup uchun)

## 🔧 Sozlash

### 1. Telegram Bot Yaratish

**BotFather orqali bot yaratish:**

1. Telegram'da `@BotFather` botini toping
2. `/newbot` buyrug'ini yuboring
3. Bot nomini kiriting (masalan: "Movex GO Payments")
4. Bot username'ini kiriting (masalan: "movexgo_payments_bot")
5. BotFather sizga **bot token** beradi:
   ```
   1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
   ```

**Guruhga bot qo'shish:**

1. Telegram guruh yarating yoki mavjud guruhni ishlating
2. Guruhga botni qo'shing (Add Members)
3. Botga admin huquqi bering (Settings → Administrators → Add Admin)

**Guruh ID olish:**

1. Guruhga `@userinfobot` botini qo'shing
2. Guruhda biror xabar yuboring
3. Bot sizga guruh ID'sini ko'rsatadi (masalan: `-1001234567890`)
4. Yoki `@getidsbot` ishlatishingiz mumkin

**Topic ID olish (agar supergroup bo'lsa):**

1. Guruhda topic yarating
2. Topic'ga xabar yuboring
3. Xabarni forward qiling `@userinfobot` ga
4. Bot sizga topic ID'sini ko'rsatadi

### 2. Environment Variables

`.env` fayliga qo'shing:

```env
# Telegram Notification
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_GROUP_ID=-1001234567890
TELEGRAM_GROUP_TOPIC_ID=123  # Agar topic bo'lsa
```

### 3. Database Migration

```bash
cd movex_go_backend

# Alembic migration
alembic upgrade head

# Yoki qo'lda SQL
psql -U postgres -d movex_go -c "
ALTER TABLE balance_transactions 
ADD COLUMN click_trans_id INTEGER,
ADD COLUMN click_prepare_id INTEGER,
ADD COLUMN phone_number VARCHAR(20);
"
```

### 4. Test Qilish

**Telegram bot test:**

```bash
cd movex_go_backend
python -c "
from app.services.telegram_service import telegram_service
telegram_service.test_connection()
"
```

**To'lov test:**

1. Mobile ilovada Click to'lovni tanlang
2. Telefon raqam kiriting: `+998 90 123 45 67`
3. Summa kiriting: `50000`
4. To'lovni amalga oshiring
5. Telegram guruhda xabar paydo bo'lishi kerak

## 📱 Mobile App - Telefon Raqam Input

### Qanday Ishlaydi:

1. Foydalanuvchi Click to'lov usulini tanlaydi
2. Telefon raqam input maydoni paydo bo'ladi
3. Foydalanuvchi telefon raqamini kiritadi (har qanday formatda):
   - `+998 90 123 45 67`
   - `998901234567`
   - `90 123 45 67`
   - `+998-90-123-45-67`
4. Backend avtomatik formatlaydi: `+998901234567`
5. Validatsiya qilinadi (O'zbekiston raqamlari)

### Qo'llab-quvvatlanadigan Operatorlar:

- Beeline: 90, 91
- Uzmobile: 93, 94, 95, 97
- Ucell: 98, 99, 33
- Mobiuz: 88, 77
- Humans: 71
- Ums: 50

## 💬 Telegram Xabar Formati

To'lov muvaffaqiyatli bo'lganda quyidagi xabar yuboriladi:

```
💰 Yangi To'lov

👤 Foydalanuvchi: Shohruxbek Abdullayev
📱 Telefon: +998901234567
💵 Summa: 50 000 so'm
💳 To'lov usuli: Click
🆔 Transaction ID: #123
🕐 Vaqt: 13.11.2025 14:30:45

✅ To'lov muvaffaqiyatli amalga oshirildi!
```

## 🔒 Xavfsizlik

### Telefon Raqam:
- Faqat O'zbekiston raqamlari qabul qilinadi
- Avtomatik formatlash va validatsiya
- Database'da formatlangan holda saqlanadi

### Telegram:
- Bot token xavfsiz saqlanadi (.env)
- Faqat to'lov muvaffaqiyatli bo'lganda xabar yuboriladi
- Telegram xatosi to'lovga ta'sir qilmaydi

## 📊 Backend API O'zgarishlari

### Balance TopUp Endpoint

**Request:**
```json
POST /api/balance/topup
{
  "amount": 50000,
  "payment_method": "click",
  "phone_number": "+998 90 123 45 67"
}
```

**Response:**
```json
{
  "transaction_id": 123,
  "amount": 50000,
  "payment_method": "click",
  "status": "pending",
  "payment_url": "https://my.click.uz/services/pay?..."
}
```

## 🧪 Test Scenariolar

### 1. Telefon Raqam Test

```python
from app.utils.phone_utils import format_phone_number, validate_uzbek_phone

# Test 1: Formatlash
phone = "+998 90 123 45 67"
formatted = format_phone_number(phone)  # +998901234567

# Test 2: Validatsiya
is_valid = validate_uzbek_phone("+998901234567")  # True
is_valid = validate_uzbek_phone("+998801234567")  # False (80 operator yo'q)
```

### 2. Telegram Test

```python
from app.services.telegram_service import telegram_service

# Connection test
telegram_service.test_connection()

# Xabar yuborish test
telegram_service.send_payment_notification(
    user_name="Test User",
    phone_number="+998901234567",
    amount=50000,
    transaction_id=123,
    payment_method="Click"
)
```

## 📝 Yangi Fayllar

### Backend:
- `movex_go_backend/app/utils/phone_utils.py` - Telefon raqam utilities
- `movex_go_backend/app/services/telegram_service.py` - Telegram notification service

### Database:
- `balance_transactions.phone_number` - Yangi ustun

## ⚠️ Muhim Eslatmalar

1. **Telegram Bot:**
   - Bot guruhda admin bo'lishi kerak
   - Bot xabar yuborish huquqiga ega bo'lishi kerak

2. **Telefon Raqam:**
   - Faqat Click to'lov uchun majburiy
   - Boshqa to'lov usullari uchun ixtiyoriy

3. **Production:**
   - Telegram bot token'ni xavfsiz saqlang
   - Rate limiting qo'shing (spam oldini olish)
   - Logging sozlang

## 🔗 Foydali Linklar

- **Telegram Bot API:** https://core.telegram.org/bots/api
- **BotFather:** https://t.me/BotFather
- **Get IDs Bot:** https://t.me/getidsbot
- **User Info Bot:** https://t.me/userinfobot

---

**Muvaffaqiyatli integratsiya! 🎉**

