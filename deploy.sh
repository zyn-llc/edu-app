#!/usr/bin/env bash
# =============================================================================
#  Topag'on — to'liq deploy skripti
# =============================================================================
#  QAYERDA ISHGA TUSHIRILADI: Windows, Git Bash, `D:\platform edu` papkasida.
#
#      cd "/d/platform edu"
#      bash deploy.sh all
#
#  Rejimlar:
#      bash deploy.sh webhook   — Telegram webhook'ni qayta o'rnatish
#      bash deploy.sh split     — domenlarni ajratish (app.topagon.uz)
#      bash deploy.sh all       — backend + app + landing (split'siz)
#
#  Windows buyrug'i VPS ichida ishga tushdi, `tar` ildizi noto'g'ri
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

# da `limit_req_zone` e'lonlari bor, ular http{} kontekstiga tushadi va IKKI
#     limit_req_zone "bilim_otp" is already bound to key "$binary_remote_addr"
NGINX_API_SITE="topagon-api"

# deb o'tkazib yuboradi.
#
# Oldingi marker `noncoin` edi; u 2026-08-07 build'ida allaqachon bor,
#
BUILD_MARKER="Ertangi"

ok()   { printf '\n\033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# VPS `.env` dan bitta qiymatni oladi. Faylni SHELL SIFATIDA BAJARMAYDI —
# deployni to'xtatardi).
remote_env() {
  ssh "$VPS" "sed -n 's/^[[:space:]]*$1=//p' $REMOTE_BACKEND/.env | tail -1 | tr -d '\"'" 2>/dev/null || true
}

need_dir() {
  [ -d "$1" ] || die "Papka topilmadi: $1 — skriptni \"D:\\platform edu\" da ishga tushiring"
}

# --------------------------------------------------------------------------- #
#  BACKEND
# --------------------------------------------------------------------------- #
deploy_backend() {
  need_dir backend/app

  step "0/5  VPS sozlamalari tekshiruvi"
  [ -n "$(remote_env BACKUP_REMOTE)" ] \
    || warn "VPS .env da BACKUP_REMOTE yo'q — zaxira FAQAT o'sha VPS'da qoladi."
  [ -n "$(remote_env ADMIN_IP)" ] \
    || warn "VPS .env da ADMIN_IP yo'q — 'bash deploy.sh nginx' admin cheklovini qo'ya olmaydi."

  step "1/5  Backend kodini VPS'ga ko'chirish"
  tar --exclude='__pycache__' --exclude='*.pyc' \
      -czf /tmp/topagon-backend.tar.gz -C backend app sql scripts deploy
  scp /tmp/topagon-backend.tar.gz "$VPS:/tmp/backend.tar.gz"
  rm -f /tmp/topagon-backend.tar.gz

  step "2/5  Zaxira (migratsiyadan oldin)"
  # `.env` SHELL SIFATIDA BAJARILMAYDI.
  #
  #
  ssh "$VPS" "cd $REMOTE_BACKEND && \
    PGU=\$(sed -n 's/^[[:space:]]*POSTGRES_USER=//p' .env | tail -1 | tr -d '\"') && \
    PGD=\$(sed -n 's/^[[:space:]]*POSTGRES_DB=//p'   .env | tail -1 | tr -d '\"') && \
    $COMPOSE exec -T db pg_dump -U \$PGU -d \$PGD -Fc -f /tmp/pre-deploy.dump && \
    $COMPOSE cp db:/tmp/pre-deploy.dump ./pre-deploy.dump && \
    ls -lh pre-deploy.dump"

  step "3/5  Kodni joyiga qo'yish va qayta qurish"
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
  # xavfsiz o'qiydi (3-qadamda VPS'ga tushdi).
  ssh "$VPS" "cd $REMOTE_BACKEND && ./scripts/migrate.sh --status | tail -10"
  echo
  read -r -p "Yuqorida faqat YANGI migratsiya 'kutmoqda' bo'lsa Enter bosing (to'xtatish: Ctrl+C) " _
  ssh "$VPS" "cd $REMOTE_BACKEND && ./scripts/migrate.sh"

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
  #
  # `split` tugagach: WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app
  local web_base="${WEB_BASE_URL:-https://topagon.uz}"

  #
  # havolani bosgan odam boshdan kechiradigan yo'l.
  curl -sfI --max-time 10 "$web_base" >/dev/null 2>&1 || die \
"WEB_BASE_URL=$web_base ochilmadi (DNS yo'q yoki sayt javob bermayapti).
   Taklif havolalari (?join=KOD) shu manzilga quriladi — build to'xtatildi.
   Ilova hozir qayerda bo'lsa, o'shani bering:
     WEB_BASE_URL=https://topagon.uz bash deploy.sh app"

  step "1/4  Flutter build"
  (
    cd mobile
    flutter pub get
    flutter gen-l10n
    flutter analyze || die "flutter analyze xato berdi — build to'xtatildi"
    # `--pwa-strategy=none` MAJBURIY: usiz service worker ilovani keshlaydi
    flutter build web --release --pwa-strategy=none \
      --dart-define=API_BASE_URL="$API_URL" \
      --dart-define=WEB_BASE_URL="$web_base"
  )

  step "2/4  Build haqiqatan yangimi"
  grep -q "$BUILD_MARKER" mobile/build/web/main.dart.js \
    || die "build'da yangi kod yo'q — 'flutter clean' qilib qaytadan urinib ko'ring"
  ok "yangi kod build'da bor"

  # ---- statikani oldindan siqish -----------------------------------------
  #
  #
  step "2.5/4  Statikani oldindan siqish"
  find mobile/build/web -name "*.symbols" -delete
  find mobile/build/web \
       \( -name "*.js" -o -name "*.css" -o -name "*.json" -o -name "*.wasm" \
          -o -name "*.svg" \) -size +1k -print0 \
    | xargs -0 -r -n 8 gzip -9 -k -f
  ok "$(find mobile/build/web -name '*.gz' | wc -l) ta fayl oldindan siqildi"

  step "3/4  Yuklash"
  tar -czf /tmp/topagon-web.tar.gz -C mobile/build web
  scp /tmp/topagon-web.tar.gz "$VPS:/tmp/web.tar.gz"
  rm -f /tmp/topagon-web.tar.gz
  ssh "$VPS" "rm -rf /tmp/web && tar -xzf /tmp/web.tar.gz -C /tmp && \
    mkdir -p $APP_DIR && rsync -a --delete /tmp/web/ $APP_DIR/ && \
    chown -R www-data:www-data $APP_DIR && rm -rf /tmp/web /tmp/web.tar.gz"

  step "4/4  Serverda tekshirish"
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
# --------------------------------------------------------------------------- #
#
#  `__DOMAIN__` va `__ADMIN_IP__`. Ular REPODA QOLADI — haqiqiy IP git'ga
#
# --------------------------------------------------------------------------- #
deploy_nginx() {
  step "1/3  Admin IP ni aniqlash"
  local admin_ip
  admin_ip="$(remote_env ADMIN_IP)"
  if [ -z "$admin_ip" ]; then
    warn "VPS .env da ADMIN_IP yo'q — admin yuzasi IP bo'yicha CHEKLANMAYDI."
    warn "Tuzatish (VPS'da):  echo 'ADMIN_IP=<sizning-ip>' >> $REMOTE_BACKEND/.env"
    warn "IP ni bilish:       curl -s ifconfig.me"
    admin_ip="all"
  else
    ok "ADMIN_IP = $admin_ip"
  fi

  step "2/3  Konfiguratsiyani o'rnatish"
  local site="/etc/nginx/sites-available/$NGINX_API_SITE"
  # sayt yaratadi va `limit_req_zone` takrorlanib nginx umuman ko'tarilmaydi.
  ssh "$VPS" "test -f $site" \
    || die "$site VPS'da topilmadi — sayt nomi o'zgarganmi? NGINX_API_SITE ni tekshiring"

  # Ship the config to a temp path first; the live site file is only
  # replaced once the checks below pass.
  scp -q backend/deploy/nginx.conf "$VPS:/tmp/nginx-api.src"
  ssh "$VPS" "grep -q '__ADMIN_IP__' /tmp/nginx-api.src" \
    || die "nginx.conf da __ADMIN_IP__ yo'q — noto'g'ri yoki eski fayl yuborildi"

  ssh "$VPS" "cp -f $site $site.bak && \
    sed -e 's/__DOMAIN__/api.topagon.uz/g' \
        -e 's/allow __ADMIN_IP__;/allow $admin_ip;/' \
        /tmp/nginx-api.src > $site && rm -f /tmp/nginx-api.src"

  step "3/3  Sintaksis va qayta yuklash"
  if ! ssh "$VPS" "nginx -t"; then
    ssh "$VPS" "cp -f $site.bak $site && nginx -t" \
      && warn "eski konfiguratsiya qaytarildi — nginx yaroqli holatda" \
      || die "QAYTARISH HAM YIQILDI. VPS'da qo'lda tekshiring: nginx -t"
    die "nginx konfiguratsiyasi yaroqsiz — hech narsa o'zgarmadi"
  fi
  ssh "$VPS" "systemctl reload nginx"

  curl -fsS "$API_URL/health" >/dev/null || die "$API_URL/health javob bermayapti"
  ok "nginx yangilandi (admin: $admin_ip)"
}

# --------------------------------------------------------------------------- #
#  Telegram webhook
#
# --------------------------------------------------------------------------- #
deploy_webhook() {
  step "1/2  Webhook o'rnatish"
  ssh "$VPS" "cd $REMOTE_BACKEND && $COMPOSE exec -T api \
    python scripts/telegram_setup.py --webhook $API_URL/v1/telegram/webhook"

  step "2/2  Tekshirish"
  ssh "$VPS" "cd $REMOTE_BACKEND && $COMPOSE exec -T api \
    python scripts/telegram_setup.py --info" | tee /tmp/tg-info.txt
  grep -q "callback_query" /tmp/tg-info.txt \
    || warn "javobda 'callback_query' ko'rinmadi — tasdiqlash tugmasi ishlamasligi mumkin"
  rm -f /tmp/tg-info.txt
  ok "Webhook o'rnatildi"
}

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

case "${1:-}" in
  backend) deploy_backend ;;
  app)     deploy_app ;;
  landing) deploy_landing ;;
  nginx)   deploy_nginx ;;
  webhook) deploy_webhook ;;
  split)   do_split ;;
  # `nginx` va `webhook` `all` ICHIGA KIRMAYDI — ataylab. Ikkalasi ham
  all)     deploy_backend; deploy_app; deploy_landing ;;
  *)
    cat <<'USAGE'
Ishlatish:
  bash deploy.sh backend   — API (kod + migratsiya)
  bash deploy.sh app       — Flutter Web
  bash deploy.sh landing   — reklama sahifasi (fayllar)
  bash deploy.sh nginx     — API nginx konfiguratsiyasi (VPS .env dagi ADMIN_IP bilan)
  bash deploy.sh webhook   — Telegram webhook (allowed_updates o'zgarganda MAJBURIY)
  bash deploy.sh split     — domenlarni ajratish (DNS tayyor bo'lsa)
  bash deploy.sh all       — backend + app + landing

Tavsiya etilgan tartib:
  1. bash deploy.sh all
  2. bash deploy.sh nginx        (admin IP cheklovi + CSP)
  3. bash deploy.sh webhook      (kirishni tasdiqlash tugmasi uchun)
  4. telefonda sinab ko'ring
  5. DNS tayyor bo'lsa: bash deploy.sh split
  6. WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app
USAGE
    exit 1 ;;
esac
