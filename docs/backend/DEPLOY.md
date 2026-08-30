# Movex GO - Deployment Guide

Bu qo'llanma Movex GO backend ilovasini production serverga deploy qilish bo'yicha to'liq ko'rsatmalarni o'z ichiga oladi.

## Mundarija

1. [Tizim talablari](#tizim-talablari)
2. [Serverga tayyorgarlik](#serverga-tayyorgarlik)
3. [PostgreSQL o'rnatish va sozlash](#postgresql-ornatish-va-sozlash)
4. [Python va loyihani sozlash](#python-va-loyihani-sozlash)
5. [Apache o'rnatish va sozlash](#apache-ornatish-va-sozlash)
6. [SSL sertifikat sozlash](#ssl-sertifikat-sozlash)
7. [Systemd service yaratish](#systemd-service-yaratish)
8. [Database migration](#database-migration)
9. [Monitoring va logging](#monitoring-va-logging)
10. [Backup va restore](#backup-va-restore)
11. [Troubleshooting](#troubleshooting)

---

## Tizim talablari

### Minimal talablar:
- **OS**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- **RAM**: 2GB (4GB tavsiya etiladi)
- **CPU**: 2 core (4 core tavsiya etiladi)
- **Disk**: 20GB (SSD tavsiya etiladi)
- **Python**: 3.11+
- **PostgreSQL**: 15+
- **Apache**: 2.4+

### Tavsiya etiladigan talablar (production):
- **RAM**: 8GB+
- **CPU**: 4+ cores
- **Disk**: 100GB+ SSD
- **Backup storage**: 50GB+

---

## Serverga tayyorgarlik

### 1. Serverni yangilash

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL
sudo yum update -y
```

### 2. Kerakli paketlarni o'rnatish

```bash
# Ubuntu/Debian
sudo apt install -y git curl wget vim build-essential python3-dev libpq-dev

# CentOS/RHEL
sudo yum install -y git curl wget vim gcc make python3-devel postgresql-devel
```

### 3. Firewall sozlash

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable

# Firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

---

## PostgreSQL o'rnatish va sozlash

### 1. PostgreSQL o'rnatish

```bash
# Ubuntu/Debian
sudo apt install -y postgresql postgresql-contrib

# CentOS/RHEL
sudo yum install -y postgresql-server postgresql-contrib
sudo postgresql-setup initdb
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### 2. PostgreSQL ni sozlash

PostgreSQL ni tashqaridan kirish uchun sozlash (agar kerak bo'lsa):

```bash
# pg_hba.conf faylini tahrirlash
sudo nano /etc/postgresql/15/main/pg_hba.conf

# Quyidagi qatorni qo'shing (local connections uchun):
# local   all             all                                     md5
# host    all             all             127.0.0.1/32            md5

# PostgreSQL ni qayta ishga tushirish
sudo systemctl restart postgresql
```

### 3. Database va foydalanuvchi yaratish

```bash
sudo -u postgres psql

# PostgreSQL shell ichida
CREATE DATABASE movex_go;
CREATE USER movex_user WITH PASSWORD 'strong_password_here';
GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;

# PostgreSQL 15+ uchun qo'shimcha ruxsatlar
\c movex_go
GRANT ALL ON SCHEMA public TO movex_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO movex_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO movex_user;

\q
```

### 4. Database ulanishini tekshirish

```bash
psql -U movex_user -d movex_go -h localhost
# Parolni kiriting va ulanishni tekshiring
\q
```

---

## Python va loyihani sozlash

### 1. Loyihani klonlash

```bash
cd /opt
sudo git clone https://github.com/your-username/movex_go.git
cd movex_go
sudo chown -R $USER:$USER .
```

### 2. Python 3.11 o'rnatish

```bash
# Ubuntu 22.04+
sudo apt install -y python3.11 python3.11-venv python3.11-dev

# Ubuntu 20.04 (deadsnakes PPA orqali)
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-dev

# CentOS/RHEL
sudo yum install -y python3.11 python3.11-devel
```

### 3. Virtual environment yaratish

```bash
cd /opt/movex_go
python3.11 -m venv venv
source venv/bin/activate
```

### 4. Dependencies o'rnatish

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### 5. Environment o'zgaruvchilarini sozlash

```bash
cp .env.example .env
nano .env
```

**Muhim sozlamalar:**

```env
# Database
DATABASE_URL=postgresql://movex_user:strong_password_here@localhost:5432/movex_go

# JWT
SECRET_KEY=GENERATE_STRONG_SECRET_KEY_HERE  # openssl rand -hex 32
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Application
APP_ENV=production
DEBUG=false
ALLOWED_HOSTS=your-domain.com,www.your-domain.com

# CORS
CORS_ORIGINS=https://your-frontend-domain.com,https://www.your-frontend-domain.com
```

**Secret key generatsiya qilish:**

```bash
openssl rand -hex 32
```

### 6. Static va uploads papkalarini yaratish

```bash
mkdir -p /opt/movex_go/static
mkdir -p /opt/movex_go/uploads
chmod 755 /opt/movex_go/static
chmod 755 /opt/movex_go/uploads
```

---

## Apache o'rnatish va sozlash

### 1. Apache va kerakli modullarni o'rnatish

```bash
# Ubuntu/Debian
sudo apt install -y apache2 libapache2-mod-proxy-html libxml2-dev

# CentOS/RHEL
sudo yum install -y httpd mod_ssl
```

### 2. Kerakli Apache modullarini yoqish

```bash
# Ubuntu/Debian
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod ssl
sudo a2enmod rewrite
sudo a2enmod deflate
sudo a2enmod expires

# CentOS/RHEL (modullar default yoqilgan)
# Faqat tekshirish
httpd -M | grep proxy
```

### 3. Apache konfiguratsiyasini yaratish

```bash
# Ubuntu/Debian
sudo nano /etc/apache2/sites-available/movex_go.conf

# CentOS/RHEL
sudo nano /etc/httpd/conf.d/movex_go.conf
```

**Konfiguratsiya faylini nusxalash:**

```bash
# Loyiha papkasidan konfiguratsiyani nusxalash
sudo cp /opt/movex_go/apache/conf.d/movex_go.conf /etc/apache2/sites-available/movex_go.conf

# Domain nomini o'zgartirish
sudo nano /etc/apache2/sites-available/movex_go.conf
# your-domain.com ni o'z domeningizga o'zgartiring
```

### 4. Apache konfiguratsiyasini faollashtirish

```bash
# Ubuntu/Debian
sudo a2ensite movex_go.conf
sudo apache2ctl configtest
sudo systemctl restart apache2

# CentOS/RHEL
sudo apachectl configtest
sudo systemctl restart httpd
sudo systemctl enable httpd
```

### 5. Apache loglarini ko'rish

```bash
# Ubuntu/Debian
sudo tail -f /var/log/apache2/movex_go_error.log
sudo tail -f /var/log/apache2/movex_go_access.log

# CentOS/RHEL
sudo tail -f /var/log/httpd/movex_go_error.log
sudo tail -f /var/log/httpd/movex_go_access.log
```

---

## Systemd service yaratish

### 1. Service faylini yaratish

```bash
sudo nano /etc/systemd/system/movex_go.service
```

**Service fayli:**

```ini
[Unit]
Description=Movex GO FastAPI Application
After=network.target postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/movex_go
Environment="PATH=/opt/movex_go/venv/bin"
EnvironmentFile=/opt/movex_go/.env
ExecStart=/opt/movex_go/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 4
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/movex_go/uploads /opt/movex_go/logs

[Install]
WantedBy=multi-user.target
```

### 2. Service ni ishga tushirish

```bash
# Service faylini qayta yuklash
sudo systemctl daemon-reload

# Service ni ishga tushirish
sudo systemctl start movex_go

# Service ni avtomatik ishga tushirish
sudo systemctl enable movex_go

# Service holatini tekshirish
sudo systemctl status movex_go
```

### 3. Service loglarini ko'rish

```bash
# Real-time loglar
sudo journalctl -u movex_go -f

# Oxirgi 100 ta log
sudo journalctl -u movex_go -n 100 --no-pager

# Bugungi loglar
sudo journalctl -u movex_go --since today
```

### 4. Service ni boshqarish

```bash
# Service ni to'xtatish
sudo systemctl stop movex_go

# Service ni qayta ishga tushirish
sudo systemctl restart movex_go

# Service ni qayta yuklash (downtime siz)
sudo systemctl reload movex_go
```

---

## SSL sertifikat sozlash

### Let's Encrypt bilan (tavsiya etiladi)

#### 1. Certbot o'rnatish

```bash
# Ubuntu/Debian
sudo apt install -y certbot python3-certbot-apache

# CentOS/RHEL
sudo yum install -y certbot python3-certbot-apache
```

#### 2. SSL sertifikat olish

```bash
# Apache uchun avtomatik sozlash
sudo certbot --apache -d your-domain.com -d www.your-domain.com

# Yoki faqat sertifikat olish (manual sozlash uchun)
sudo certbot certonly --apache -d your-domain.com -d www.your-domain.com
```

#### 3. Avtomatik yangilanishni sozlash

```bash
# Avtomatik yangilanishni tekshirish
sudo certbot renew --dry-run

# Cron job qo'shish (agar avtomatik qo'shilmagan bo'lsa)
sudo crontab -e

# Quyidagi qatorni qo'shing:
0 0,12 * * * certbot renew --quiet --post-hook "systemctl reload apache2"
```

#### 4. SSL konfiguratsiyasini tekshirish

```bash
# Apache konfiguratsiyasini tekshirish
sudo apache2ctl configtest

# Apache ni qayta ishga tushirish
sudo systemctl restart apache2

# SSL sertifikatni tekshirish
sudo certbot certificates
```

### Manual SSL sertifikat (agar boshqa provider ishlatilsa)

Agar Let's Encrypt o'rniga boshqa SSL provider (Comodo, DigiCert, va h.k.) ishlatilsa:

```bash
# Sertifikat fayllarini joylashtirish
sudo mkdir -p /etc/ssl/movex_go
sudo cp your-certificate.crt /etc/ssl/movex_go/
sudo cp your-private-key.key /etc/ssl/movex_go/
sudo cp ca-bundle.crt /etc/ssl/movex_go/

# Ruxsatlarni sozlash
sudo chmod 600 /etc/ssl/movex_go/your-private-key.key
sudo chmod 644 /etc/ssl/movex_go/your-certificate.crt

# Apache konfiguratsiyasida SSL qismini uncomment qiling va yo'llarni to'g'rilang
sudo nano /etc/apache2/sites-available/movex_go.conf
```

---

## Database migration

### 1. Dastlabki migratsiyani yaratish

```bash
cd /opt/movex_go
source venv/bin/activate

# Dastlabki migratsiya yaratish
alembic revision --autogenerate -m "Initial migration"

# Migratsiyani bajarish
alembic upgrade head
```

### 2. Yangi migration yaratish

```bash
# Migration yaratish
alembic revision --autogenerate -m "migration message"

# Yaratilgan migratsiyani ko'rish
ls -la alembic/versions/

# Migration faylini tahrirlash (agar kerak bo'lsa)
nano alembic/versions/XXXX_migration_message.py
```

### 3. Migratsiyalarni bajarish

```bash
# Barcha migratsiyalarni bajarish
alembic upgrade head

# Ma'lum bir migratsiyagacha bajarish
alembic upgrade <revision_id>

# Bir qadam oldinga
alembic upgrade +1
```

### 4. Migratsiyani bekor qilish

```bash
# Bir qadam orqaga
alembic downgrade -1

# Ma'lum bir migratsiyagacha orqaga
alembic downgrade <revision_id>

# Barcha migratsiyalarni bekor qilish
alembic downgrade base
```

### 5. Migration tarixini ko'rish

```bash
# Joriy migration holatini ko'rish
alembic current

# Migration tarixini ko'rish
alembic history

# Migration tarixini batafsil ko'rish
alembic history --verbose
```

---

## Monitoring va logging

### 1. Application loglarini sozlash

```bash
# Logs papkasini yaratish
mkdir -p /opt/movex_go/logs
chown www-data:www-data /opt/movex_go/logs
chmod 755 /opt/movex_go/logs
```

### 2. Loglarni ko'rish

```bash
# Application logs (systemd orqali)
sudo journalctl -u movex_go -f

# Oxirgi 100 ta log
sudo journalctl -u movex_go -n 100 --no-pager

# Bugungi loglar
sudo journalctl -u movex_go --since today

# Apache access logs
sudo tail -f /var/log/apache2/movex_go_access.log

# Apache error logs
sudo tail -f /var/log/apache2/movex_go_error.log

# PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-15-main.log
```

### 3. Log rotation sozlash

Application logs uchun:

```bash
sudo nano /etc/logrotate.d/movex_go
```

```
/opt/movex_go/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data www-data
    sharedscripts
    postrotate
        systemctl reload movex_go > /dev/null 2>&1 || true
    endscript
}
```

Apache logs uchun (default sozlangan, lekin tekshirish):

```bash
cat /etc/logrotate.d/apache2
```

### 4. Monitoring sozlash (optional)

#### Htop o'rnatish (resurslarni kuzatish)

```bash
sudo apt install -y htop
htop
```

#### Netdata o'rnatish (real-time monitoring)

```bash
# Netdata o'rnatish
bash <(curl -Ss https://my-netdata.io/kickstart.sh)

# Netdata ga kirish
# http://your-server-ip:19999
```

#### Prometheus va Grafana (professional monitoring)

Bu qo'llanmadan tashqarida, lekin tavsiya etiladi production uchun.

### 5. Health check sozlash

Cron job orqali health check:

```bash
crontab -e
```

```cron
# Har 5 daqiqada health check
*/5 * * * * curl -f http://localhost:8000/health || systemctl restart movex_go
```

### 6. Error notification (optional)

Email orqali xatoliklar haqida xabar berish:

```bash
sudo apt install -y mailutils

# Test email
echo "Test message" | mail -s "Test Subject" your-email@example.com
```

Systemd service ga email notification qo'shish:

```bash
sudo nano /etc/systemd/system/movex_go.service
```

```ini
[Service]
...
OnFailure=failure-notification@%n.service
```

---

## Backup va restore

### 1. Database backup

#### Manual backup

```bash
# Backup papkasini yaratish
mkdir -p /opt/movex_go/backups

# Database backup yaratish
pg_dump -U movex_user -h localhost movex_go > /opt/movex_go/backups/backup_$(date +%Y%m%d_%H%M%S).sql

# Yoki Makefile orqali
cd /opt/movex_go
make backup
```

#### Compressed backup

```bash
# Gzip bilan siqish
pg_dump -U movex_user -h localhost movex_go | gzip > /opt/movex_go/backups/backup_$(date +%Y%m%d_%H%M%S).sql.gz

# Custom format (tavsiya etiladi)
pg_dump -U movex_user -h localhost -Fc movex_go > /opt/movex_go/backups/backup_$(date +%Y%m%d_%H%M%S).dump
```

### 2. Database restore

#### SQL fayldan restore

```bash
# Database ni tozalash (agar kerak bo'lsa)
psql -U movex_user -h localhost -d movex_go -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Backup dan restore qilish
psql -U movex_user -h localhost movex_go < /opt/movex_go/backups/backup_file.sql

# Yoki Makefile orqali
cd /opt/movex_go
make restore
# Backup fayl nomini kiriting
```

#### Compressed fayldan restore

```bash
# Gzip dan restore
gunzip -c /opt/movex_go/backups/backup_file.sql.gz | psql -U movex_user -h localhost movex_go

# Custom format dan restore
pg_restore -U movex_user -h localhost -d movex_go /opt/movex_go/backups/backup_file.dump
```

### 3. Avtomatik backup (cron)

#### Backup script yaratish

```bash
sudo nano /opt/movex_go/scripts/backup.sh
```

```bash
#!/bin/bash

# Configuration
BACKUP_DIR="/opt/movex_go/backups"
DB_NAME="movex_go"
DB_USER="movex_user"
RETENTION_DAYS=30

# Create backup directory if not exists
mkdir -p $BACKUP_DIR

# Create backup
BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql.gz"
pg_dump -U $DB_USER -h localhost $DB_NAME | gzip > $BACKUP_FILE

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup created successfully: $BACKUP_FILE"

    # Delete old backups
    find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
    echo "Old backups deleted (older than $RETENTION_DAYS days)"
else
    echo "Backup failed!"
    exit 1
fi
```

```bash
# Script ni executable qilish
chmod +x /opt/movex_go/scripts/backup.sh
```

#### Cron job sozlash

```bash
crontab -e
```

```cron
# Har kuni soat 2:00 da backup
0 2 * * * /opt/movex_go/scripts/backup.sh >> /opt/movex_go/logs/backup.log 2>&1

# Har 6 soatda backup (production uchun)
0 */6 * * * /opt/movex_go/scripts/backup.sh >> /opt/movex_go/logs/backup.log 2>&1
```

### 4. Fayllar va uploads backup

```bash
# Uploads papkasini backup qilish
tar -czf /opt/movex_go/backups/uploads_$(date +%Y%m%d_%H%M%S).tar.gz /opt/movex_go/uploads/

# Butun loyihani backup qilish (database siz)
tar -czf /opt/movex_go/backups/app_$(date +%Y%m%d_%H%M%S).tar.gz \
    --exclude='/opt/movex_go/backups' \
    --exclude='/opt/movex_go/venv' \
    --exclude='/opt/movex_go/.git' \
    /opt/movex_go/
```

### 5. Remote backup (optional)

#### SCP orqali boshqa serverga yuborish

```bash
# Backup ni remote serverga yuborish
scp /opt/movex_go/backups/backup_file.sql.gz user@backup-server:/backups/movex_go/
```

#### Rsync orqali sync qilish

```bash
# Rsync o'rnatish
sudo apt install -y rsync

# Backup papkasini sync qilish
rsync -avz /opt/movex_go/backups/ user@backup-server:/backups/movex_go/
```

### 6. Backup ni tekshirish

```bash
# Backup fayl hajmini ko'rish
ls -lh /opt/movex_go/backups/

# Backup faylni tekshirish (SQL)
gunzip -c /opt/movex_go/backups/backup_file.sql.gz | head -n 20

# Backup dan ma'lumotlarni sanash
gunzip -c /opt/movex_go/backups/backup_file.sql.gz | grep "COPY" | wc -l
```

---

## Troubleshooting

### 1. Service ishlamayapti

```bash
# Service holatini tekshirish
sudo systemctl status movex_go

# Loglarni ko'rish
sudo journalctl -u movex_go -n 100 --no-pager

# Xatoliklarni topish
sudo journalctl -u movex_go -p err

# Service ni qayta ishga tushirish
sudo systemctl restart movex_go

# Service konfiguratsiyasini tekshirish
sudo systemctl cat movex_go
```

### 2. Database ulanish xatosi

```bash
# PostgreSQL ishlab turganini tekshirish
sudo systemctl status postgresql

# PostgreSQL ni qayta ishga tushirish
sudo systemctl restart postgresql

# Database mavjudligini tekshirish
sudo -u postgres psql -l | grep movex_go

# Database ga ulanishni tekshirish
psql -U movex_user -h localhost -d movex_go

# Connection string ni tekshirish
cat /opt/movex_go/.env | grep DATABASE_URL

# PostgreSQL loglarini ko'rish
sudo tail -f /var/log/postgresql/postgresql-15-main.log
```

### 3. Apache ishlamayapti

```bash
# Apache holatini tekshirish
sudo systemctl status apache2

# Apache konfiguratsiyasini tekshirish
sudo apache2ctl configtest

# Apache loglarini ko'rish
sudo tail -f /var/log/apache2/error.log

# Apache ni qayta ishga tushirish
sudo systemctl restart apache2

# Apache modullarini tekshirish
apache2ctl -M | grep proxy
```

### 4. Port band

```bash
# Portni ishlatayotgan jarayonni topish
sudo lsof -i :8000
sudo netstat -tulpn | grep :8000

# Jarayonni to'xtatish
sudo kill -9 <PID>

# Yoki service orqali
sudo systemctl stop movex_go
```

### 5. Permission xatolari

```bash
# Fayl ruxsatlarini tekshirish
ls -la /opt/movex_go/

# Ruxsatlarni to'g'rilash
sudo chown -R www-data:www-data /opt/movex_go/uploads
sudo chown -R www-data:www-data /opt/movex_go/logs
sudo chmod -R 755 /opt/movex_go/uploads
sudo chmod -R 755 /opt/movex_go/logs

# Virtual environment ruxsatlarini tekshirish
ls -la /opt/movex_go/venv/
```

### 6. Disk to'lgan

```bash
# Disk ishlatilishini tekshirish
df -h

# Katta fayllarni topish
du -sh /opt/movex_go/* | sort -h
du -sh /var/log/* | sort -h

# Eski loglarni tozalash
sudo journalctl --vacuum-time=7d
sudo find /var/log -name "*.gz" -mtime +30 -delete

# Eski backuplarni tozalash
find /opt/movex_go/backups -name "*.sql.gz" -mtime +30 -delete

# Temporary fayllarni tozalash
sudo apt clean
sudo apt autoclean
```

### 7. SSL sertifikat xatolari

```bash
# Sertifikat holatini tekshirish
sudo certbot certificates

# Sertifikatni yangilash
sudo certbot renew

# Apache SSL konfiguratsiyasini tekshirish
sudo apache2ctl -t -D DUMP_VHOSTS

# SSL loglarini ko'rish
sudo tail -f /var/log/apache2/movex_go_ssl_error.log
```

### 8. Migration xatolari

```bash
# Migration holatini tekshirish
cd /opt/movex_go
source venv/bin/activate
alembic current

# Migration tarixini ko'rish
alembic history

# Migration ni qayta bajarish
alembic downgrade -1
alembic upgrade head

# Database sxemasini tekshirish
psql -U movex_user -d movex_go -c "\dt"
```

### 9. Python dependencies xatolari

```bash
# Virtual environment ni qayta yaratish
cd /opt/movex_go
rm -rf venv
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Dependencies ni tekshirish
pip list
pip check
```

### 10. Performance muammolari

```bash
# CPU va RAM ishlatilishini ko'rish
htop

# Jarayonlarni ko'rish
ps aux | grep uvicorn

# Database ulanishlarini ko'rish
sudo -u postgres psql -d movex_go -c "SELECT * FROM pg_stat_activity;"

# Slow query larni topish
sudo -u postgres psql -d movex_go -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# Apache worker larni ko'rish
sudo apache2ctl status
```

### 11. Xatolik kodlari va yechimlar

| Xatolik | Sabab | Yechim |
|---------|-------|--------|
| 502 Bad Gateway | Uvicorn ishlamayapti | `sudo systemctl restart movex_go` |
| 503 Service Unavailable | Apache yoki Uvicorn to'xtatilgan | Service larni tekshiring |
| 500 Internal Server Error | Application xatosi | Loglarni ko'ring |
| Connection refused | Port yopiq yoki firewall | Firewall va portlarni tekshiring |
| Permission denied | Fayl ruxsatlari noto'g'ri | Ruxsatlarni to'g'rilang |

---

## Qo'shimcha resurslar

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Apache Documentation](https://httpd.apache.org/docs/)
- [Uvicorn Documentation](https://www.uvicorn.org/)
- [Alembic Documentation](https://alembic.sqlalchemy.org/)
- [Let's Encrypt](https://letsencrypt.org/)
- [Systemd Documentation](https://www.freedesktop.org/software/systemd/man/)

---

## Xavfsizlik tavsiyalari

### 1. Firewall sozlamalari

```bash
# Faqat kerakli portlarni ochish
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw deny 8000/tcp   # Uvicorn portini yopish (faqat localhost)
sudo ufw enable
```

### 2. SSH xavfsizligi

```bash
# SSH konfiguratsiyasini tahrirlash
sudo nano /etc/ssh/sshd_config

# Quyidagi sozlamalarni o'zgartiring:
# PermitRootLogin no
# PasswordAuthentication no  # SSH key ishlatish
# Port 2222  # Default portni o'zgartirish

# SSH ni qayta ishga tushirish
sudo systemctl restart sshd
```

### 3. Fail2ban o'rnatish

```bash
# Fail2ban o'rnatish
sudo apt install -y fail2ban

# Konfiguratsiya yaratish
sudo nano /etc/fail2ban/jail.local

# Apache uchun
[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log

# SSH uchun
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

# Fail2ban ni ishga tushirish
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
```

### 4. Database xavfsizligi

```bash
# PostgreSQL ni faqat localhost dan qabul qilish
sudo nano /etc/postgresql/15/main/postgresql.conf
# listen_addresses = 'localhost'

# Kuchli parol ishlatish
# Parolni muntazam o'zgartirish
# Database backup ni shifrlash
```

### 5. Environment o'zgaruvchilarini himoya qilish

```bash
# .env faylini faqat owner o'qiy olishi
chmod 600 /opt/movex_go/.env
chown www-data:www-data /opt/movex_go/.env

# .env faylini git ga qo'shmaslik
echo ".env" >> /opt/movex_go/.gitignore
```

---

## Yordam

Muammolar yuzaga kelsa:
- GitHub Issues: https://github.com/your-username/movex_go/issues
- Email: support@movexgo.com

---

**Movex GO** - Qurilish texnikasi ijarasi platformasi 🚜

