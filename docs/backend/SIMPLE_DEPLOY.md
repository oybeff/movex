# Movex GO - Oddiy Subdomen Deploy (movex.004.uz)

Bu qo'llanma **5-10 daqiqada** ishlaydigan oddiy deploy usuli.

---

## 📋 Kerakli ma'lumotlar

- **Subdomen**: `movex.004.uz`
- **Papka**: `/var/www/movex.004.uz/`
- **Port**: `8000` (ichki)
- **Database**: PostgreSQL

---

## 🚀 Tez Deploy (5 daqiqa)

### 1. Serverni tayyorlash

```bash
# Kerakli paketlarni o'rnatish
sudo apt update
sudo apt install -y python3.11 python3.11-venv postgresql apache2 git

# Apache modullarini yoqish
sudo a2enmod proxy proxy_http headers ssl rewrite
sudo systemctl restart apache2
```

### 2. Loyihani joylashtirish

```bash
# Papka yaratish
sudo mkdir -p /var/www/movex.004.uz
cd /var/www/movex.004.uz

# Loyihani ko'chirish (yoki git clone)
# Agar local dan ko'chirsangiz:
# sudo cp -r /path/to/your/project/* /var/www/movex.004.uz/

# Yoki git orqali:
sudo git clone https://github.com/your-username/movex_go_backend.git .

# Ruxsatlarni sozlash
sudo chown -R www-data:www-data /var/www/movex.004.uz
```

### 3. Python muhitini sozlash

```bash
cd /var/www/movex.004.uz

# Virtual environment yaratish
sudo -u www-data python3.11 -m venv venv

# Dependencies o'rnatish
sudo -u www-data venv/bin/pip install -r requirements.txt
```

### 4. Database yaratish

```bash
# PostgreSQL ga kirish
sudo -u postgres psql

# Database va user yaratish
CREATE DATABASE movex_go;
CREATE USER movex_user WITH PASSWORD 'your_strong_password';
GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;
\q
```

### 5. Environment sozlash

```bash
# .env fayl yaratish
sudo nano /var/www/movex.004.uz/.env
```

**`.env` fayl mazmuni:**

```env
# Database
DATABASE_URL=postgresql://movex_user:your_strong_password@localhost:5432/movex_go

# JWT
SECRET_KEY=your_secret_key_here_use_openssl_rand_hex_32
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Application
APP_ENV=production
DEBUG=false

# CORS (agar frontend boshqa domenda bo'lsa)
CORS_ORIGINS=https://004.uz,https://www.004.uz
```

**Secret key generatsiya:**
```bash
openssl rand -hex 32
```

### 6. Migration bajarish

```bash
cd /var/www/movex.004.uz
sudo -u www-data venv/bin/alembic upgrade head
```

### 7. Apache konfiguratsiyasi

```bash
# Config faylini yaratish
sudo nano /etc/apache2/sites-available/movex.004.uz.conf
```

**Fayl mazmuni (pastda ko'rsatilgan)** - `apache/subdomain/movex.004.uz.conf` faylidan nusxalang.

```bash
# Config ni faollashtirish
sudo a2ensite movex.004.uz.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### 8. Systemd service yaratish

```bash
# Service faylini yaratish
sudo nano /etc/systemd/system/movex-api.service
```

**Fayl mazmuni (pastda ko'rsatilgan)** - `systemd/movex-api.service` faylidan nusxalang.

```bash
# Service ni ishga tushirish
sudo systemctl daemon-reload
sudo systemctl start movex-api
sudo systemctl enable movex-api
sudo systemctl status movex-api
```

### 9. SSL sertifikat (Let's Encrypt)

```bash
# Certbot o'rnatish
sudo apt install -y certbot python3-certbot-apache

# SSL sertifikat olish (avtomatik)
sudo certbot --apache -d movex.004.uz

# Avtomatik yangilanish
sudo systemctl enable certbot.timer
```

---

## ✅ Tekshirish

```bash
# Service ishlayaptimi?
sudo systemctl status movex-api

# Loglarni ko'rish
sudo journalctl -u movex-api -f

# Apache loglar
sudo tail -f /var/log/apache2/movex_error.log

# Test qilish
curl http://movex.004.uz/health
curl https://movex.004.uz/docs
```

---

## 🔄 Yangilash (Update)

```bash
# 1. Yangi kodni olish
cd /var/www/movex.004.uz
sudo -u www-data git pull

# 2. Dependencies yangilash (agar kerak bo'lsa)
sudo -u www-data venv/bin/pip install -r requirements.txt

# 3. Migration (agar kerak bo'lsa)
sudo -u www-data venv/bin/alembic upgrade head

# 4. Service ni qayta ishga tushirish
sudo systemctl restart movex-api
```

---

## 🛠️ Muammolarni hal qilish

### Service ishlamayapti

```bash
# Loglarni ko'rish
sudo journalctl -u movex-api -n 50

# Qo'lda ishga tushirib ko'rish
cd /var/www/movex.004.uz
sudo -u www-data venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### Apache xatolik beradi

```bash
# Config test
sudo apache2ctl configtest

# Apache loglar
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/movex_error.log
```

### Database ulanmayapti

```bash
# PostgreSQL ishlayaptimi?
sudo systemctl status postgresql

# Database mavjudmi?
sudo -u postgres psql -l | grep movex_go

# Connection test
sudo -u www-data venv/bin/python -c "from app.db.database import engine; print(engine.connect())"
```

### Port band

```bash
# 8000 portni tekshirish
sudo lsof -i :8000
sudo netstat -tulpn | grep 8000

# Agar kerak bo'lsa, boshqa portga o'zgartiring
# .service faylida --port 8001 qiling
```

---

## 📊 Monitoring

### Service holati

```bash
# Status
sudo systemctl status movex-api

# Real-time loglar
sudo journalctl -u movex-api -f

# Bugungi loglar
sudo journalctl -u movex-api --since today
```

### Apache holati

```bash
# Apache status
sudo systemctl status apache2

# Active connections
sudo apache2ctl status

# Loglar
sudo tail -f /var/log/apache2/movex_access.log
```

---

## 🔐 Xavfsizlik

### Firewall sozlash

```bash
# UFW o'rnatish va sozlash
sudo apt install -y ufw

# Kerakli portlarni ochish
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS

# Firewall yoqish
sudo ufw enable
sudo ufw status
```

### Ruxsatlarni tekshirish

```bash
# Papka ruxsatlari
ls -la /var/www/movex.004.uz

# www-data user ega bo'lishi kerak
sudo chown -R www-data:www-data /var/www/movex.004.uz

# .env fayl faqat www-data o'qiy olishi kerak
sudo chmod 600 /var/www/movex.004.uz/.env
```

---

## 📦 Backup

### Oddiy backup script

```bash
# Backup papkasini yaratish
sudo mkdir -p /var/backups/movex

# Backup script
sudo nano /var/backups/movex/backup.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/movex"

# Database backup
sudo -u postgres pg_dump movex_go | gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Code backup (optional)
tar -czf $BACKUP_DIR/code_$DATE.tar.gz -C /var/www movex.004.uz

# Eski backuplarni o'chirish (30 kundan eski)
find $BACKUP_DIR -name "*.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
```

```bash
# Script ni executable qilish
sudo chmod +x /var/backups/movex/backup.sh

# Cron job (har kuni soat 2:00 da)
sudo crontab -e
# Qo'shish: 0 2 * * * /var/backups/movex/backup.sh
```

---

## 🎯 Qisqacha xulosa

1. ✅ Serverni tayyorlash (apt install)
2. ✅ Loyihani `/var/www/movex.004.uz/` ga joylashtirish
3. ✅ Python venv va dependencies
4. ✅ PostgreSQL database yaratish
5. ✅ `.env` fayl sozlash
6. ✅ Migration bajarish
7. ✅ Apache config (`movex.004.uz.conf`)
8. ✅ Systemd service (`movex-api.service`)
9. ✅ SSL sertifikat (certbot)
10. ✅ Test va monitoring

**Jami vaqt: 5-10 daqiqa** ⚡

---

## 📞 Yordam

Agar muammo bo'lsa:
1. Service loglarini tekshiring: `sudo journalctl -u movex-api -f`
2. Apache loglarini tekshiring: `sudo tail -f /var/log/apache2/movex_error.log`
3. Config testdan o'tkazing: `sudo apache2ctl configtest`
4. Port bandligini tekshiring: `sudo lsof -i :8000`

