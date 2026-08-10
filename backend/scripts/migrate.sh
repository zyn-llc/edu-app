#!/usr/bin/env bash
# =============================================================================
#
#
#      ./scripts/migrate.sh              # qo'llash
#      ./scripts/migrate.sh --status     # nima qo'llangan / nima kutyapti
#      ./scripts/migrate.sh --mark 001_init.sql   # allaqachon qo'llangan deb belgilash
#
#  kabilari dublikat kiritishi mumkin).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# `sql/` da diagnostika fayllari ham bor (`quality_audit.sql`,
# `*.sql` turardi va ular ham "migratsiya" sifatida ishga tushib,
SQL_DIR="${SQL_DIR:-sql}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

#
#
# o'ldirardi — batafsili `scripts/envlib.sh` da.
# shellcheck source=scripts/envlib.sh
. "$(dirname "$0")/envlib.sh"

# Tartib: MUHIT > `.env` > standart.
#
#
#   COMPOSE_FILE=docker-compose.yml POSTGRES_USER=edu POSTGRES_DB=edu \
#     ./scripts/migrate.sh --status
DB_USER="${POSTGRES_USER:-$(env_get POSTGRES_USER postgres)}"
DB_NAME="${POSTGRES_DB:-$(env_get POSTGRES_DB postgres)}"

PSQL_CMD="${PSQL_CMD:-docker compose -f $COMPOSE_FILE exec -T db psql -U $DB_USER -d $DB_NAME}"

psql_q() {   # jim, faqat qiymat qaytaradi
    $PSQL_CMD -v ON_ERROR_STOP=1 -tAq -c "$1"
}
psql_file() {
    $PSQL_CMD -v ON_ERROR_STOP=1 -f - < "$1"
}

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
    if ! psql_file "$f"; then
        echo "!! XATO: $base qo'llanmadi. To'xtatildi." >&2
        exit 1
    fi
    psql_q "INSERT INTO schema_migrations (filename) VALUES ('$base');" >/dev/null
    count=$((count + 1))
done

echo "tayyor — $count ta yangi migratsiya qo'llandi."
