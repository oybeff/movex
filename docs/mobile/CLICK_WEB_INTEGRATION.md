# Click To'lov - Web Sayt Integratsiyasi

## 📋 Umumiy Ma'lumot

Bu hujjat web sayt uchun Click to'lov tizimini integratsiya qilish bo'yicha to'liq qo'llanma.

## 🔧 Backend API (FastAPI)

### 1. Environment Variables

`.env` fayliga qo'shing:

```env
# Click Credentials
CLICK_MERCHANT_ID=12345
CLICK_SERVICE_ID=67890
CLICK_SECRET_KEY=your_secret_key_here
CLICK_MERCHANT_USER_ID=1

# Web uchun return URL
CLICK_RETURN_URL=https://yourdomain.com/payment/success
```

### 2. API Endpoints

#### 2.1. To'lov Yaratish

**Request:**
```http
POST /api/balance/topup
Authorization: Bearer {token}
Content-Type: application/json

{
  "amount": 50000,
  "payment_method": "click",
  "phone_number": "+998901234567"
}
```

**Response:**
```json
{
  "transaction_id": 123,
  "amount": 50000,
  "payment_method": "click",
  "status": "pending",
  "payment_url": "https://my.click.uz/services/pay?service_id=...&return_url=..."
}
```

#### 2.2. To'lov Statusini Tekshirish

**Request:**
```http
GET /api/balance/transactions/{transaction_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "id": 123,
  "amount": 50000,
  "status": "completed",
  "payment_method": "click",
  "created_at": "2025-11-13T14:30:00",
  "phone_number": "+998901234567"
}
```

### 3. Click Callback Endpoints

Click merchant panel'da sozlang:

```
Prepare URL: https://yourdomain.com/api/balance/click/prepare
Complete URL: https://yourdomain.com/api/balance/click/complete
```

## 🌐 Frontend (Web)

### 1. HTML/JavaScript Integratsiya

#### Oddiy HTML Form

```html
<!DOCTYPE html>
<html>
<head>
    <title>Hisob To'ldirish</title>
</head>
<body>
    <h1>Hisob To'ldirish</h1>
    
    <form id="topupForm">
        <label>Summa (so'm):</label>
        <input type="number" id="amount" min="10000" max="10000000" required>
        
        <label>Telefon raqam:</label>
        <input type="tel" id="phone" placeholder="+998 90 123 45 67" required>
        
        <button type="submit">Click orqali to'lash</button>
    </form>

    <script>
        const API_URL = 'https://yourdomain.com/api';
        const token = localStorage.getItem('token'); // Yoki cookie'dan

        document.getElementById('topupForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const amount = document.getElementById('amount').value;
            const phone = document.getElementById('phone').value;
            
            try {
                const response = await fetch(`${API_URL}/balance/topup`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify({
                        amount: parseFloat(amount),
                        payment_method: 'click',
                        phone_number: phone
                    })
                });
                
                const data = await response.json();
                
                if (data.payment_url) {
                    // Click to'lov sahifasiga yo'naltirish
                    window.location.href = data.payment_url;
                } else {
                    alert('Xatolik yuz berdi');
                }
            } catch (error) {
                console.error('Error:', error);
                alert('Xatolik yuz berdi');
            }
        });
    </script>
</body>
</html>
```

### 2. React Integratsiya

```jsx
import React, { useState } from 'react';
import axios from 'axios';

function BalanceTopUp() {
    const [amount, setAmount] = useState('');
    const [phone, setPhone] = useState('');
    const [loading, setLoading] = useState(false);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);

        try {
            const response = await axios.post(
                '/api/balance/topup',
                {
                    amount: parseFloat(amount),
                    payment_method: 'click',
                    phone_number: phone
                },
                {
                    headers: {
                        'Authorization': `Bearer ${localStorage.getItem('token')}`
                    }
                }
            );

            if (response.data.payment_url) {
                // Click to'lov sahifasiga yo'naltirish
                window.location.href = response.data.payment_url;
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Xatolik yuz berdi');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div>
            <h1>Hisob To'ldirish</h1>
            <form onSubmit={handleSubmit}>
                <input
                    type="number"
                    placeholder="Summa"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    min="10000"
                    max="10000000"
                    required
                />
                <input
                    type="tel"
                    placeholder="+998 90 123 45 67"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    required
                />
                <button type="submit" disabled={loading}>
                    {loading ? 'Yuklanmoqda...' : 'Click orqali to\'lash'}
                </button>
            </form>
        </div>
    );
}

export default BalanceTopUp;
```

### 3. Vue.js Integratsiya

```vue
<template>
  <div class="balance-topup">
    <h1>Hisob To'ldirish</h1>
    <form @submit.prevent="handleSubmit">
      <div class="form-group">
        <label>Summa (so'm):</label>
        <input
          v-model="amount"
          type="number"
          min="10000"
          max="10000000"
          required
        />
      </div>

      <div class="form-group">
        <label>Telefon raqam:</label>
        <input
          v-model="phone"
          type="tel"
          placeholder="+998 90 123 45 67"
          required
        />
      </div>

      <button type="submit" :disabled="loading">
        {{ loading ? 'Yuklanmoqda...' : 'Click orqali to\'lash' }}
      </button>
    </form>
  </div>
</template>

<script>
import axios from 'axios';

export default {
  name: 'BalanceTopUp',
  data() {
    return {
      amount: '',
      phone: '',
      loading: false
    };
  },
  methods: {
    async handleSubmit() {
      this.loading = true;

      try {
        const response = await axios.post('/api/balance/topup', {
          amount: parseFloat(this.amount),
          payment_method: 'click',
          phone_number: this.phone
        }, {
          headers: {
            'Authorization': `Bearer ${localStorage.getItem('token')}`
          }
        });

        if (response.data.payment_url) {
          window.location.href = response.data.payment_url;
        }
      } catch (error) {
        console.error('Error:', error);
        alert('Xatolik yuz berdi');
      } finally {
        this.loading = false;
      }
    }
  }
};
</script>
```

## 📱 Return URL - To'lovdan Qaytish

### Web uchun Success Page

```html
<!DOCTYPE html>
<html>
<head>
    <title>To'lov Natijasi</title>
</head>
<body>
    <div id="result">
        <h1>To'lov jarayoni yakunlandi</h1>
        <p>Balans yangilanmoqda...</p>
    </div>

    <script>
        // URL'dan transaction_id olish
        const urlParams = new URLSearchParams(window.location.search);
        const transactionId = urlParams.get('transaction_param');

        if (transactionId) {
            // Transaction statusini tekshirish
            checkPaymentStatus(transactionId);
        }

        async function checkPaymentStatus(transactionId) {
            const token = localStorage.getItem('token');

            try {
                const response = await fetch(
                    `https://yourdomain.com/api/balance/transactions/${transactionId}`,
                    {
                        headers: {
                            'Authorization': `Bearer ${token}`
                        }
                    }
                );

                const transaction = await response.json();

                if (transaction.status === 'completed') {
                    document.getElementById('result').innerHTML = `
                        <h1>✅ To'lov muvaffaqiyatli!</h1>
                        <p>Summa: ${transaction.amount} so'm</p>
                        <p>Hisobingiz to'ldirildi.</p>
                        <a href="/dashboard">Bosh sahifaga qaytish</a>
                    `;
                } else if (transaction.status === 'failed') {
                    document.getElementById('result').innerHTML = `
                        <h1>❌ To'lov amalga oshmadi</h1>
                        <p>Iltimos, qaytadan urinib ko'ring.</p>
                        <a href="/balance">Qaytadan urinish</a>
                    `;
                } else {
                    // Pending - 3 soniyadan keyin qayta tekshirish
                    setTimeout(() => checkPaymentStatus(transactionId), 3000);
                }
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('result').innerHTML = `
                    <h1>⚠️ Xatolik</h1>
                    <p>To'lov holatini tekshirishda xatolik yuz berdi.</p>
                    <a href="/balance">Qaytish</a>
                `;
            }
        }
    </script>
</body>
</html>
```

## 🔒 Xavfsizlik

### 1. CORS Sozlamalari

Backend'da CORS sozlang:

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://yourdomain.com"],  # Faqat o'z domeningiz
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### 2. HTTPS

- Production'da faqat HTTPS ishlatilishi kerak
- Click callback'lar uchun ham HTTPS majburiy

### 3. Token Xavfsizligi

- JWT token'ni localStorage yoki httpOnly cookie'da saqlang
- Token'ni har bir request'da Authorization header'da yuboring

## 📊 To'lov Oqimi (Flow)

```
1. Foydalanuvchi web sahifada summa va telefon raqam kiritadi
   ↓
2. Frontend backend'ga POST /api/balance/topup yuboradi
   ↓
3. Backend pending transaction yaratadi va payment_url qaytaradi
   ↓
4. Frontend foydalanuvchini Click sahifasiga yo'naltiradi
   ↓
5. Foydalanuvchi Click'da to'lovni amalga oshiradi
   ↓
6. Click backend'ga prepare va complete callback'larini yuboradi
   ↓
7. Backend balansni yangilaydi va Telegram'ga xabar yuboradi
   ↓
8. Click foydalanuvchini return_url'ga qaytaradi
   ↓
9. Web sahifa transaction statusini tekshiradi va natijani ko'rsatadi
```

## 🧪 Test Qilish

### 1. Local Test

```bash
# Backend ishga tushirish
cd movex_go_backend
uvicorn app.main:app --reload

# Frontend (masalan, React)
cd frontend
npm start
```

### 2. Ngrok orqali Test

Click callback'larni test qilish uchun:

```bash
# Ngrok o'rnatish
brew install ngrok  # macOS
# yoki https://ngrok.com/download

# Backend'ni expose qilish
ngrok http 8000

# Ngrok URL'ni Click merchant panel'da sozlang:
# Prepare: https://abc123.ngrok.io/api/balance/click/prepare
# Complete: https://abc123.ngrok.io/api/balance/click/complete
```

## 📞 Yordam

### Click Support

- **Email:** support@click.uz
- **Telefon:** +998 71 200 0 200
- **Merchant Panel:** https://my.click.uz/

### Foydali Linklar

- **Click API Documentation:** https://docs.click.uz/
- **Test Merchant:** Click support'dan test credentials so'rang

---

**Muvaffaqiyatli integratsiya! 🎉**


