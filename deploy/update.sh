#!/usr/bin/env bash
#
# Обновление уже настроенного сервера: свежий код → миграции → перезапуск.
#
# Дамп базы делается ДО миграций и всегда. Миграция типов техники
# меняет данные, а не только схему; без дампа откатить её нечем.
#
#   bash deploy/update.sh

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/movex}"
APP_USER="${APP_USER:-movex}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
step() { echo; echo "${YLW}▸ $*${NC}"; }
ok()   { echo "${GRN}  ✓ $*${NC}"; }
die()  { echo "${RED}✗ $*${NC}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Запускать от root"
[ -d "$APP_DIR/backend" ] || die "Нет $APP_DIR/backend"
cd "$APP_DIR"

step "1/5 Дамп базы"
DUMP="/root/movex_$(date +%F_%H%M).sql"
DB_URL="$(grep -m1 '^DATABASE_URL=' backend/.env | cut -d= -f2-)"
[ -n "$DB_URL" ] || die "В backend/.env нет DATABASE_URL"
pg_dump "$DB_URL" > "$DUMP"
ok "$DUMP ($(du -h "$DUMP" | cut -f1))"

step "2/5 Свежий код"
if [ -d .git ]; then
    git pull --ff-only
    ok "git pull"
else
    echo "  не git-каталог — код обновите сами, продолжаю"
fi

step "3/5 Зависимости"
backend/venv/bin/pip install -q -r backend/requirements.txt
ok "готово"

step "4/5 Миграции"
cd backend
sudo -u "$APP_USER" venv/bin/alembic upgrade head
ok "alembic upgrade head"
cd ..

step "5/5 Перезапуск"
chown -R "$APP_USER:$APP_USER" backend
chmod 640 backend/.env
systemctl restart movex-api
sleep 4
systemctl is-active --quiet movex-api || { journalctl -u movex-api -n 30 --no-pager; die "служба не поднялась"; }
systemctl reload nginx
ok "movex-api и nginx перезапущены"

echo
curl -sS -o /dev/null -w "API: HTTP %{http_code}\n" http://127.0.0.1:8000/health || true
echo "${GRN}Если что-то сломалось, база откатывается так:${NC}"
echo "  psql \"\$DATABASE_URL\" < $DUMP"
