# 🚀 Movex.004.uz - Systemd bilan Deploy
# Papka: /www/wwwroot/movex.004.uz

Bu qo'llanmada har bir buyruq tushuntirilgan. Faqat copy-paste qiling!

---

## ✅ Boshlashdan oldin tekshirish

SSH orqali serverga kiring va quyidagilarni tekshiring:

```bash
# 1. Papka mavjudmi?
ls -la /www/wwwroot/movex.004.uz

# 2. Python o'rnatilganmi?
python3.11 --version

# 3. PostgreSQL ishlayaptimi?
sudo systemctl status postgresql
```

Agar hammasi OK bo'lsa, davom eting! ⬇️

---

## 📦 1-QADAM: Kerakli paketlarni o'rnatish (1 daqiqa)

```bash
# Paketlarni yangilash
sudo apt update

# Kerakli paketlarni o'rnatish
sudo apt install -y python3.11 python3.11-venv postgresql apache2 certbot python3-certbot-apache

# Apache modullarini yoqish
sudo a2enmod proxy proxy_http headers ssl rewrite

# Apache ni qayta ishga tushirish
sudo systemctl restart apache2
```

**Nima bo'ldi?** Python, PostgreSQL, Apache va SSL uchun kerakli paketlar o'rnatildi.

---

## 🐍 2-QADAM: Python muhitini sozlash (2 daqiqa)

```bash
# Loyiha papkasiga o'tish
cd /www/wwwroot/movex.004.uz

# Virtual environment yaratish (agar yo'q bo'lsa)
python3.11 -m venv venv

# Virtual environment ni faollashtirish
source venv/bin/activate

# Dependencies o'rnatish
pip install --upgrade pip
pip install -r requirements.txt

# Deactivate qilish
deactivate
```

**Nima bo'ldi?** Python virtual environment yaratildi va barcha kerakli kutubxonalar o'rnatildi.

---

## 🗄️ 3-QADAM: Database yaratish (1 daqiqa)

```bash
# PostgreSQL ga kirish
sudo -u postgres psql
```

PostgreSQL ichida quyidagi buyruqlarni bajaring:

```sql
-- Database yaratish
CREATE DATABASE movex_go;

-- User yaratish (parolni o'zgartiring!)
CREATE USER movex_user WITH PASSWORD 'your_strong_password_here';

-- Ruxsatlar berish
GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;

-- Chiqish
\q
```

**Nima bo'ldi?** `movex_go` database va `movex_user` user yaratildi.

---

## ⚙️ 4-QADAM: Environment sozlash (1 daqiqa)

```bash
# .env fayl yaratish
nano /www/wwwroot/movex.004.uz/.env
```

Quyidagi mazmunni kiriting (parol va secret key ni o'zgartiring!):

```env
# Database
DATABASE_URL=postgresql://movex_user:your_strong_password_here@localhost:5432/movex_go

# JWT (secret key ni generatsiya qiling!)
SECRET_KEY=your_secret_key_here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Application
APP_ENV=production
DEBUG=false

# CORS
CORS_ORIGINS=https://004.uz,https://www.004.uz,https://movex.004.uz
```

**Secret key generatsiya qilish:**
```bash
openssl rand -hex 32
```

Natijani `SECRET_KEY=` ga qo'ying.

**Saqlash:** `Ctrl+O`, `Enter`, `Ctrl+X`

**Nima bo'ldi?** Environment o'zgaruvchilari sozlandi.

---

## 🔄 5-QADAM: Database migration (30 soniya)

```bash
cd /www/wwwroot/movex.004.uz
source venv/bin/activate
alembic upgrade head
deactivate
```

**Nima bo'ldi?** Database jadvallar yaratildi.

---

## 🌐 6-QADAM: Apache konfiguratsiyasi (1 daqiqa)

```bash
# Config fayl yaratish
sudo nano /etc/apache2/sites-available/movex.004.uz.conf
```

Quyidagi mazmunni kiriting:

```apache
<VirtualHost *:80>
    ServerName movex.004.uz
    ServerAdmin admin@004.uz

    # Logging
    ErrorLog ${APACHE_LOG_DIR}/movex_error.log
    CustomLog ${APACHE_LOG_DIR}/movex_access.log combined

    # Proxy sozlamalari
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    # Timeout
    ProxyTimeout 300
    TimeOut 300

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"

    # Upload limit (20MB)
    LimitRequestBody 20971520

    # Media files
    Alias /media /www/wwwroot/movex.004.uz/media
    <Directory /www/wwwroot/movex.004.uz/media>
        Require all granted
        Options -Indexes
    </Directory>
</VirtualHost>
```

**Saqlash:** `Ctrl+O`, `Enter`, `Ctrl+X`

```bash
# Site ni faollashtirish
sudo a2ensite movex.004.uz.conf

# Config test
sudo apache2ctl configtest

# Apache ni qayta yuklash
sudo systemctl reload apache2
```

**Nima bo'ldi?** Apache subdomen uchun sozlandi.

---

## ⚙️ 7-QADAM: Systemd service yaratish (1 daqiqa)

```bash
# Service fayl yaratish
sudo nano /etc/systemd/system/movex-api.service
```

Quyidagi mazmunni kiriting:

```ini
[Unit]
Description=Movex GO API Service (movex.004.uz)
After=network.target postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/www/wwwroot/movex.004.uz
Environment="PATH=/www/wwwroot/movex.004.uz/venv/bin"
EnvironmentFile=/www/wwwroot/movex.004.uz/.env

# Uvicorn bilan ishga tushirish
ExecStart=/www/wwwroot/movex.004.uz/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 4

# Restart sozlamalari
Restart=always
RestartSec=10

# Security
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movex-api

[Install]
WantedBy=multi-user.target
```

**Saqlash:** `Ctrl+O`, `Enter`, `Ctrl+X`

**Nima bo'ldi?** Systemd service fayli yaratildi.

---

## 🚀 8-QADAM: Service ni ishga tushirish (30 soniya)

```bash
# Ruxsatlarni sozlash
sudo chown -R www-data:www-data /www/wwwroot/movex.004.uz
sudo chmod 600 /www/wwwroot/movex.004.uz/.env

# Systemd ni qayta yuklash
sudo systemctl daemon-reload

# Service ni ishga tushirish
sudo systemctl start movex-api

# Avtomatik ishga tushirish (server restart bo'lganda)
sudo systemctl enable movex-api

# Holat tekshirish
sudo systemctl status movex-api
```

**Nima bo'ldi?** Service ishga tushdi va avtomatik ishga tushirish sozlandi.

---

## 🔒 9-QADAM: SSL sertifikat (1 daqiqa)

```bash
# SSL sertifikat olish (avtomatik)
sudo certbot --apache -d movex.004.uz
```

Email so'ralsa, kiriting va `Y` bosing.

**Nima bo'ldi?** HTTPS sozlandi (https://movex.004.uz).

---

## ✅ 10-QADAM: Tekshirish

```bash
# 1. Service ishlayaptimi?
sudo systemctl status movex-api

# 2. Loglarni ko'rish
sudo journalctl -u movex-api -n 50

# 3. Apache loglar
sudo tail -f /var/log/apache2/movex_error.log

# 4. API test (yangi terminal ochib)
curl http://movex.004.uz/health
curl http://movex.004.uz/docs
```

**Brauzerda ochish:**
- API Docs: `https://movex.004.uz/docs`
- Health: `https://movex.004.uz/health`

---

## 🎉 TAYYOR!

Agar hammasi ishlasa, sizning API ishga tushdi! 🚀

---

## 🛠️ Foydali buyruqlar

### Service boshqarish
```bash
# Ishga tushirish
sudo systemctl start movex-api

# To'xtatish
sudo systemctl stop movex-api

# Qayta ishga tushirish
sudo systemctl restart movex-api

# Holat
sudo systemctl status movex-api
```

### Loglarni ko'rish
```bash
# Real-time loglar
sudo journalctl -u movex-api -f

# Oxirgi 100 ta log
sudo journalctl -u movex-api -n 100

# Bugungi loglar
sudo journalctl -u movex-api --since today
```

### Yangilash (update)
```bash
cd /www/wwwroot/movex.004.uz

# Git dan yangilash (agar git ishlatilsa)
git pull

# Dependencies yangilash
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Migration
source venv/bin/activate
alembic upgrade head
deactivate

# Service restart
sudo systemctl restart movex-api
```

---

## 🚨 Muammolarni hal qilish

### Service ishlamayapti

```bash
# Loglarni ko'rish
sudo journalctl -u movex-api -n 50 --no-pager

# Qo'lda test
cd /www/wwwroot/movex.004.uz
source venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### 502 Bad Gateway

Backend ishlamayapti:
```bash
sudo systemctl status movex-api
sudo systemctl restart movex-api
```

### Database xatolik

```bash
# PostgreSQL ishlayaptimi?
sudo systemctl status postgresql

# Database mavjudmi?
sudo -u postgres psql -l | grep movex_go

# Connection test
cd /www/wwwroot/movex.004.uz
source venv/bin/activate
python -c "from app.db.database import engine; print(engine.connect())"
```

### Port band

```bash
# 8000 portni tekshirish
sudo lsof -i :8000
sudo netstat -tulpn | grep 8000

# Agar kerak bo'lsa, process ni to'xtatish
sudo kill -9 <PID>
```

---

## 📞 Yordam

Agar biror qadam ishlamasa:

1. **Xatolik xabarini to'liq ko'rsating** (screenshot yoki copy-paste)
2. **Qaysi qadamda xatolik bo'ldi?**
3. **Loglarni yuboring:**
   ```bash
   sudo journalctl -u movex-api -n 100 --no-pager
   ```

Men sizga yordam beraman! 😊

