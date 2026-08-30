# 🚜 Movex GO - Qurilish texnikasi ijarasi platformasi

Movex GO - bu qurilish texnikasini ijaraga berish va olish uchun zamonaviy platforma. Backend qismi FastAPI framework yordamida ishlab chiqilgan.

## 🚀 Tez Boshlash

**Deploy qilish uchun:** [START_HERE.md](../docs/backend/START_HERE.md) ⚡

**Subdomen:** movex.004.uz | **Papka:** /www/wwwroot/movex.004.uz

## 📋 Mundarija

- [Xususiyatlar](#xususiyatlar)
- [Texnologiyalar](#texnologiyalar)
- [Tizim talablari](#tizim-talablari)
- [O'rnatish](#ornatish)
- [Ishga tushirish](#ishga-tushirish)
- [API dokumentatsiya](#api-dokumentatsiya)
- [Loyiha strukturasi](#loyiha-strukturasi)
- [Database sxemasi](#database-sxemasi)
- [Testing](#testing)
- [Deployment](#deployment)
- [Hissa qo'shish](#hissa-qoshish)
- [Litsenziya](#litsenziya)

## ✨ Xususiyatlar

### Foydalanuvchi boshqaruvi
- ✅ JWT autentifikatsiya
- ✅ Rol-based access control (Client, Owner, Admin)
- ✅ Foydalanuvchi profili boshqaruvi
- ✅ Parol xavfsizligi (bcrypt hashing)

### Texnika boshqaruvi
- ✅ Texnika qo'shish, tahrirlash, o'chirish
- ✅ Ko'p rasmli galereya
- ✅ Geolokatsiya (latitude, longitude)
- ✅ Turli narx variantlari (soatlik, smenali, kunlik)
- ✅ Texnika holati (available, busy, maintenance)
- ✅ Soft delete funksiyasi

### Buyurtma tizimi
- ✅ Buyurtma yaratish va boshqarish
- ✅ Buyurtma holati (pending, confirmed, completed, cancelled)
- ✅ Avtomatik komissiya hisoblash
- ✅ Buyurtma tarixi

### Chat tizimi
- ✅ Buyurtma bo'yicha chat
- ✅ Real-time xabarlar
- ✅ Xabar tarixi

### To'lov tizimi
- ✅ Payme integratsiyasi (tayyor)
- ✅ Click integratsiyasi (tayyor)
- ✅ Karta to'lovi
- ✅ To'lov tarixi va holati

### Sharh va reyting
- ✅ Texnikaga sharh qoldirish
- ✅ 1-5 yulduzli reyting tizimi
- ✅ Sharh moderatsiyasi

## 🛠 Texnologiyalar

### Backend
- **FastAPI** - Zamonaviy, tez va yuqori samarali web framework
- **Python 3.11+** - Dasturlash tili
- **SQLAlchemy 2.0** - ORM (Object-Relational Mapping)
- **Pydantic 2.0** - Data validation
- **Alembic** - Database migration tool

### Database
- **PostgreSQL 15** - Relational database
- **Redis** - Caching va session management (optional)

### Autentifikatsiya
- **JWT** - JSON Web Tokens
- **python-jose** - JWT implementation
- **passlib** - Password hashing

### Deployment
- **Apache** - Web server va reverse proxy
- **Uvicorn** - ASGI server
- **Systemd** - Service management

## 📦 Tizim talablari

### Development
- Python 3.11 yoki yuqori
- PostgreSQL 15 yoki yuqori
- 2GB RAM (minimal)
- 10GB disk space

### Production
- Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- Python 3.11+
- PostgreSQL 15+
- Apache 2.4+
- 4GB RAM (tavsiya etiladi)
- 50GB disk space (SSD tavsiya etiladi)

## 🚀 O'rnatish

### 1. Repositoriyani klonlash

```bash
git clone https://github.com/your-username/movex_go.git
cd movex_go
```

### 2. Virtual environment yaratish

```bash
python3.11 -m venv venv
source venv/bin/activate  # Linux/Mac
# yoki
venv\Scripts\activate  # Windows
```

### 3. Dependencies o'rnatish

```bash
pip install -r requirements.txt
```

### 4. Environment o'zgaruvchilarini sozlash

```bash
cp .env.example .env
nano .env  # yoki boshqa text editor
```

**Minimal sozlamalar:**

```env
DATABASE_URL=postgresql://postgres:password@localhost:5432/movex_go
SECRET_KEY=your-secret-key-here  # openssl rand -hex 32
```

### 5. Database yaratish

```bash
# PostgreSQL ga kirish
psql -U postgres

# Database yaratish
CREATE DATABASE movex_go;
\q
```

### 6. Database migratsiyalarini bajarish

```bash
# Migratsiyalarni bajarish
alembic upgrade head
```

## 🎯 Ishga tushirish

### Development rejimida

```bash
# Virtual environment ni faollashtirish
source venv/bin/activate

# Serverni ishga tushirish
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# yoki Makefile orqali
make run
```

Server `http://localhost:8000` da ishga tushadi.

### Production rejimida

Production deployment uchun [DEPLOY.md](../docs/backend/DEPLOY.md) faylini ko'ring. Qisqacha:

1. PostgreSQL o'rnatish va database yaratish
2. Python 3.11 va virtual environment sozlash
3. Dependencies o'rnatish
4. Environment o'zgaruvchilarini sozlash
5. Database migration bajarish
6. Systemd service yaratish
7. Apache o'rnatish va sozlash
8. SSL sertifikat olish (Let's Encrypt)

## 📚 API dokumentatsiya

Server ishga tushgandan keyin quyidagi manzillarda API dokumentatsiyasini ko'rishingiz mumkin:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Asosiy endpointlar

#### Autentifikatsiya
- `POST /auth/register` - Ro'yxatdan o'tish
- `POST /auth/login` - Tizimga kirish
- `GET /auth/me` - Joriy foydalanuvchi ma'lumotlari

#### Foydalanuvchilar
- `GET /users` - Barcha foydalanuvchilar
- `GET /users/{id}` - Foydalanuvchi ma'lumotlari
- `PUT /users/{id}` - Foydalanuvchini yangilash
- `DELETE /users/{id}` - Foydalanuvchini o'chirish

#### Texnika
- `GET /equipment` - Barcha texnikalar
- `POST /equipment` - Yangi texnika qo'shish
- `GET /equipment/{id}` - Texnika ma'lumotlari
- `PUT /equipment/{id}` - Texnikani yangilash
- `DELETE /equipment/{id}` - Texnikani o'chirish

#### Buyurtmalar
- `GET /orders` - Barcha buyurtmalar
- `POST /orders` - Yangi buyurtma yaratish
- `GET /orders/{id}` - Buyurtma ma'lumotlari
- `PUT /orders/{id}` - Buyurtmani yangilash

#### Chat va xabarlar
- `GET /chats` - Barcha chatlar
- `POST /chats` - Yangi chat yaratish
- `GET /messages/{chat_id}` - Chat xabarlari
- `POST /messages` - Xabar yuborish

#### Sharhlar
- `GET /reviews` - Barcha sharhlar
- `POST /reviews` - Sharh qoldirish
- `GET /reviews/equipment/{equipment_id}` - Texnika sharhlari

#### To'lovlar
- `GET /payments` - Barcha to'lovlar
- `POST /payments` - To'lov yaratish
- `GET /payments/{id}` - To'lov ma'lumotlari

## 📁 Loyiha strukturasi

```
movex_go/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI application
│   ├── core/
│   │   ├── __init__.py
│   │   ├── config.py          # Configuration settings
│   │   └── security.py        # Security utilities
│   ├── db/
│   │   ├── __init__.py
│   │   ├── base.py            # Base class for models
│   │   └── session.py         # Database session
│   ├── models/
│   │   ├── __init__.py
│   │   ├── user.py            # User model
│   │   ├── company.py         # Company model
│   │   ├── equipment.py       # Equipment model
│   │   ├── order.py           # Order model
│   │   ├── chat.py            # Chat model
│   │   ├── message.py         # Message model
│   │   ├── review.py          # Review model
│   │   └── payment.py         # Payment model
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── auth.py            # Auth endpoints
│   │   ├── users.py           # User endpoints
│   │   ├── companies.py       # Company endpoints
│   │   ├── equipment.py       # Equipment endpoints
│   │   ├── orders.py          # Order endpoints
│   │   ├── chats.py           # Chat endpoints
│   │   ├── messages.py        # Message endpoints
│   │   ├── reviews.py         # Review endpoints
│   │   └── payments.py        # Payment endpoints
│   └── schemas/
│       ├── __init__.py
│       ├── user.py            # User schemas
│       ├── company.py         # Company schemas
│       ├── equipment.py       # Equipment schemas
│       ├── order.py           # Order schemas
│       ├── chat.py            # Chat schemas
│       ├── message.py         # Message schemas
│       ├── review.py          # Review schemas
│       └── payment.py         # Payment schemas
├── alembic/                   # Database migrations
│   ├── versions/
│   └── env.py
├── apache/                    # Apache configuration
│   └── conf.d/
│       └── movex_go.conf
├── migrations/                # SQL scripts
│   └── add_indexes.sql
├── scripts/                   # Utility scripts
│   └── backup.sh
├── tests/                     # Tests
├── .env.example              # Environment variables example
├── .gitignore
├── alembic.ini               # Alembic configuration
├── Makefile                  # Useful commands
├── requirements.txt          # Python dependencies
├── DEPLOY.md                 # Deployment guide
└── README.md                 # This file
```

## 🗄 Database sxemasi

Loyihada quyidagi jadvallar mavjud:

- **users** - Foydalanuvchilar
- **companies** - Kompaniyalar
- **equipment** - Texnikalar
- **equipment_photos** - Texnika rasmlari
- **orders** - Buyurtmalar
- **chats** - Chatlar
- **messages** - Xabarlar
- **reviews** - Sharhlar
- **payments** - To'lovlar

To'liq database sxemasi `database.txt` faylida mavjud.

## 🧪 Testing

```bash
# Testlarni ishga tushirish
pytest

# Coverage bilan
pytest --cov=app tests/

# Specific test
pytest tests/test_auth.py
```

## 🚀 Deployment

### ⚡ Tez Deploy (5 daqiqa) - Tavsiya etiladi!

**Subdomen uchun oddiy deploy:** `movex.004.uz`

```bash
# 1. Loyihani serverga ko'chiring
scp -r /path/to/project user@server:/var/www/movex.004.uz/

# 2. Serverga kiring va scriptni ishga tushiring
ssh user@server
cd /var/www/movex.004.uz
sudo bash scripts/quick_deploy.sh
```

**Tayyor!** 🎉

📖 **Deploy qo'llanmalari:**
- **[QUICK_START.md](../docs/backend/QUICK_START.md)** - 5 daqiqada deploy (oddiy usul) ⚡
- **[SIMPLE_DEPLOY.md](../docs/backend/SIMPLE_DEPLOY.md)** - Subdomen uchun to'liq qo'llanma 📘
- **[DEPLOY.md](../docs/backend/DEPLOY.md)** - Murakkab production deploy 🏢

### Qisqacha qo'lda deploy

```bash
# 1. Serverni tayyorlash
sudo apt update && sudo apt install -y python3.11 python3.11-venv postgresql apache2

# 2. Loyihani joylashtirish
sudo mkdir -p /var/www/movex.004.uz
cd /var/www/movex.004.uz
# Loyihani ko'chiring yoki git clone qiling

# 3. Python sozlash
sudo -u www-data python3.11 -m venv venv
sudo -u www-data venv/bin/pip install -r requirements.txt

# 4. Database yaratish
sudo -u postgres psql -c "CREATE DATABASE movex_go;"
sudo -u postgres psql -c "CREATE USER movex_user WITH PASSWORD 'password';"

# 5. Environment va migration
cp .env.example .env && nano .env
sudo -u www-data venv/bin/alembic upgrade head

# 6. Apache va Service
sudo cp apache/subdomain/movex.004.uz.conf /etc/apache2/sites-available/
sudo a2ensite movex.004.uz.conf
sudo cp systemd/movex-api.service /etc/systemd/system/
sudo systemctl start movex-api && sudo systemctl enable movex-api

# 7. SSL
sudo certbot --apache -d movex.004.uz
```

## 🤝 Hissa qo'shish

Loyihaga hissa qo'shmoqchimisiz? Ajoyib!

1. Fork qiling
2. Feature branch yarating (`git checkout -b feature/AmazingFeature`)
3. O'zgarishlarni commit qiling (`git commit -m 'Add some AmazingFeature'`)
4. Branch ga push qiling (`git push origin feature/AmazingFeature`)
5. Pull Request oching

## 📝 Litsenziya

Bu loyiha MIT litsenziyasi ostida tarqatiladi.

## 👥 Muallif

- **Shohruxbek** - Initial work

## 📞 Aloqa

- Email: support@movexgo.com
- Website: https://movexgo.com
- GitHub: https://github.com/your-username/movex_go

---

**Movex GO** - Qurilish texnikasi ijarasi oson va qulay! 🚜
# movex_go_backend
