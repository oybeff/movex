# 🚀 Movex GO - Admin Panel Deployment Guide

## 📋 Umumiy Ma'lumot

Movex GO platformasi uchun to'liq funksional admin panel. Toza PHP (framework yo'q) da yozilgan, PostgreSQL database bilan ishlaydi.

## 🎯 Xususiyatlar

### ✅ Asosiy Funksiyalar:
- **Dashboard**: Real-time statistika (users, equipment, orders, balance)
- **User Management**: Foydalanuvchilarni boshqarish (search, filter, delete)
- **Order Monitoring**: Buyurtmalarni kuzatish va statistika
- **Balance & Transactions**: Moliyaviy operatsiyalar tarixi
- **Database Backup/Restore**: Full/Schema/Data backup tizimi
- **System Information**: Server va database monitoring

### 🎨 Dizayn:
- Responsive CSS (mobile-friendly)
- Modern UI/UX
- AJAX/jQuery integration
- Dark sidebar navigation
- Real-time notifications

### 🔐 Xavfsizlik:
- Session-based authentication
- Role-based access control (admin only)
- Password hashing (bcrypt)
- SQL injection protection (PDO prepared statements)
- XSS protection

## 📁 Fayl Strukturasi

```
admin/
├── assets/
│   ├── css/
│   │   └── style.css          # 790 lines - Complete responsive CSS
│   └── js/
│       └── main.js            # AJAX helpers, notifications, modals
├── includes/
│   ├── header.php             # Sidebar + Header component
│   └── footer.php             # Footer component
├── config.php                 # Database connection, auth functions
├── login.php                  # Admin login page
├── logout.php                 # Logout handler
├── index.php                  # Dashboard (statistics)
├── users.php                  # Users management (pagination, search)
├── orders.php                 # Orders monitoring (filters, stats)
├── balance.php                # Balance & transactions
├── backup.php                 # Database backup/restore UI
├── system.php                 # System information
├── .htaccess                  # Apache security config
└── README.md                  # Documentation
```

## 🔧 O'rnatish (Step-by-Step)

### 1️⃣ Prerequisites

```bash
# PHP 7.4+ va extensions
sudo apt install php7.4 php7.4-pgsql php7.4-mbstring php7.4-xml

# PostgreSQL client tools
sudo apt install postgresql-client

# Apache/Nginx
sudo apt install apache2  # yoki nginx
```

### 2️⃣ Environment Sozlash

`.env` faylini yarating yoki mavjudini yangilang:

```bash
# Database
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=movex_go
POSTGRES_USER=shohruxbek
POSTGRES_PASSWORD=your_secure_password

# Admin Panel
ADMIN_SECRET_KEY=change_this_to_random_string_2024
```

### 3️⃣ Admin User Yaratish

Database'ga admin foydalanuvchi qo'shing:

```sql
-- Connect to database
psql -U shohruxbek -d movex_go

-- Create admin user
INSERT INTO users (full_name, phone, email, password_hash, role, created_at)
VALUES (
    'Admin User',
    '+998901234567',
    'admin@movexgo.uz',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
    'admin',
    NOW()
);

-- Default password: "password"
-- MUHIM: Login qilgandan keyin parolni o'zgartiring!
```

**Parolni o'zgartirish:**

```sql
-- Yangi parol hash yaratish (PHP)
php -r "echo password_hash('yangi_parol', PASSWORD_BCRYPT);"

-- Database'da yangilash
UPDATE users 
SET password_hash = 'yangi_hash' 
WHERE phone = '+998901234567' AND role = 'admin';
```

### 4️⃣ Backup Tizimini Sozlash

```bash
# Backup papkasini yaratish
mkdir -p movex_go_backend/database/backups
chmod 755 movex_go_backend/database/backups

# Script'larni executable qilish
chmod +x movex_go_backend/scripts/backup.sh
chmod +x movex_go_backend/scripts/restore.sh

# Test backup
./movex_go_backend/scripts/backup.sh --full
```

### 5️⃣ Web Server Sozlash

#### Apache Configuration

`/etc/apache2/sites-available/movex-admin.conf`:

```apache
<VirtualHost *:80>
    ServerName admin.movexgo.uz
    DocumentRoot /var/www/movex_go/admin
    
    <Directory /var/www/movex_go/admin>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # PHP settings
        php_value upload_max_filesize 10M
        php_value post_max_size 10M
        php_value memory_limit 256M
    </Directory>
    
    # Logs
    ErrorLog ${APACHE_LOG_DIR}/movex-admin-error.log
    CustomLog ${APACHE_LOG_DIR}/movex-admin-access.log combined
</VirtualHost>
```

Enable site:
```bash
sudo a2ensite movex-admin
sudo a2enmod rewrite
sudo systemctl reload apache2
```

#### Nginx Configuration

`/etc/nginx/sites-available/movex-admin`:

```nginx
server {
    listen 80;
    server_name admin.movexgo.uz;
    root /var/www/movex_go/admin;
    index index.php;
    
    # Security
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Deny access to sensitive files
    location ~ /(config\.php|\.env) {
        deny all;
    }
    
    # Logs
    access_log /var/log/nginx/movex-admin-access.log;
    error_log /var/log/nginx/movex-admin-error.log;
}
```

Enable site:
```bash
sudo ln -s /etc/nginx/sites-available/movex-admin /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 6️⃣ Permissions Sozlash

```bash
# Owner o'rnatish
sudo chown -R www-data:www-data /var/www/movex_go/admin

# Permissions
sudo chmod 755 /var/www/movex_go/admin
sudo chmod 644 /var/www/movex_go/admin/*.php
sudo chmod 600 /var/www/movex_go/admin/config.php

# Backup directory
sudo chown -R www-data:www-data /var/www/movex_go/movex_go_backend/database/backups
sudo chmod 755 /var/www/movex_go/movex_go_backend/database/backups
```

## 🔄 Avtomatik Backup (Cron)

```bash
# Crontab edit
sudo crontab -e

# Har kuni soat 02:00 da full backup
0 2 * * * /var/www/movex_go/movex_go_backend/scripts/backup.sh --full >> /var/log/movex-backup.log 2>&1

# Har dushanba soat 03:00 da eski backuplarni tozalash (30 kundan eski)
0 3 * * 1 find /var/www/movex_go/movex_go_backend/database/backups -name "backup_*.sql*" -mtime +30 -delete
```

## 🔐 Production Xavfsizlik

### 1. Config.php sozlamalari:

```php
// Error reporting o'chirish
error_reporting(0);
ini_set('display_errors', 0);

// HTTPS yoqish
ini_set('session.cookie_secure', 1);

// Secret key o'zgartirish
define('ADMIN_SECRET_KEY', 'your_random_secret_key_here');
```

### 2. SSL/HTTPS sozlash:

```bash
# Let's Encrypt
sudo apt install certbot python3-certbot-apache
sudo certbot --apache -d admin.movexgo.uz
```

### 3. Firewall:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 📊 Monitoring

### Logs tekshirish:

```bash
# Apache
tail -f /var/log/apache2/movex-admin-error.log

# Nginx
tail -f /var/log/nginx/movex-admin-error.log

# Backup logs
tail -f /var/log/movex-backup.log
```

## 🐛 Troubleshooting

### Database connection error:
```bash
# PostgreSQL ishlab turganini tekshiring
sudo systemctl status postgresql

# Connection test
psql -U shohruxbek -d movex_go -h localhost -p 5432
```

### Permission errors:
```bash
# Web server user
ps aux | grep -E 'apache|nginx'

# Permissions fix
sudo chown -R www-data:www-data /var/www/movex_go/admin
```

### Session issues:
```bash
# PHP session directory
php -i | grep session.save_path

# Permissions
sudo chmod 1733 /var/lib/php/sessions
```

## 📞 Support

- **Documentation**: `/admin/README.md`
- **GitHub**: [movex-go/admin-panel](https://github.com/movex-go)
- **Email**: support@movexgo.uz

---

**Deployment Date**: 2024
**Version**: 1.0.0
**Status**: Production Ready ✅

