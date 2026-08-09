#!/usr/bin/env bash
# =============================================================================
#  scripts/migrate.sh — sql/*.sql fayllarini tartib bilan, bir martadan qo'llaydi.
#
#  Nega kerak: hozir migratsiyalar qo'lda qo'llanmoqda va "008 qo'llanganmi?"
#  degan savolga javob faqat esda. Bu skript `schema_migrations` jadvalida
#  qayd yuritadi — qo'llangan fayl qayta ishlamaydi.
#
#  Ishlatish (VPS'da, backend papkasida):
#      ./scripts/migrate.sh              # qo'llash
#      ./scripts/migrate.sh --status     # nima qo'llangan / nima kutyapti
#      ./scripts/migrate.sh --mark 001_init.sql   # allaqachon qo'llangan deb belgilash
#
#  Mavjud bazaga birinchi marta ishlatganda AVVAL --status ni ko'r, keyin
#  allaqachon qo'llangan fayllarni --mark bilan belgilab chiq, keyin ishga tushir.
#  Aks holda 001..008 qayta ishlaydi (ko'pi IF NOT EXISTS, lekin 002_seed
#  kabilari dublikat kiritishi mumkin).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# DIQQAT: faqat `NNN_*.sql` shakli migratsiya hisoblanadi.
# `sql/` da diagnostika fayllari ham bor (`quality_audit.sql`,
# `quality_deep.sql`) — ular faqat SELECT, migratsiya EMAS. Oldin bu yerda
# `*.sql` turardi va ular ham "migratsiya" sifatida ishga tushib,
# `schema_migrations` ga yozilib qolardi.
SQL_DIR="${SQL_DIR:-sql}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

# `.env` ni O'ZIMIZ o'qiymiz.
#
# NEGA (2026-08-06 da deploy paytida topilgan). Ilgari bu yerda
# `${POSTGRES_USER:-edu}` turardi va skript muhit o'zgaruvchisiga tayanardi.
# Lekin `ssh host "./scripts/migrate.sh"` da hech qanday muhit uzatilmaydi —
# skript `edu` ga tushib qolardi va psql `role "edu" does not exist` berardi.
# Migratsiya holati umuman ko'rinmasdi.
#
# `set -a` — fayldagi har bir o'zgaruvchi avtomatik eksport qilinadi.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"

# Testlash uchun almashtiriladigan buyruq. Standart: konteyner ichidagi psql.
PSQL_CMD="${PSQL_CMD:-docker compose -f $COMPOSE_FILE exec -T db psql -U $DB_USER -d $DB_NAME}"

psql_q() {   # jim, faqat qiymat qaytaradi
    $PSQL_CMD -v ON_ERROR_STOP=1 -tAq -c "$1"
}
psql_file() {
    $PSQL_CMD -v ON_ERROR_STOP=1 -f - < "$1"
}

# ---- qayd jadvali -----------------------------------------------------------
psql_q "SET client_min_messages = warning;
         CREATE TABLE IF NOT EXISTS schema_migrations (
            filename   text PRIMARY KEY,
            applied_at timestamptz NOT NULL DEFAULT now()
        );" >/dev/null

applied() {
    psql_q "SELECT 1 FROM schema_migrations WHERE filename = '$1' LIMIT 1;"
}

# ---- rejimlar ---------------------------------------------------------------
case "${1:-}" in
  --status)
      echo "fayl                                  holat"
      echo "------------------------------------- ------------"
      for f in "$SQL_DIR"/[0-9][0-9][0-9]_*.sql; do
          base="$(basename "$f")"
          if [ -n "$(applied "$base")" ]; then
              printf '%-37s QO'"'"'LLANGAN\n' "$base"
          else
              printf '%-37s kutyapti\n' "$base"
          fi
      done
      exit 0
      ;;
  --mark)
      base="${2:?--mark uchun fayl nomi kerak}"
      [ -f "$SQL_DIR/$base" ] || { echo "yo'q: $SQL_DIR/$base" >&2; exit 1; }
      psql_q "INSERT INTO schema_migrations (filename) VALUES ('$base')
              ON CONFLICT DO NOTHING;" >/dev/null
      echo "belgilandi (ishga tushirilmadi): $base"
      exit 0
      ;;
  "" ) ;;
  * ) echo "noma'lum argument: $1" >&2; exit 2 ;;
esac

# ---- qo'llash ---------------------------------------------------------------
count=0
for f in "$SQL_DIR"/[0-9][0-9][0-9]_*.sql; do
    base="$(basename "$f")"
    if [ -n "$(applied "$base")" ]; then
        echo "  o'tkazildi (allaqachon): $base"
        continue
    fi
    echo ">> qo'llanmoqda: $base"
    # Har bir fayl alohida — biri yiqilsa keyingilariga o'tmaymiz.
    if ! psql_file "$f"; then
        echo "!! XATO: $base qo'llanmadi. To'xtatildi." >&2
        exit 1
    fi
    psql_q "INSERT INTO schema_migrations (filename) VALUES ('$base');" >/dev/null
    count=$((count + 1))
done

echo "tayyor — $count ta yangi migratsiya qo'llandi."
