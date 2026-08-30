#!/bin/bash

# Movex GO - Tez Deploy Script
# Subdomen: movex.004.uz
# Maqsad: Bir buyruq bilan deploy qilish

set -e  # Xatolik bo'lsa to'xtatish

# Ranglar
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# O'zgaruvchilar
DOMAIN="movex.004.uz"
PROJECT_DIR="/var/www/movex.004.uz"
SERVICE_NAME="movex-api"
APACHE_CONFIG="/etc/apache2/sites-available/movex.004.uz.conf"
SYSTEMD_SERVICE="/etc/systemd/system/movex-api.service"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Movex GO - Tez Deploy${NC}"
echo -e "${GREEN}Subdomen: $DOMAIN${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Root tekshirish
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Iltimos, sudo bilan ishga tushiring!${NC}"
    echo "Misol: sudo bash scripts/quick_deploy.sh"
    exit 1
fi

# 1. Kerakli paketlarni o'rnatish
echo -e "${YELLOW}[1/10] Kerakli paketlarni o'rnatish...${NC}"
apt update -qq
apt install -y python3.11 python3.11-venv postgresql apache2 git certbot python3-certbot-apache > /dev/null 2>&1

# Apache modullarini yoqish
a2enmod proxy proxy_http headers ssl rewrite > /dev/null 2>&1
systemctl restart apache2

echo -e "${GREEN}✓ Paketlar o'rnatildi${NC}"

# 2. Loyiha papkasini yaratish
echo -e "${YELLOW}[2/10] Loyiha papkasini tayyorlash...${NC}"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Agar loyiha hali ko'chirilmagan bo'lsa
if [ ! -f "$PROJECT_DIR/requirements.txt" ]; then
    echo -e "${RED}Xatolik: Loyiha fayllari topilmadi!${NC}"
    echo "Iltimos, loyihani $PROJECT_DIR ga ko'chiring yoki git clone qiling."
    exit 1
fi

chown -R www-data:www-data $PROJECT_DIR
echo -e "${GREEN}✓ Papka tayyor${NC}"

# 3. Python muhitini sozlash
echo -e "${YELLOW}[3/10] Python virtual environment...${NC}"
if [ ! -d "$PROJECT_DIR/venv" ]; then
    sudo -u www-data python3.11 -m venv venv
fi
sudo -u www-data venv/bin/pip install -q --upgrade pip
sudo -u www-data venv/bin/pip install -q -r requirements.txt
echo -e "${GREEN}✓ Python muhiti tayyor${NC}"

# 4. Database yaratish
echo -e "${YELLOW}[4/10] PostgreSQL database...${NC}"
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='movex_go'")
if [ "$DB_EXISTS" != "1" ]; then
    echo "Database parolini kiriting:"
    read -s DB_PASSWORD
    
    sudo -u postgres psql -c "CREATE DATABASE movex_go;" > /dev/null 2>&1 || true
    sudo -u postgres psql -c "CREATE USER movex_user WITH PASSWORD '$DB_PASSWORD';" > /dev/null 2>&1 || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE movex_go TO movex_user;" > /dev/null 2>&1 || true
    
    echo -e "${GREEN}✓ Database yaratildi${NC}"
else
    echo -e "${GREEN}✓ Database mavjud${NC}"
fi

# 5. .env fayl tekshirish
echo -e "${YELLOW}[5/10] Environment sozlamalari...${NC}"
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${RED}Xatolik: .env fayl topilmadi!${NC}"
    echo "Iltimos, .env faylini yarating va sozlang."
    echo "Misol: cp .env.example .env && nano .env"
    exit 1
fi
chmod 600 $PROJECT_DIR/.env
echo -e "${GREEN}✓ Environment tayyor${NC}"

# 6. Migration bajarish
echo -e "${YELLOW}[6/10] Database migration...${NC}"
cd $PROJECT_DIR
sudo -u www-data venv/bin/alembic upgrade head
echo -e "${GREEN}✓ Migration bajarildi${NC}"

# 7. Apache konfiguratsiyasi
echo -e "${YELLOW}[7/10] Apache sozlash...${NC}"
if [ -f "$PROJECT_DIR/apache/subdomain/movex.004.uz.conf" ]; then
    cp $PROJECT_DIR/apache/subdomain/movex.004.uz.conf $APACHE_CONFIG
    a2ensite movex.004.uz.conf > /dev/null 2>&1
    apache2ctl configtest > /dev/null 2>&1
    systemctl reload apache2
    echo -e "${GREEN}✓ Apache sozlandi${NC}"
else
    echo -e "${RED}Xatolik: Apache config fayli topilmadi!${NC}"
    exit 1
fi

# 8. Systemd service
echo -e "${YELLOW}[8/10] Systemd service sozlash...${NC}"
if [ -f "$PROJECT_DIR/systemd/movex-api.service" ]; then
    cp $PROJECT_DIR/systemd/movex-api.service $SYSTEMD_SERVICE
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME > /dev/null 2>&1
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}✓ Service ishga tushdi${NC}"
else
    echo -e "${RED}Xatolik: Service fayli topilmadi!${NC}"
    exit 1
fi

# 9. SSL sertifikat
echo -e "${YELLOW}[9/10] SSL sertifikat...${NC}"
read -p "SSL sertifikat o'rnatilsinmi? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    certbot --apache -d $DOMAIN --non-interactive --agree-tos --email admin@004.uz || echo -e "${YELLOW}SSL o'rnatilmadi (keyinroq qo'lda o'rnating)${NC}"
    echo -e "${GREEN}✓ SSL sozlandi${NC}"
else
    echo -e "${YELLOW}⊘ SSL o'tkazib yuborildi${NC}"
fi

# 10. Tekshirish
echo -e "${YELLOW}[10/10] Tekshirish...${NC}"
sleep 2

# Service holati
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ Service ishlayapti${NC}"
else
    echo -e "${RED}✗ Service ishlamayapti${NC}"
    echo "Loglarni ko'rish: sudo journalctl -u $SERVICE_NAME -n 50"
fi

# Apache holati
if systemctl is-active --quiet apache2; then
    echo -e "${GREEN}✓ Apache ishlayapti${NC}"
else
    echo -e "${RED}✗ Apache ishlamayapti${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploy yakunlandi!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Subdomen: ${GREEN}http://$DOMAIN${NC}"
echo -e "API Docs: ${GREEN}http://$DOMAIN/docs${NC}"
echo -e "Health: ${GREEN}http://$DOMAIN/health${NC}"
echo ""
echo -e "${YELLOW}Foydali buyruqlar:${NC}"
echo "  Service holati: sudo systemctl status $SERVICE_NAME"
echo "  Service loglar: sudo journalctl -u $SERVICE_NAME -f"
echo "  Apache loglar: sudo tail -f /var/log/apache2/movex_error.log"
echo "  Service restart: sudo systemctl restart $SERVICE_NAME"
echo ""
echo -e "${YELLOW}Keyingi qadamlar:${NC}"
echo "  1. DNS sozlamalarida movex.004.uz ni server IP ga yo'naltiring"
echo "  2. SSL sertifikatni yangilang (agar o'rnatilmagan bo'lsa):"
echo "     sudo certbot --apache -d $DOMAIN"
echo "  3. Firewall sozlang:"
echo "     sudo ufw allow 80/tcp"
echo "     sudo ufw allow 443/tcp"
echo ""

