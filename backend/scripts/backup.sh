#!/usr/bin/env bash
# =============================================================================
#
#      ./scripts/backup.sh
#
#      crontab -e
#      0 3 * * * cd /opt/topagon/backend && ./scripts/backup.sh >> /var/log/topagon-backup.log 2>&1
#
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"

# `.env` dan o'qiymiz — BAJARMASDAN. `. ./.env` faylni shell skripti sifatida
# `scripts/envlib.sh` da. Qiymatlar hech qayerga chop etilmaydi.
# shellcheck source=scripts/envlib.sh
. "$(dirname "$0")/envlib.sh"

DB_USER="${POSTGRES_USER:-$(env_get POSTGRES_USER edu)}"
DB_NAME="${POSTGRES_DB:-$(env_get POSTGRES_DB edu)}"

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/topagon-$STAMP.dump"

echo "[$(date '+%F %T')] zaxira boshlandi -> $OUT"

if ! docker compose -f "$COMPOSE_FILE" exec -T db \
        pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc --no-owner > "$OUT"; then
    echo "!! XATO: pg_dump yiqildi. Chala fayl o'chirilmoqda." >&2
    rm -f "$OUT"
    exit 1
fi

SIZE=$(stat -c%s "$OUT" 2>/dev/null || echo 0)
if [ "$SIZE" -lt 100000 ]; then
    echo "!! XATO: dump juda kichik ($SIZE bayt) — baza bo'sh yoki dump chala." >&2
    rm -f "$OUT"
    exit 1
fi

# `pg_restore -l` reads the dump's own table of contents, so it fails on a
# truncated or corrupt file.
if ! docker compose -f "$COMPOSE_FILE" exec -T db \
        pg_restore -l < "$OUT" > /dev/null 2>&1; then
    echo "!! XATO: dump o'qilmadi (pg_restore -l yiqildi). Fayl o'chirilmoqda." >&2
    rm -f "$OUT"
    exit 1
fi

QCOUNT=$(docker compose -f "$COMPOSE_FILE" exec -T db \
    psql -U "$DB_USER" -d "$DB_NAME" -tAq \
    -c "SELECT count(*) FROM questions WHERE status='active';" 2>/dev/null || echo '?')

echo "[$(date '+%F %T')] OK — $(numfmt --to=iec "$SIZE" 2>/dev/null || echo "$SIZE B"), aktiv savol: $QCOUNT"

# ---- TASHQARIGA KO'CHIRISH --------------------------------------------------
#
#  bajarilmasdi.
#
#  `.env` da sozlanadi:
#      BACKUP_REMOTE=r2:topagon-backups        # rclone remote (yoki s3:...)
#
BACKUP_REMOTE="${BACKUP_REMOTE:-$(env_get BACKUP_REMOTE)}"
if [ -n "$BACKUP_REMOTE" ]; then
    if ! command -v rclone >/dev/null 2>&1; then
        echo "!! XATO: BACKUP_REMOTE sozlangan, lekin rclone o'rnatilmagan." >&2
        exit 1
    fi
    echo "[$(date '+%F %T')] tashqariga ko'chirilmoqda -> $BACKUP_REMOTE"
    if ! rclone copy --no-traverse "$OUT" "$BACKUP_REMOTE/"; then
        echo "!! XATO: tashqi nusxa yuklanmadi. Lokal fayl saqlanib qoldi:" >&2
        echo "   $OUT" >&2
        exit 1
    fi
    echo "    tashqi nusxa OK"
else
    echo "    ⚠  BACKUP_REMOTE sozlanmagan — zaxira FAQAT shu serverda."
    echo "       VPS yo'qolsa hamma narsa yo'qoladi. .env ga qo'sh:"
    echo "       BACKUP_REMOTE=r2:topagon-backups"
fi

# ---- Eskilarini tozalash ----------------------------------------------------
DELETED=$(find "$BACKUP_DIR" -name 'topagon-*.dump' -mtime "+$KEEP_DAYS" -print -delete | wc -l)
[ "$DELETED" -gt 0 ] && echo "    $DELETED ta eski zaxira o'chirildi (>$KEEP_DAYS kun)."

# =============================================================================
#
#      cat backups/topagon-YYYYMMDD-HHMMSS.dump | \
#        docker compose -f docker-compose.prod.yml exec -T db \
#        pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists --no-owner
# =============================================================================
