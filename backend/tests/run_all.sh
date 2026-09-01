#!/usr/bin/env bash
# Barcha tekshiruvlarni ketma-ket ishga tushiradi.
#
# Server ishlab turgan bo'lishi kerak:
#   venv/bin/uvicorn app.main:app --port 8000
#
# Ishga tushirish:  bash tests/run_all.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$(dirname "$DIR")"
PY="$BACKEND/venv/bin/python"

if [ ! -x "$PY" ]; then
  echo "venv topilmadi: $PY"
  exit 1
fi

if ! curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
  echo "Server javob bermayapti (http://127.0.0.1:8000). Avval uni ishga tushiring."
  exit 1
fi

failed=0

for test in verify_equipment_types verify_access verify_money verify_commission verify_refunds verify_payme verify_payouts verify_notifications verify_requests verify_listings verify_account_state verify_admin_csrf verify_otp_security verify_smoke_get; do
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
