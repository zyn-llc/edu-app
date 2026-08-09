# =============================================================================
#  scripts/envlib.sh — `.env` ni XAVFSIZ o'qish.
#
#  NEGA KERAK (2026-08-09 da topilgan). Skriptlar `.env` ni `set -a; . ./.env`
#  bilan o'qirdi, ya'ni uni SHELL SKRIPTI sifatida BAJARARDI. `.env` esa shell
#  emas — u oddiy `KALIT=qiymat` fayli, va u yerda tirnoqsiz bo'sh joyli
#  qiymatlar bo'lishi mutlaqo normal:
#
#      OTP_MESSAGE_TEMPLATE=Topag'on tasdiqlash kodi: {code}
#
#  Bash buni `OTP_MESSAGE_TEMPLATE=Topag'on` deb o'qib, `tasdiqlash` ni
#  BUYRUQ deb ishga tushiradi:
#
#      ./.env: line 42: tasdiqlash: command not found
#
#  `set -e` bilan birga bu butun skriptni o'ldiradi — zaxira ham olinmaydi,
#  migratsiya ham ishlamaydi. Apostrof (`Topag'on`) esa undan ham yomonroq:
#  u tirnoq ochib, fayl oxirigacha hamma narsani yutib yuboradi.
#
#  Bu yerdagi `env_get` faylni HECH QACHON bajarmaydi — faqat kerakli qatorni
#  topib, qiymatini oladi. Yon ta'siri yo'q, buyruq ishga tushmaydi, sir
#  chiqmaydi.
#
#  Ishlatish:
#      . "$(dirname "$0")/envlib.sh"
#      DB_USER="$(env_get POSTGRES_USER postgres)"
# =============================================================================

#: `.env` fayl yo'li. Chaqiruvchi skript uni o'zgartirishi mumkin.
ENV_FILE="${ENV_FILE:-.env}"

# env_get KALIT [STANDART]
#
# `.env` dan bitta qiymatni qaytaradi. Topilmasa — STANDART (yoki bo'sh satr).
# Qo'llab-quvvatlanadi: tirnoqsiz qiymat, "qo'sh tirnoq", 'bitta tirnoq',
# qiymat ichidagi bo'sh joy va `=`, oldingi bo'sh joylar, `export KALIT=...`.
# Izoh qatorlari (`#`) e'tiborsiz.
env_get() {
    local key="$1" default="${2-}" line value

    [ -f "$ENV_FILE" ] || { printf '%s' "$default"; return 0; }

    # Oxirgi mos qator yutadi — `.env` da takror bo'lsa, xuddi shell kabi.
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$ENV_FILE" \
            | tail -n 1)" || true
    if [ -z "$line" ]; then
        printf '%s' "$default"
        return 0
    fi

    # `KALIT=` gacha bo'lgan hamma narsani kesamiz (birinchi `=` bo'yicha).
    value="${line#*=}"

    # O'rab turgan tirnoqlarni olib tashlaymiz — faqat ikkala tomonda
    # bo'lganda. `#` dan keyingi izohni KESMAYMIZ: parolda `#` bo'lishi
    # mumkin va uni kesish jim ravishda noto'g'ri parol beradi.
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac

    printf '%s' "$value"
}
