#!/usr/bin/env bash
#
# Первичная настройка чистого сервера Ubuntu 24.04 под MoveX GO.
#
# Ставит и связывает всё: PostgreSQL, Python-окружение, API под systemd,
# PHP-админку, nginx, файрвол, swap, ночные дампы базы. Запускается от
# root ОДИН раз, но написан идемпотентно — повторный запуск ничего не
# ломает и не перезаписывает уже настроенное (в том числе .env).
#
# Почему не старые scripts/quick_deploy.sh и deploy_movex_004_uz.sh:
# они ставят python3.11 и Apache. В Ubuntu 24.04 пакета python3.11 НЕТ
# вообще — они падают на первом apt install. И админку они не поднимают.
#
#   DOMAIN=movex.004.uz bash deploy/bootstrap_ubuntu24.sh
#
# Домен на этом шаге может ещё не указывать на сервер: сертификат
# выпускается отдельно, скриптом deploy/enable_tls.sh, когда DNS доедет.

set -euo pipefail

DOMAIN="${DOMAIN:-}"
# Где живёт PHP-админка:
#   path      — https://<домен>/panel/   (по умолчанию)
#   subdomain — https://admin.<домен>
#
# По умолчанию путь, а не поддомен: admin.movex.004.uz — это домен
# ЧЕТВЁРТОГО уровня, и не всякий регистратор даёт такую запись. Пути же
# хватает всегда: ни лишней записи в DNS, ни лишнего имени в сертификате.
# Админке всё равно — внутри неё все ссылки относительные.
ADMIN_MODE="${ADMIN_MODE:-path}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-}"
APP_DIR="${APP_DIR:-/opt/movex}"
APP_USER="${APP_USER:-movex}"
DB_NAME="${DB_NAME:-movex_go}"
DB_USER="${DB_USER:-movex}"
# По воркеру на ядро. На 2 ГБ памяти больше двух ставить нельзя:
# каждый воркер держит свой пул к базе и свою копию приложения.
WORKERS="${WORKERS:-2}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
step() { echo; echo "${YLW}▸ $*${NC}"; }
ok()   { echo "${GRN}  ✓ $*${NC}"; }
die()  { echo "${RED}✗ $*${NC}" >&2; exit 1; }

# ---------------------------------------------------------------- проверки

[ "$(id -u)" -eq 0 ] || die "Запускать от root: sudo bash $0"
[ -n "$DOMAIN" ] || die "Не задан DOMAIN. Пример: DOMAIN=movex.004.uz bash $0"
case "$ADMIN_MODE" in
    path)      ADMIN_DOMAIN=""; ADMIN_URL="https://$DOMAIN/panel/" ;;
    subdomain) ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.$DOMAIN}"; ADMIN_URL="https://$ADMIN_DOMAIN" ;;
    *)         die "ADMIN_MODE должен быть path или subdomain, а не '$ADMIN_MODE'" ;;
esac

[ -d "$APP_DIR/backend" ] || die "Нет $APP_DIR/backend — положите сюда весь монорепозиторий"
[ -d "$APP_DIR/admin" ]   || die "Нет $APP_DIR/admin — админка читает ../backend/.env, каталоги должны лежать рядом"

if ! grep -q "24.04" /etc/os-release 2>/dev/null; then
    echo "${YLW}  Внимание: система не Ubuntu 24.04, имена пакетов могут отличаться${NC}"
fi

echo "${GRN}=== MoveX GO: настройка сервера ===${NC}"
echo "  API      : https://$DOMAIN"
echo "  Админка  : $ADMIN_URL"
echo "  Каталог  : $APP_DIR"
echo "  Воркеров : $WORKERS"

# ---------------------------------------------------------------- 1. пакеты

step "1/12 Пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    python3 python3-venv python3-dev build-essential \
    postgresql postgresql-contrib libpq-dev \
    nginx \
    php8.3-fpm php8.3-pgsql php8.3-mbstring php8.3-xml \
    git curl ufw certbot python3-certbot-nginx >/dev/null
ok "python$(python3 -V | cut -d' ' -f2), postgres, nginx, php8.3, certbot"

# ---------------------------------------------------------------- 2. swap

step "2/12 Подкачка"
if swapon --show | grep -q .; then
    ok "уже есть: $(swapon --show=SIZE --noheadings | tr -d ' ' | tr '\n' ' ')"
else
    # 2 ГБ памяти — postgres, python и php вместе упираются в потолок
    # при сборке пакетов и при дампе базы. Без swap процесс убивает OOM.
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap -q /swapfile
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl -qw vm.swappiness=10
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    ok "создано 2 ГБ"
fi

# ---------------------------------------------------------------- 3. пользователь

step "3/12 Системный пользователь $APP_USER"
if id "$APP_USER" >/dev/null 2>&1; then
    ok "уже есть"
else
    adduser --system --group --home "$APP_DIR" --no-create-home "$APP_USER"
    ok "создан"
fi
# www-data (php-fpm) должен читать backend/.env — оттуда админка берёт доступ к базе
usermod -aG "$APP_USER" www-data
ok "www-data добавлен в группу $APP_USER"

# ---------------------------------------------------------------- 4. база

step "4/12 PostgreSQL"
systemctl enable --now postgresql >/dev/null 2>&1 || true

role_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" || true)
if [ "$role_exists" = "1" ]; then
    ok "роль $DB_USER уже есть, пароль не трогаем"
    DB_PASS=""
else
    DB_PASS="$(openssl rand -hex 24)"
    sudo -u postgres psql -qc "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';" >/dev/null
    ok "роль $DB_USER создана"
fi

db_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" || true)
if [ "$db_exists" = "1" ]; then
    ok "база $DB_NAME уже есть"
else
    sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
    ok "база $DB_NAME создана"
fi

# Настройки под 2 ГБ памяти. Значения по умолчанию рассчитаны на машину
# помощнее: shared_buffers=128MB и max_connections=100 вместе с двумя
# воркерами uvicorn и php-fpm упираются в предел.
PGCONF="/etc/postgresql/$(ls /etc/postgresql | sort -n | tail -1)/main/conf.d"
mkdir -p "$PGCONF"
cat > "$PGCONF/movex.conf" <<'PGC'
# MoveX GO — под 2 ГБ ОЗУ
max_connections = 50
shared_buffers = 256MB
effective_cache_size = 768MB
work_mem = 8MB
maintenance_work_mem = 64MB
wal_buffers = 8MB
random_page_cost = 1.1
PGC
systemctl restart postgresql
ok "параметры под 2 ГБ применены"

# ---------------------------------------------------------------- 5. .env

step "5/12 Переменные окружения"
ENV_FILE="$APP_DIR/backend/.env"
if [ "$ADMIN_MODE" = "subdomain" ]; then
    ENV_HOSTS="$DOMAIN,$ADMIN_DOMAIN,127.0.0.1,localhost"
    ENV_ORIGINS="https://$DOMAIN,https://$ADMIN_DOMAIN"
else
    ENV_HOSTS="$DOMAIN,127.0.0.1,localhost"
    ENV_ORIGINS="https://$DOMAIN"
fi
if [ -f "$ENV_FILE" ]; then
    ok ".env уже есть — НЕ трогаем (ключи внутри)"
else
    [ -n "$DB_PASS" ] || die ".env нет, а роль $DB_USER уже существовала — пароль неизвестен.
Задайте вручную:  sudo -u postgres psql -c \"ALTER ROLE $DB_USER PASSWORD 'новый';\"
затем создайте $ENV_FILE по образцу deploy/env.production.example"
    cat > "$ENV_FILE" <<ENVEOF
# Создан bootstrap_ubuntu24.sh $(date +%F)
# Секреты только здесь. В git этот файл не попадает.

DATABASE_URL=postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME
SECRET_KEY=$(openssl rand -hex 32)

APP_ENV=production
DEBUG=false
ALLOWED_HOSTS=$ENV_HOSTS
CORS_ORIGINS=$ENV_ORIGINS

# --- SMS (Eskiz). Пока пусто — коды уходят только в Telegram.
ESKIZ_EMAIL=
ESKIZ_PASSWORD=
OTP_TEST_MODE=false

# --- Telegram: вход по боту
TELEGRAM_BOT_TOKEN=
TELEGRAM_BOT_USERNAME=
# В проде НЕ опрос, а вебхук: uvicorn работает в $WORKERS процессах, и
# каждый опрашивал бы бота отдельно — Telegram отвечает на это 409.
TELEGRAM_POLLING=false
TELEGRAM_WEBHOOK_SECRET=$(openssl rand -hex 32)

# --- Приём платежей. Боевых ключей нет, см. docs/backend/PAYMENTS.md
CLICK_MERCHANT_ID=
CLICK_SERVICE_ID=
CLICK_SECRET_KEY=
CLICK_MERCHANT_USER_ID=
PAYME_MERCHANT_ID=
PAYME_KEY=
PAYME_ACCOUNT_FIELD=transaction_id
SPLIT_MODE=escrow
ENVEOF
    ok "создан, пароль базы и ключи сгенерированы"
fi
chown "$APP_USER:$APP_USER" "$ENV_FILE"
chmod 640 "$ENV_FILE"    # www-data читает по группе, остальные — нет
ok "права 640 $APP_USER:$APP_USER"

# ---------------------------------------------------------------- 6. python

step "6/12 Python-окружение"
mkdir -p "$APP_DIR/backend/media" "$APP_DIR/backend/logs" "$APP_DIR/backend/database/backups"
if [ ! -d "$APP_DIR/backend/venv" ]; then
    python3 -m venv "$APP_DIR/backend/venv"
    ok "venv создан"
fi
"$APP_DIR/backend/venv/bin/pip" install -q --upgrade pip wheel
"$APP_DIR/backend/venv/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt"
ok "зависимости установлены"
chown -R "$APP_USER:$APP_USER" "$APP_DIR/backend"
chmod 750 "$APP_DIR/backend/database/backups"

# ---------------------------------------------------------------- 7. схема

step "7/12 Схема базы"
cd "$APP_DIR/backend"
TABLES=$(sudo -u postgres psql -tAd "$DB_NAME" -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" | tr -d ' ')
if [ "$TABLES" = "0" ]; then
    sudo -u "$APP_USER" venv/bin/python scripts/init_db.py
    ok "база пустая — схема создана init_db.py"
else
    sudo -u "$APP_USER" venv/bin/alembic upgrade head
    ok "$TABLES таблиц — применены миграции alembic"
fi

# ---------------------------------------------------------------- 8. systemd

step "8/12 Служба API"
cat > /etc/systemd/system/movex-api.service <<UNITEOF
[Unit]
Description=MoveX GO API
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/backend
EnvironmentFile=$APP_DIR/backend/.env
ExecStart=$APP_DIR/backend/venv/bin/uvicorn app.main:app \\
    --host 127.0.0.1 --port 8000 --workers $WORKERS \\
    --proxy-headers --forwarded-allow-ips 127.0.0.1
Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR/backend/media $APP_DIR/backend/logs $APP_DIR/backend/database/backups

StandardOutput=journal
StandardError=journal
SyslogIdentifier=movex-api

[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable movex-api >/dev/null 2>&1
systemctl restart movex-api
sleep 4
if systemctl is-active --quiet movex-api; then
    ok "movex-api запущена ($WORKERS воркера)"
else
    echo "${RED}  служба не поднялась:${NC}"
    journalctl -u movex-api -n 30 --no-pager
    die "разберитесь с ошибкой выше и запустите скрипт снова"
fi

# ---------------------------------------------------------------- 9. nginx

step "9/12 nginx"

# Симлинк, чтобы отдавать админку по пути /panel/ обычным root, без alias.
# alias вместе с вложенным location для php даёт неверный SCRIPT_FILENAME,
# и вместо страницы приходит «No input file specified» — на этом теряют
# по полдня, потому что ошибка ничего не объясняет.
mkdir -p /var/www/movex
ln -sfn "$APP_DIR/admin" /var/www/movex/panel

if [ "$ADMIN_MODE" = "path" ]; then
    ADMIN_BLOCK=$(cat <<'NGXPANEL'

    # PHP-админка. Именно /panel/, а не /admin: /admin у API занят
    # собственным роутером, они бы столкнулись.
    location = /panel { return 301 /panel/; }

    location ^~ /panel/ {
        index index.php;
        try_files $uri $uri/ /panel/index.php;

        location ~ ^/panel/.+\.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php8.3-fpm.sock;
            fastcgi_read_timeout 120s;
        }
    }
NGXPANEL
)
else
    ADMIN_BLOCK=""
fi

cat > /etc/nginx/sites-available/movex-api.conf <<NGXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Нужен только для /panel/ — всё остальное уходит в uvicorn
    root /var/www/movex;

    # Столько же, сколько разрешает app/core/media.py (8 МБ), плюс запас
    client_max_body_size 12M;

    # Фотографии техники, объявлений и материалов. Отдаёт nginx напрямую:
    # гонять картинки через uvicorn незачем, воркеров всего $WORKERS.
    location /static/ {
        alias $APP_DIR/backend/media/;
        expires 7d;
        add_header Cache-Control "public";
        access_log off;
        try_files \$uri =404;
    }
$ADMIN_BLOCK
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 90s;
    }

    gzip on;
    gzip_types application/json text/plain application/javascript text/css;
    gzip_min_length 1000;
}
NGXEOF
ln -sf /etc/nginx/sites-available/movex-api.conf /etc/nginx/sites-enabled/movex-api.conf

if [ "$ADMIN_MODE" = "subdomain" ]; then
    cat > /etc/nginx/sites-available/movex-admin.conf <<NGXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $ADMIN_DOMAIN;

    root $APP_DIR/admin;
    index index.php;
    client_max_body_size 12M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_read_timeout 120s;
    }

    location ~ /\. { deny all; }
}
NGXEOF
    ln -sf /etc/nginx/sites-available/movex-admin.conf /etc/nginx/sites-enabled/movex-admin.conf
else
    # Режим сменили — старый поддомен убираем, иначе он остался бы
    # висеть и отдавать админку вторым адресом
    rm -f /etc/nginx/sites-enabled/movex-admin.conf
fi

rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || { nginx -t; die "ошибка в конфигурации nginx"; }
systemctl reload nginx
ok "$DOMAIN → API, $ADMIN_URL → админка"

# ---------------------------------------------------------------- 10. php

step "10/12 php-fpm"
systemctl enable --now php8.3-fpm >/dev/null 2>&1
systemctl restart php8.3-fpm
ok "php8.3-fpm работает"

# ---------------------------------------------------------------- 11. файрвол

step "11/12 Файрвол"
ufw allow OpenSSH >/dev/null
ufw allow 'Nginx Full' >/dev/null
ufw --force enable >/dev/null
ok "открыты 22, 80, 443 — остальное закрыто"

# ---------------------------------------------------------------- 12. дампы

step "12/12 Ночные дампы базы"
cat > /etc/cron.d/movex-backup <<CRONEOF
# Дамп базы каждую ночь в 03:20, хранится 14 дней
20 3 * * * root $APP_DIR/backend/scripts/backup.sh >> /var/log/movex-backup.log 2>&1
CRONEOF
chmod 644 /etc/cron.d/movex-backup
ok "cron настроен на 03:20"

# ---------------------------------------------------------------- итог

echo
echo "${GRN}=== Готово ===${NC}"
curl -sS -o /dev/null -w "  API отвечает: HTTP %{http_code}\n" http://127.0.0.1:8000/health || true
echo
SERVER_IP="$(curl -s -4 --max-time 5 ifconfig.me || echo '<IP сервера>')"
echo "Дальше, по порядку:"
echo "  1. Пропишите у регистратора A-запись на этот сервер:"
echo "       $DOMAIN   A   $SERVER_IP"
if [ "$ADMIN_MODE" = "subdomain" ]; then
echo "       $ADMIN_DOMAIN   A   $SERVER_IP"
else
echo "     (админка на том же домене, по пути /panel/ — второй записи не нужно)"
fi
echo "  2. Когда DNS доедет — сертификаты:  DOMAIN=$DOMAIN bash $APP_DIR/deploy/enable_tls.sh"
echo "  3. Заполните в $ENV_FILE: TELEGRAM_BOT_TOKEN, TELEGRAM_BOT_USERNAME,"
echo "     ESKIZ_EMAIL, ESKIZ_PASSWORD  →  systemctl restart movex-api"
echo "  4. Вебхук бота:  cd $APP_DIR/backend && venv/bin/python scripts/telegram_webhook.py set https://$DOMAIN"
echo "  5. Создайте администратора:  cd $APP_DIR/backend && venv/bin/python scripts/create_admin.py"
echo "     Панель откроется на $ADMIN_URL"
echo
echo "  Логи:      journalctl -u movex-api -f"
echo "  Перезапуск: systemctl restart movex-api"
