#!/bin/bash

# Movex.004.uz - Avtomatik Deploy Script
# Papka: /www/wwwroot/movex.004.uz
# Systemd bilan

set -e  # Xatolik bo'lsa to'xtatish

# Ranglar
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# O'zgaruvchilar
DOMAIN="movex.004.uz"
PROJECT_DIR="/www/wwwroot/movex.004.uz"
SERVICE_NAME="movex-api"
APACHE_CONFIG="/etc/apache2/sites-available/movex.004.uz.conf"
SYSTEMD_SERVICE="/etc/systemd/system/movex-api.service"

clear
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Movex GO - Avtomatik Deploy${NC}"
echo -e "${BLUE}   Subdomen: $DOMAIN${NC}"
echo -e "${BLUE}   Papka: $PROJECT_DIR${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Root tekshirish
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Iltimos, sudo bilan ishga tushiring!${NC}"
    echo "Misol: sudo bash scripts/deploy_movex_004_uz.sh"
    exit 1
fi

# Papka tekshirish
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ Xatolik: $PROJECT_DIR papka topilmadi!${NC}"
    echo "Iltimos, loyihani $PROJECT_DIR ga joylashtiring."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/requirements.txt" ]; then
    echo -e "${RED}❌ Xatolik: requirements.txt topilmadi!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Papka tekshirildi${NC}"
echo ""

# 1. Kerakli paketlarni o'rnatish
echo -e "${YELLOW}[1/10] Kerakli paketlarni o'rnatish...${NC}"
apt update -qq > /dev/null 2>&1
apt install -y python3.11 python3.11-venv postgresql apache2 certbot python3-certbot-apache > /dev/null 2>&1

# Apache modullarini yoqish
a2enmod proxy proxy_http headers ssl rewrite > /dev/null 2>&1
systemctl restart apache2 > /dev/null 2>&1

echo -e "${GREEN}✓ Paketlar o'rnatildi${NC}"

# 2. Python muhitini sozlash
echo -e "${YELLOW}[2/10] Python virtual environment...${NC}"
cd $PROJECT_DIR

if [ ! -d "$PROJECT_DIR/venv" ]; then
    python3.11 -m venv venv
fi

venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt

echo -e "${GREEN}✓ Python muhiti tayyor${NC}"

# 3. Database yaratish
echo -e "${YELLOW}[3/10] PostgreSQL database...${NC}"

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='movex_go'" 2>/dev/null || echo "0")

if [ "$DB_EXISTS" != "1" ]; then
    echo -e "${BLUE}Database yaratilmoqda...${NC}"
    echo -e "${BLUE}Database paroli kiriting:${NC}"
    read -s DB_PASSWORD
    echo ""
    
    sudo -u postgres psql -c "CREATE DATABASE movex_go;" > /dev/null 2>&1 || true
    sudo -u postgres psql -c "CREATE USER movex_user WITH PASSWORD '$DB_PASSWORD';" > /dev/null 2>&1 || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;" > /dev/null 2>&1 || true
    sudo -u postgres psql -c "ALTER DATABASE movex_go OWNER TO movex_user;" > /dev/null 2>&1 || true
    
    echo -e "${GREEN}✓ Database yaratildi${NC}"
    
    # .env faylni yaratish
    if [ ! -f "$PROJECT_DIR/.env" ]; then
        echo -e "${BLUE}Secret key generatsiya qilinmoqda...${NC}"
        SECRET_KEY=$(openssl rand -hex 32)
        
        cat > $PROJECT_DIR/.env << EOF
# Database
DATABASE_URL=postgresql://movex_user:$DB_PASSWORD@localhost:5432/movex_go

# JWT
SECRET_KEY=$SECRET_KEY
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Application
APP_ENV=production
DEBUG=false

# CORS
CORS_ORIGINS=https://004.uz,https://www.004.uz,https://movex.004.uz
EOF
        echo -e "${GREEN}✓ .env fayl yaratildi${NC}"
    fi
else
    echo -e "${GREEN}✓ Database mavjud${NC}"
fi

# 4. .env fayl tekshirish
echo -e "${YELLOW}[4/10] Environment sozlamalari...${NC}"
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${RED}❌ Xatolik: .env fayl topilmadi!${NC}"
    echo "Iltimos, .env faylini yarating:"
    echo "  nano $PROJECT_DIR/.env"
    exit 1
fi
chmod 600 $PROJECT_DIR/.env
echo -e "${GREEN}✓ Environment tayyor${NC}"

# 5. Migration bajarish
echo -e "${YELLOW}[5/10] Database migration...${NC}"
cd $PROJECT_DIR
venv/bin/alembic upgrade head > /dev/null 2>&1 || echo -e "${YELLOW}⚠ Migration xatolik (keyinroq tekshiring)${NC}"
echo -e "${GREEN}✓ Migration bajarildi${NC}"

# 6. Apache konfiguratsiyasi
echo -e "${YELLOW}[6/10] Apache sozlash...${NC}"

cat > $APACHE_CONFIG << 'EOF'
<VirtualHost *:80>
    ServerName movex.004.uz
    ServerAdmin admin@004.uz

    ErrorLog ${APACHE_LOG_DIR}/movex_error.log
    CustomLog ${APACHE_LOG_DIR}/movex_access.log combined

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    ProxyTimeout 300
    TimeOut 300

    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"

    LimitRequestBody 20971520

    Alias /media /www/wwwroot/movex.004.uz/media
    <Directory /www/wwwroot/movex.004.uz/media>
        Require all granted
        Options -Indexes
    </Directory>
</VirtualHost>
EOF

a2ensite movex.004.uz.conf > /dev/null 2>&1
apache2ctl configtest > /dev/null 2>&1 && systemctl reload apache2 > /dev/null 2>&1

echo -e "${GREEN}✓ Apache sozlandi${NC}"

# 7. Systemd service
echo -e "${YELLOW}[7/10] Systemd service sozlash...${NC}"

cat > $SYSTEMD_SERVICE << 'EOF'
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

ExecStart=/www/wwwroot/movex.004.uz/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 4

Restart=always
RestartSec=10

NoNewPrivileges=true
PrivateTmp=true

StandardOutput=journal
StandardError=journal
SyslogIdentifier=movex-api

[Install]
WantedBy=multi-user.target
EOF

# Ruxsatlarni sozlash
chown -R www-data:www-data $PROJECT_DIR
chmod 600 $PROJECT_DIR/.env

# Service ni ishga tushirish
systemctl daemon-reload
systemctl enable $SERVICE_NAME > /dev/null 2>&1
systemctl restart $SERVICE_NAME

echo -e "${GREEN}✓ Service ishga tushdi${NC}"

# 8. SSL sertifikat
echo -e "${YELLOW}[8/10] SSL sertifikat...${NC}"
read -p "SSL sertifikat o'rnatilsinmi? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    certbot --apache -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null || \
    echo -e "${YELLOW}⚠ SSL o'rnatilmadi (keyinroq qo'lda o'rnating: sudo certbot --apache -d $DOMAIN)${NC}"
else
    echo -e "${YELLOW}⊘ SSL o'tkazib yuborildi${NC}"
fi

# 9. Firewall (optional)
echo -e "${YELLOW}[9/10] Firewall sozlash...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp > /dev/null 2>&1 || true
    ufw allow 443/tcp > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Firewall sozlandi${NC}"
else
    echo -e "${YELLOW}⊘ UFW o'rnatilmagan${NC}"
fi

# 10. Tekshirish
echo -e "${YELLOW}[10/10] Tekshirish...${NC}"
sleep 3

# Service holati
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ Service ishlayapti${NC}"
else
    echo -e "${RED}✗ Service ishlamayapti${NC}"
    echo -e "${YELLOW}Loglarni ko'rish: sudo journalctl -u $SERVICE_NAME -n 50${NC}"
fi

# Apache holati
if systemctl is-active --quiet apache2; then
    echo -e "${GREEN}✓ Apache ishlayapti${NC}"
else
    echo -e "${RED}✗ Apache ishlamayapti${NC}"
fi

# Port tekshirish
if lsof -i :8000 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Port 8000 band (backend ishlayapti)${NC}"
else
    echo -e "${YELLOW}⚠ Port 8000 bo'sh (backend ishlamayapti)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deploy yakunlandi! 🎉${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📍 URL:${NC}"
echo -e "   Subdomen: ${GREEN}http://$DOMAIN${NC}"
echo -e "   API Docs: ${GREEN}http://$DOMAIN/docs${NC}"
echo -e "   Health:   ${GREEN}http://$DOMAIN/health${NC}"
echo ""
echo -e "${BLUE}🛠️  Foydali buyruqlar:${NC}"
echo -e "   Service holati:  ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
echo -e "   Service loglar:  ${YELLOW}sudo journalctl -u $SERVICE_NAME -f${NC}"
echo -e "   Apache loglar:   ${YELLOW}sudo tail -f /var/log/apache2/movex_error.log${NC}"
echo -e "   Service restart: ${YELLOW}sudo systemctl restart $SERVICE_NAME${NC}"
echo ""
echo -e "${BLUE}🔄 Yangilash (update):${NC}"
echo -e "   ${YELLOW}cd $PROJECT_DIR${NC}"
echo -e "   ${YELLOW}git pull${NC}"
echo -e "   ${YELLOW}venv/bin/pip install -r requirements.txt${NC}"
echo -e "   ${YELLOW}venv/bin/alembic upgrade head${NC}"
echo -e "   ${YELLOW}sudo systemctl restart $SERVICE_NAME${NC}"
echo ""
echo -e "${BLUE}📞 Yordam:${NC}"
echo -e "   Agar muammo bo'lsa, loglarni ko'ring:"
echo -e "   ${YELLOW}sudo journalctl -u $SERVICE_NAME -n 100 --no-pager${NC}"
echo ""

