# Movex GO Admin Panel

Movex GO platformasi uchun to'liq funksional admin panel. Toza PHP (framework yo'q) da yozilgan.

## 🚀 Xususiyatlar

- ✅ **Dashboard**: Real-time statistika va monitoring
- ✅ **Foydalanuvchilar**: User management (CRUD)
- ✅ **Buyurtmalar**: Order tracking va monitoring
- ✅ **Balans**: Transaction history va balance management
- ✅ **Database Backup**: Full/Schema/Data backup va restore
- ✅ **Tizim Ma'lumotlari**: Server va database monitoring
- ✅ **Authentication**: Secure session-based auth
- ✅ **Responsive Design**: Mobile-friendly UI

## 📋 Talablar

- PHP 7.4+
- PostgreSQL 12+
- Apache/Nginx web server
- PHP PDO PostgreSQL extension

## 🔧 O'rnatish

### 1. Environment sozlash

`.env` faylida database ma'lumotlarini to'g'rilang:

```bash
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=movex_go
POSTGRES_USER=shohruxbek
POSTGRES_PASSWORD=your_password
```

### 2. Admin foydalanuvchi yaratish

Database'da admin user yarating:

```sql
INSERT INTO users (full_name, phone, email, password_hash, role, created_at)
VALUES (
    'Admin User',
    '+998901234567',
    'admin@movexgo.uz',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- password: password
    'admin',
    NOW()
);
```

**Default parol**: `password` (o'zgartiring!)

### 3. Backup papkasini yaratish

```bash
mkdir -p movex_go_backend/database/backups
chmod 755 movex_go_backend/database/backups
```

### 4. Script'larni executable qilish

```bash
chmod +x movex_go_backend/scripts/backup.sh
chmod +x movex_go_backend/scripts/restore.sh
```

### 5. Web server sozlash

#### Apache

`admin/.htaccess` fayli allaqachon mavjud.

#### Nginx

```nginx
location /admin {
    try_files $uri $uri/ /admin/index.php?$query_string;
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
    }
}
```

## 🔐 Xavfsizlik

### Production uchun:

1. **config.php** da error reporting o'chiring:
Xatolarni ekranga chiqarish va sessiya cookie'si endi AVTOMATIK sozlanadi
(config.php):

- xatolar faqat `APP_ENV=development` bo'lganda ko'rinadi, prodda jurnalgagina
  yoziladi;
- HTTPS aniqlansa, cookie `Secure` bayrog'i bilan yuboriladi, ustiga
  `SameSite=Strict` qo'yiladi.

Ya'ni prodda qo'lda o'zgartiradigan narsa yo'q — faqat muhit o'zgaruvchisi:

```bash
APP_ENV=production
```

`ADMIN_SECRET_KEY` olib tashlandi: u kodda ochiq yozilgan edi va hech qayerda
ishlatilmasdi.

4. **Admin parolini** o'zgartiring

5. **Database backup** ni muntazam oling

## 📁 Fayl Strukturasi

```
admin/
├── assets/
│   ├── css/
│   │   └── style.css          # Responsive CSS
│   └── js/
│       └── main.js            # AJAX/jQuery functions
├── includes/
│   ├── header.php             # Header component
│   └── footer.php             # Footer component
├── config.php                 # Configuration
├── login.php                  # Login page
├── logout.php                 # Logout handler
├── index.php                  # Dashboard
├── users.php                  # Users management
├── orders.php                 # Orders monitoring
├── balance.php                # Balance & transactions
├── backup.php                 # Database backup/restore
├── system.php                 # System information
├── .htaccess                  # Apache config
└── README.md                  # Documentation
```

## 🎯 Sahifalar

### Dashboard (`index.php`)
- Umumiy statistika
- So'nggi buyurtmalar
- Quick actions

### Foydalanuvchilar (`users.php`)
- User list (pagination)
- Search va filter
- Delete user

### Buyurtmalar (`orders.php`)
- Order list (pagination)
- Status filter
- Revenue statistics

### Balans (`balance.php`)
- Transaction history
- Filter by type/status
- Balance statistics

### Database Backup (`backup.php`)
- Create backup (full/schema/data)
- Restore from backup
- Delete old backups
- Backup list

### Tizim Ma'lumotlari (`system.php`)
- Database info
- Table sizes
- Server info
- Backup directory status

## 🔄 Backup Tizimi

### Backup yaratish:

```bash
# Full backup
./movex_go_backend/scripts/backup.sh --full

# Schema only
./movex_go_backend/scripts/backup.sh --schema

# Data only
./movex_go_backend/scripts/backup.sh --data
```

### Restore qilish:

```bash
./movex_go_backend/scripts/restore.sh /path/to/backup.sql.gz
```

### Avtomatik backup (cron):

```bash
# Har kuni soat 02:00 da
0 2 * * * /path/to/movex_go_backend/scripts/backup.sh --full
```

## 🐛 Troubleshooting

### Database connection error
- `.env` faylini tekshiring
- PostgreSQL ishlab turganini tekshiring
- User permissions'ni tekshiring

### Backup script ishlamayapti
- Script executable ekanligini tekshiring: `chmod +x backup.sh`
- Backup papkasi mavjud va writable ekanligini tekshiring
- PostgreSQL client tools o'rnatilganligini tekshiring: `pg_dump`, `psql`

### Session issues
- PHP session papkasi writable ekanligini tekshiring
- `session.save_path` sozlamalarini tekshiring

## 📞 Support

Muammolar yuzaga kelsa:
- GitHub Issues: [movex-go/issues](https://github.com/movex-go/issues)
- Email: support@movexgo.uz

## 📄 License

Proprietary - Movex GO Platform

# movex_go_admin
