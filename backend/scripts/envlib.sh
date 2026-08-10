# =============================================================================
#  scripts/envlib.sh — `.env` ni XAVFSIZ o'qish.
#
#
#
#  Bash buni `OTP_MESSAGE_TEMPLATE=Topag'on` deb o'qib, `tasdiqlash` ni
#  BUYRUQ deb ishga tushiradi:
#
#      ./.env: line 42: tasdiqlash: command not found
#
#
#  chiqmaydi.
#
#      . "$(dirname "$0")/envlib.sh"
#      DB_USER="$(env_get POSTGRES_USER postgres)"
# =============================================================================

ENV_FILE="${ENV_FILE:-.env}"

# env_get KALIT [STANDART]
#
# `.env` dan bitta qiymatni qaytaradi. Topilmasa — STANDART (yoki bo'sh satr).
# Izoh qatorlari (`#`) e'tiborsiz.
env_get() {
    local key="$1" default="${2-}" line value

    [ -f "$ENV_FILE" ] || { printf '%s' "$default"; return 0; }

    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$ENV_FILE" \
            | tail -n 1)" || true
    if [ -z "$line" ]; then
        printf '%s' "$default"
        return 0
    fi

    value="${line#*=}"

    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac

    printf '%s' "$value"
}
