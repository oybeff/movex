#!/usr/bin/env bash
#
# Сертификаты Let's Encrypt для API и админки.
#
# Запускать ПОСЛЕ того, как A-записи домена доехали до этого сервера:
# certbot проверяет владение доменом, обращаясь к нему по HTTP. Пока
# домен смотрит в другое место, выпуск не сработает — и, что хуже,
# после пяти неудач подряд Let's Encrypt блокирует домен на час.
# Поэтому скрипт сначала СВЕРЯЕТ, куда указывает домен.
#
#   DOMAIN=movex.004.uz bash deploy/enable_tls.sh

set -euo pipefail

DOMAIN="${DOMAIN:-}"
# Должен совпадать с тем, что задавали в bootstrap_ubuntu24.sh
ADMIN_MODE="${ADMIN_MODE:-path}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-}"
EMAIL="${EMAIL:-}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
die() { echo "${RED}✗ $*${NC}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Запускать от root"
[ -n "$DOMAIN" ] || die "Не задан DOMAIN. Пример: DOMAIN=movex.004.uz bash $0"
if [ "$ADMIN_MODE" = "subdomain" ]; then
    ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.$DOMAIN}"
else
    ADMIN_DOMAIN=""   # админка на том же домене, отдельное имя не нужно
fi

SERVER_IP="$(curl -s -4 --max-time 10 ifconfig.me || true)"
[ -n "$SERVER_IP" ] || die "Не удалось определить внешний IP сервера"
echo "IP этого сервера: $SERVER_IP"

check_dns() {
    local host="$1"
    local got
    got="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | head -1 || true)"
    if [ -z "$got" ]; then
        echo "${RED}  $host — не разрешается вообще (A-записи нет или DNS ещё не разошёлся)${NC}"
        return 1
    fi
    if [ "$got" != "$SERVER_IP" ]; then
        echo "${RED}  $host → $got, а нужно $SERVER_IP${NC}"
        return 1
    fi
    echo "${GRN}  $host → $got ✓${NC}"
    return 0
}

echo
echo "Проверяю DNS:"
bad=0
check_dns "$DOMAIN" || bad=1
[ -n "$ADMIN_DOMAIN" ] && { check_dns "$ADMIN_DOMAIN" || bad=1; }
if [ "$bad" -ne 0 ]; then
    echo
    echo "${YLW}Пропишите у своего регистратора и подождите, пока разойдётся:${NC}"
    echo "    $DOMAIN.   A   $SERVER_IP"
    [ -n "$ADMIN_DOMAIN" ] && echo "    $ADMIN_DOMAIN.   A   $SERVER_IP"
    echo
    echo "Проверить со стороны:  dig +short $DOMAIN"
    die "DNS ещё не готов — выпуск сертификата пока не запускаю"
fi

ARGS=(--nginx --non-interactive --agree-tos --redirect -d "$DOMAIN")
[ -n "$ADMIN_DOMAIN" ] && ARGS+=(-d "$ADMIN_DOMAIN")
if [ -n "$EMAIL" ]; then
    ARGS+=(-m "$EMAIL")
else
    ARGS+=(--register-unsafely-without-email)
fi

echo
echo "${YLW}▸ Выпускаю сертификаты${NC}"
certbot "${ARGS[@]}"

# Продление certbot ставит сам (systemd-таймер), проверим что он на месте
systemctl list-timers 'certbot*' --no-pager | head -3

echo
echo "${GRN}=== Готово ===${NC}"
curl -sS -o /dev/null -w "  https://$DOMAIN/health → HTTP %{http_code}\n" "https://$DOMAIN/health" || true
echo
echo "Теперь можно включить вебхук бота (нужен именно https):"
echo "  cd \${APP_DIR:-/opt/movex}/backend && venv/bin/python scripts/telegram_webhook.py set https://$DOMAIN"
