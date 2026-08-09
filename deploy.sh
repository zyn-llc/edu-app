#!/usr/bin/env bash
# =============================================================================
#  Topag'on — to'liq deploy skripti
# =============================================================================
#  QAYERDA ISHGA TUSHIRILADI: Windows, Git Bash, `D:\platform edu` papkasida.
#  VPS'da EMAS. Skript o'zi `ssh` orqali VPS'ga buyruq yuboradi.
#
#      cd "/d/platform edu"
#      bash deploy.sh all
#
#  Rejimlar:
#      bash deploy.sh backend   — faqat API (kod + migratsiya)
#      bash deploy.sh app       — faqat Flutter Web
#      bash deploy.sh landing   — faqat reklama sahifasi
#      bash deploy.sh split     — domenlarni ajratish (app.topagon.uz)
#      bash deploy.sh all       — backend + app + landing (split'siz)
#
#  NEGA SKRIPT. Buyruqlarni qo'lda ko'chirganda uch marta xato bo'ldi:
#  Windows buyrug'i VPS ichida ishga tushdi, `tar` ildizi noto'g'ri
#  ko'rsatildi, `--pwa-strategy=none` unutildi. Skript bularni takrorlamaydi
#  va har qadamdan keyin natijani TEKSHIRADI.
# =============================================================================
set -euo pipefail

VPS_USER="root"
VPS_HOST="189.74.96.41"
VPS="$VPS_USER@$VPS_HOST"
REMOTE_BACKEND="/opt/topagon/backend"
COMPOSE="docker compose -f docker-compose.prod.yml"

API_URL="https://api.topagon.uz"
APP_DIR="/var/www/topagon"          # `split` dan keyin: /var/www/topagon-app
LANDING_DIR="/var/www/topagon-landing"

# Yangi build ekanini tasdiqlaydigan satr — eng OXIRGI sessiyada qo'shilgan
# tarjimadan olinadi, shunda eski build'da uchramasligi kafolatlanadi.
# Har sessiyada yangilang, aks holda tekshiruv eski build'ni ham "yangi"
# deb o'tkazib yuboradi.
# 2026-08-08 (sahifa ritmi + footer sessiyasi): "Ertangi" so'zi faqat
# `dashGoalTomorrow` da ("Ertangi maqsad: N ta savol") uchraydi va u SHU
# sessiyada qo'shildi — ya'ni proddagi hech qanday build'da bo'lishi mumkin
# emas.
#
# Oldingi marker `noncoin` edi; u 2026-08-07 build'ida allaqachon bor,
# shuning uchun endi eski build'ni ham "yangi" deb o'tkazib yuborardi.
#
# Bonus: markerda apostrof ham, bo'sh joy ham yo'q. Oldingi markerlar
# ("Bo'limlar bo'yicha mashq", "Parolni tiklash") apostrof/probel tufayli
# serverdagi `grep` ni buzgan edi — endi qo'sh tirnoq bilan tuzatilgan
# bo'lsa-da, markerni sodda tanlash yana bir xavfsizlik qatlami.
BUILD_MARKER="Ertangi"

ok()   { printf '\n\033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

need_dir() {
  [ -d "$1" ] || die "Papka topilmadi: $1 — skriptni \"D:\\platform edu\" da ishga tushiring"
}

# --------------------------------------------------------------------------- #
#  BACKEND
# --------------------------------------------------------------------------- #
deploy_backend() {
  need_dir backend/app
  step "1/5  Backend kodini VPS'ga ko'chirish"
  # `__pycache__` ATAYLAB tashlanadi: Windows'da yaratilgan .pyc fayllari
  # konteynerdagi Python versiyasiga mos kelmaydi va faqat chalkashtiradi.
  tar --exclude='__pycache__' --exclude='*.pyc' \
      -czf /tmp/topagon-backend.tar.gz -C backend app sql scripts deploy
  scp /tmp/topagon-backend.tar.gz "$VPS:/tmp/backend.tar.gz"
  rm -f /tmp/topagon-backend.tar.gz

  step "2/5  Zaxira (migratsiyadan oldin)"
  ssh "$VPS" "cd $REMOTE_BACKEND && set -a && . ./.env && set +a && \
    $COMPOSE exec -T db pg_dump -U \$POSTGRES_USER -d \$POSTGRES_DB -Fc \
      -f /tmp/pre-deploy.dump && \
    $COMPOSE cp db:/tmp/pre-deploy.dump ./pre-deploy.dump && \
    ls -lh pre-deploy.dump"

  step "3/5  Kodni joyiga qo'yish va qayta qurish"
  # `restart` EMAS — u Python kodini qayta yuklamaydi.
  ssh "$VPS" "cd $REMOTE_BACKEND && \
    rm -rf /tmp/bnew && mkdir -p /tmp/bnew && \
    tar -xzf /tmp/backend.tar.gz -C /tmp/bnew && \
    rsync -a --delete /tmp/bnew/app/ app/ && \
    rsync -a /tmp/bnew/sql/ sql/ && \
    rsync -a /tmp/bnew/scripts/ scripts/ && \
    rsync -a /tmp/bnew/deploy/ deploy/ && \
    chmod +x scripts/*.sh && \
    rm -rf /tmp/bnew /tmp/backend.tar.gz && \
    $COMPOSE up -d --build api"

  step "4/5  Migratsiya holati"
  # `.env` migrate.sh ichida ham o'qiladi, lekin bu yerda ham beramiz —
  # eski `migrate.sh` qolgan bo'lsa ham ishlashi uchun.
  ssh "$VPS" "cd $REMOTE_BACKEND && set -a && . ./.env && set +a && \
    ./scripts/migrate.sh --status | tail -10"
  echo
  read -r -p "Yuqorida faqat YANGI migratsiya 'kutmoqda' bo'lsa Enter bosing (to'xtatish: Ctrl+C) " _
  ssh "$VPS" "cd $REMOTE_BACKEND && set -a && . ./.env && set +a && \
    ./scripts/migrate.sh"

  step "5/5  Tekshiruv"
  sleep 4
  curl -fsS "$API_URL/health" || die "/health javob bermadi"
  echo
  local methods
  methods=$(curl -fsS "$API_URL/v1/auth/methods") || die "/v1/auth/methods yo'q — eski image ishlayapti"
  echo "$methods"
  echo "$methods" | grep -q '"telegram"' || die "javob kutilgandek emas"

  local admin_id
  admin_id=$(ssh "$VPS" "cd $REMOTE_BACKEND && grep '^TELEGRAM_ADMIN_CHAT_ID=' .env | tail -1 | cut -d= -f2" || true)
  case "$admin_id" in
    ""|0|123456789)
      printf '\n\033[33m! TELEGRAM_ADMIN_CHAT_ID = %s — bu HAQIQIY id emas.\n' "${admin_id:-yo\140q}"
      printf '  Murojaatlar hech kimga bormaydi. @userinfobot dan o\140z id\140ingizni oling.\033[0m\n' ;;
    *) ok "Admin chat ID o'rnatilgan" ;;
  esac

  ok "Backend yangilandi"
}

# --------------------------------------------------------------------------- #
#  FLUTTER WEB
# --------------------------------------------------------------------------- #
deploy_app() {
  need_dir mobile
  # ILOVA `app.topagon.uz` DA, apex domen esa reklama sahifasi
  # (deploy/nginx-app.conf, deploy/nginx-landing.conf). Standart qiymat
  # `https://topagon.uz` edi — ya'ni `WEB_BASE_URL` eksport qilinmagan har
  # bir build'da bellashuv havolasi (`?join=KOD`) reklama sahifasiga olib
  # borardi va u yerda `?join=` ni o'qiydigan hech narsa yo'q.
  local web_base="${WEB_BASE_URL:-https://app.topagon.uz}"

  step "1/4  Flutter build"
  (
    cd mobile
    flutter pub get
    flutter gen-l10n
    flutter analyze || die "flutter analyze xato berdi — build to'xtatildi"
    # `--pwa-strategy=none` MAJBURIY: usiz service worker ilovani keshlaydi
    # va sinovchilar yangi versiyani ko'rmaydi.
    flutter build web --release --pwa-strategy=none \
      --dart-define=API_BASE_URL="$API_URL" \
      --dart-define=WEB_BASE_URL="$web_base"
  )

  step "2/4  Build haqiqatan yangimi"
  grep -q "$BUILD_MARKER" mobile/build/web/main.dart.js \
    || die "build'da yangi kod yo'q — 'flutter clean' qilib qaytadan urinib ko'ring"
  ok "yangi kod build'da bor"

  step "3/4  Yuklash"
  # Arxiv ildizi `web/` — VPS'da manba /tmp/web/ bo'ladi, /tmp/web/web/ EMAS.
  tar -czf /tmp/topagon-web.tar.gz -C mobile/build web
  scp /tmp/topagon-web.tar.gz "$VPS:/tmp/web.tar.gz"
  rm -f /tmp/topagon-web.tar.gz
  ssh "$VPS" "rm -rf /tmp/web && tar -xzf /tmp/web.tar.gz -C /tmp && \
    mkdir -p $APP_DIR && rsync -a --delete /tmp/web/ $APP_DIR/ && \
    chown -R www-data:www-data $APP_DIR && rm -rf /tmp/web /tmp/web.tar.gz"

  step "4/4  Serverda tekshirish"
  # DIQQAT: `$BUILD_MARKER` BITTA TIRNOQ ICHIDA EMAS. O'zbekcha matnda
  # apostrof (o'quvchi, bo'lim...) deyarli har doim bor — bitta tirnoq
  # uni ko'rsa erta yopiladi va buyruq boshqa so'zlarga bo'linib ketadi
  # (2026-08-07 da aynan shu sodir bo'ldi: "grep: boyicha mashq: No such
  # file or directory"). Qo'sh tirnoq ichida apostrof oddiy belgi —
  # muammo yo'q, chunki markerda `"` yoki `$` yo'q.
  ssh "$VPS" "grep -c \"$BUILD_MARKER\" $APP_DIR/main.dart.js" \
    | grep -qv '^0$' || die "serverdagi fayl hali eski"
  ok "Ilova yangilandi ($web_base)"
  printf '\033[33m! Brauzerda: F12 → Application → Clear site data, keyin oynani yoping\033[0m\n'
}

# --------------------------------------------------------------------------- #
#  LANDING
# --------------------------------------------------------------------------- #
deploy_landing() {
  need_dir landing
  step "1/2  Landing yuklash"
  tar -czf /tmp/topagon-landing.tar.gz -C landing \
      index.html styles.css main.js content.js assets robots.txt sitemap.xml
  scp /tmp/topagon-landing.tar.gz "$VPS:/tmp/landing.tar.gz"
  rm -f /tmp/topagon-landing.tar.gz
  ssh "$VPS" "mkdir -p $LANDING_DIR && rm -rf /tmp/lnd && mkdir -p /tmp/lnd && \
    tar -xzf /tmp/landing.tar.gz -C /tmp/lnd && \
    rsync -a --delete /tmp/lnd/ $LANDING_DIR/ && \
    chown -R www-data:www-data $LANDING_DIR && \
    rm -rf /tmp/lnd /tmp/landing.tar.gz && ls $LANDING_DIR"

  step "2/2  Tekshiruv"
  ssh "$VPS" "grep -c 'HAR BIR SAVOL' $LANDING_DIR/index.html" \
    | grep -qv '^0$' || die "landing fayllari joyiga tushmadi"
  ok "Landing $LANDING_DIR ga qo'yildi (nginx hali ulanmagan bo'lishi mumkin)"
}

# --------------------------------------------------------------------------- #
#  DOMENLARNI AJRATISH — topagon.uz → landing, app.topagon.uz → ilova
# --------------------------------------------------------------------------- #
do_split() {
  step "1/5  DNS tekshiruvi"
  local ip
  ip=$(ssh "$VPS" "dig +short app.topagon.uz | head -1" || true)
  [ -n "$ip" ] || die "app.topagon.uz uchun A-yozuv yo'q. DNS qo'shing va tarqalishini kuting."
  ok "app.topagon.uz → $ip"

  step "2/5  Ilovani yangi papkaga ko'chirish"
  ssh "$VPS" "mkdir -p /var/www/topagon-app && \
    rsync -a --delete /var/www/topagon/ /var/www/topagon-app/ && \
    chown -R www-data:www-data /var/www/topagon-app"

  step "3/5  nginx konfiguratsiyalari"
  ssh "$VPS" "cd $REMOTE_BACKEND && \
    cp deploy/nginx-landing.conf /etc/nginx/sites-available/topagon-landing && \
    cp deploy/nginx-app.conf     /etc/nginx/sites-available/topagon-app && \
    ln -sf /etc/nginx/sites-available/topagon-app /etc/nginx/sites-enabled/ && \
    nginx -t"

  step "4/5  app.topagon.uz uchun sertifikat"
  ssh "$VPS" "certbot --nginx -d app.topagon.uz --non-interactive --agree-tos \
    -m zayniddin686@gmail.com && nginx -t && systemctl reload nginx"

  step "5/5  Apex domenni landing'ga berish"
  ssh "$VPS" "rm -f /etc/nginx/sites-enabled/topagon-web && \
    ln -sf /etc/nginx/sites-available/topagon-landing /etc/nginx/sites-enabled/ && \
    nginx -t && systemctl reload nginx"

  curl -fsS https://app.topagon.uz | grep -q flutter_bootstrap || die "app.topagon.uz ilovani bermayapti"
  curl -fsS https://topagon.uz | grep -q "HAR BIR SAVOL" || die "topagon.uz landing'ni bermayapti"
  ok "Domenlar ajratildi"
  printf '\033[33m! Endi ilovani QAYTA quring: WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app\033[0m\n'
  printf '\033[33m  Aks holda bellashuv havolasi (?join=KOD) reklama sahifasiga olib boradi.\033[0m\n'
}

# --------------------------------------------------------------------------- #
case "${1:-}" in
  backend) deploy_backend ;;
  app)     deploy_app ;;
  landing) deploy_landing ;;
  split)   do_split ;;
  all)     deploy_backend; deploy_app; deploy_landing ;;
  *)
    cat <<'USAGE'
Ishlatish:
  bash deploy.sh backend   — API (kod + migratsiya)
  bash deploy.sh app       — Flutter Web
  bash deploy.sh landing   — reklama sahifasi (fayllar)
  bash deploy.sh split     — domenlarni ajratish (DNS tayyor bo'lsa)
  bash deploy.sh all       — backend + app + landing

Tavsiya etilgan tartib:
  1. bash deploy.sh all
  2. telefonda sinab ko'ring
  3. DNS tayyor bo'lsa: bash deploy.sh split
  4. WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app
USAGE
    exit 1 ;;
esac
