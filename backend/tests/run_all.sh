#!/usr/bin/env bash
# Barcha tekshiruvlarni ketma-ket ishga tushiradi.
#
# Server ishlab turgan bo'lishi kerak:
#   venv/bin/uvicorn app.main:app --port 8000
#
# Ishga tushirish:  bash tests/run_all.sh
# Boshqa portdagi server:  API=http://127.0.0.1:8010 bash tests/run_all.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$(dirname "$DIR")"
PY="$BACKEND/venv/bin/python"
# Windows: venv кладёт интерпретатор в Scripts/
[ -x "$PY" ] || PY="$BACKEND/venv/Scripts/python.exe"

if [ ! -x "$PY" ]; then
  echo "venv topilmadi: $PY"
  exit 1
fi

API="${API:-http://127.0.0.1:8000}"
export API

if ! curl -sf "$API/health" >/dev/null 2>&1; then
  echo "Server javob bermayapti ($API). Avval uni ishga tushiring."
  exit 1
fi

failed=0

for test in verify_equipment_types verify_access verify_phone_normalization verify_demo_login verify_money verify_rahmat verify_commission verify_signup_bonus verify_refunds verify_payouts verify_notifications verify_requests verify_quick_orders verify_tariff_flow verify_zones verify_cards verify_listings verify_listing_money verify_materials verify_material_delivery verify_freight verify_catalog verify_tx_language verify_account_state verify_account_deletion verify_profile verify_driver_docs verify_driver_compensation verify_admin_bonus_listing_fee verify_admin_orders verify_admin_users verify_disputes verify_legal verify_admin_csrf verify_otp_security verify_smoke_get; do
  printf '\n\033[1m### %s ###\033[0m\n' "$test"
  if "$PY" "$DIR/$test.py"; then
    :
  else
    failed=$((failed + 1))
  fi
done

printf '\n=====================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'BARCHA TEKSHIRUVLAR MUVAFFAQIYATLI\n'
else
  printf '%d ta tekshiruv to'\''plami xato bilan tugadi\n' "$failed"
fi
printf '=====================================\n'

exit "$failed"
