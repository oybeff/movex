# 🚀 Movex GO - Tez Boshlash (5 daqiqa)

Bu qo'llanma **movex.004.uz** subdomen uchun eng oddiy va tez deploy usuli.

---

## ⚡ Bir buyruq bilan deploy

```bash
# 1. Loyihani serverga ko'chiring
scp -r /path/to/project user@server:/var/www/movex.004.uz/

# 2. Serverga kiring
ssh user@server

# 3. Deploy scriptni ishga tushiring
cd /var/www/movex.004.uz
sudo bash scripts/quick_deploy.sh
```

**Tayyor!** 🎉

---

## 📋 Qo'lda deploy (agar script ishlamasa)

### 1. Serverni tayyorlash (1 daqiqa)

```bash
sudo apt update
sudo apt install -y python3.11 python3.11-venv postgresql apache2 git
sudo a2enmod proxy proxy_http headers ssl rewrite
sudo systemctl restart apache2
```

### 2. Loyihani joylashtirish (1 daqiqa)

```bash
# Papka yaratish
sudo mkdir -p /var/www/movex.004.uz
cd /var/www/movex.004.uz

# Loyihani ko'chirish (yoki git clone)
# sudo cp -r /path/to/project/* .

# Ruxsatlar
sudo chown -R www-data:www-data /var/www/movex.004.uz
```

### 3. Python sozlash (1 daqiqa)

```bash
cd /var/www/movex.004.uz
sudo -u www-data python3.11 -m venv venv
sudo -u www-data venv/bin/pip install -r requirements.txt
```

### 4. Database yaratish (1 daqiqa)

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE movex_go;
CREATE USER movex_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;
\q
```

### 5. Environment sozlash (30 soniya)

```bash
sudo nano /var/www/movex.004.uz/.env
```

**Minimal .env:**

```env
DATABASE_URL=postgresql://movex_user:your_password@localhost:5432/movex_go
SECRET_KEY=your_secret_key_here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
APP_ENV=production
DEBUG=false
CORS_ORIGINS=https://004.uz,https://www.004.uz
```

**Secret key generatsiya:**
```bash
openssl rand -hex 32
```

### 6. Migration (30 soniya)

```bash
cd /var/www/movex.004.uz
sudo -u www-data venv/bin/alembic upgrade head
```

### 7. Apache sozlash (30 soniya)

```bash
# Config nusxalash
sudo cp apache/subdomain/movex.004.uz.conf /etc/apache2/sites-available/

# Faollashtirish
sudo a2ensite movex.004.uz.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### 8. Service ishga tushirish (30 soniya)

```bash
# Service nusxalash
sudo cp systemd/movex-api.service /etc/systemd/system/

# Ishga tushirish
sudo systemctl daemon-reload
sudo systemctl start movex-api
sudo systemctl enable movex-api
sudo systemctl status movex-api
```

### 9. SSL sertifikat (1 daqiqa)

```bash
sudo apt install -y certbot python3-certbot-apache
sudo certbot --apache -d movex.004.uz
```

---

## ✅ Tekshirish

```bash
# Service ishlayaptimi?
sudo systemctl status movex-api

# API test
curl http://movex.004.uz/health
curl http://movex.004.uz/docs

# Loglar
sudo journalctl -u movex-api -f
sudo tail -f /var/log/apache2/movex_error.log
```

---

## 🔄 Yangilash (Update)

```bash
cd /var/www/movex.004.uz
sudo -u www-data git pull
sudo -u www-data venv/bin/pip install -r requirements.txt
sudo -u www-data venv/bin/alembic upgrade head
sudo systemctl restart movex-api
```

---

## 🛠️ Muammolarni hal qilish

### Service ishlamayapti

```bash
# Loglarni ko'rish
sudo journalctl -u movex-api -n 50

# Qo'lda test
cd /var/www/movex.004.uz
sudo -u www-data venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### Apache xatolik

```bash
sudo apache2ctl configtest
sudo tail -f /var/log/apache2/error.log
```

### Database xatolik

```bash
sudo systemctl status postgresql
sudo -u postgres psql -l | grep movex_go
```

### Port band

```bash
sudo lsof -i :8000
sudo netstat -tulpn | grep 8000
```

---

## 📊 Foydali buyruqlar

```bash
# Service boshqarish
sudo systemctl start movex-api
sudo systemctl stop movex-api
sudo systemctl restart movex-api
sudo systemctl status movex-api

# Loglar
sudo journalctl -u movex-api -f
sudo journalctl -u movex-api --since today
sudo tail -f /var/log/apache2/movex_error.log

# Apache
sudo systemctl restart apache2
sudo apache2ctl configtest
sudo a2ensite movex.004.uz.conf
sudo a2dissite movex.004.uz.conf

# Database backup
sudo -u postgres pg_dump movex_go > backup.sql
```

---

## 🔐 Xavfsizlik

```bash
# Firewall
sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Ruxsatlar
sudo chown -R www-data:www-data /var/www/movex.004.uz
sudo chmod 600 /var/www/movex.004.uz/.env
```

---

## 📦 Backup

```bash
# Database backup
sudo -u postgres pg_dump movex_go | gzip > backup_$(date +%Y%m%d).sql.gz

# Code backup
tar -czf backup_$(date +%Y%m%d).tar.gz -C /var/www movex.004.uz
```

---

## 🎯 Xulosa

1. ✅ Server tayyorlash
2. ✅ Loyihani joylashtirish
3. ✅ Python va dependencies
4. ✅ Database yaratish
5. ✅ .env sozlash
6. ✅ Migration
7. ✅ Apache config
8. ✅ Systemd service
9. ✅ SSL sertifikat

**Jami: 5-10 daqiqa** ⚡

---

## 📞 Yordam kerakmi?

**Loglarni tekshiring:**
```bash
sudo journalctl -u movex-api -f
sudo tail -f /var/log/apache2/movex_error.log
```

**Config test:**
```bash
sudo apache2ctl configtest
```

**Service restart:**
```bash
sudo systemctl restart movex-api
sudo systemctl restart apache2
```

---

## 📚 Batafsil ma'lumot

- To'liq deploy qo'llanmasi: [SIMPLE_DEPLOY.md](SIMPLE_DEPLOY.md)
- Murakkab deploy: [DEPLOY.md](DEPLOY.md)
- API dokumentatsiya: `http://movex.004.uz/docs`

