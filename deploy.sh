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
#      bash deploy.sh nginx     — API nginx konfiguratsiyasi (admin IP bilan)
#      bash deploy.sh webhook   — Telegram webhook'ni qayta o'rnatish
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

# VPS'dagi HAQIQIY sayt nomi. Boshqa nom bilan yozib bo'lmaydi: `nginx.conf`
# da `limit_req_zone` e'lonlari bor, ular http{} kontekstiga tushadi va IKKI
# marta e'lon qilinsa nginx butunlay ko'tarilmaydi:
#     limit_req_zone "bilim_otp" is already bound to key "$binary_remote_addr"
# Ya'ni yangi nom = ikkita faol sayt = butun nginx yiqiladi, faqat API emas.
NGINX_API_SITE="topagon-api"

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
warn() { printf '\033[33m!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# VPS `.env` dan bitta qiymatni oladi. Faylni SHELL SIFATIDA BAJARMAYDI —
# sabab `backend/scripts/envlib.sh` da (tirnoqsiz bo'sh joyli qiymat butun
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
  # Bu ikkitasi deployni TO'XTATMAYDI, lekin jim ham qolmaydi. Ikkalasi ham
  # "ishlayapti" ko'rinishida bo'lib, aslida yo'q bo'lgan himoya turi:
  # zaxira faqat o'sha diskda yotadi, admin yuzasi esa ochiq qoladi.
  [ -n "$(remote_env BACKUP_REMOTE)" ] \
    || warn "VPS .env da BACKUP_REMOTE yo'q — zaxira FAQAT o'sha VPS'da qoladi."
  [ -n "$(remote_env ADMIN_IP)" ] \
    || warn "VPS .env da ADMIN_IP yo'q — 'bash deploy.sh nginx' admin cheklovini qo'ya olmaydi."

  step "1/5  Backend kodini VPS'ga ko'chirish"
  # `__pycache__` ATAYLAB tashlanadi: Windows'da yaratilgan .pyc fayllari
  # konteynerdagi Python versiyasiga mos kelmaydi va faqat chalkashtiradi.
  tar --exclude='__pycache__' --exclude='*.pyc' \
      -czf /tmp/topagon-backend.tar.gz -C backend app sql scripts deploy
  scp /tmp/topagon-backend.tar.gz "$VPS:/tmp/backend.tar.gz"
  rm -f /tmp/topagon-backend.tar.gz

  step "2/5  Zaxira (migratsiyadan oldin)"
  # `.env` SHELL SIFATIDA BAJARILMAYDI.
  #
  # Ilgari bu yerda `set -a && . ./.env && set +a` turardi. `.env` esa shell
  # emas: `OTP_MESSAGE_TEMPLATE=Topag'on tasdiqlash kodi: {code}` kabi
  # tirnoqsiz qator bash uchun "`tasdiqlash` buyrug'ini ishga tushir" degani,
  # va `set -e` bilan birga u BUTUN DEPLOYNI shu yerda to'xtatadi —
  # zaxira olinmaydi, lekin sabab «command not found» bo'lib ko'rinadi.
  #
  # Bu qadam `scripts/envlib.sh` dan foydalana OLMAYDI: u VPS'ga faqat
  # 3-qadamda tushadi, zaxira esa undan oldin olinishi shart. Shuning uchun
  # ikkita qiymat shu yerda `sed` bilan olinadi.
  ssh "$VPS" "cd $REMOTE_BACKEND && \
    PGU=\$(sed -n 's/^[[:space:]]*POSTGRES_USER=//p' .env | tail -1 | tr -d '\"') && \
    PGD=\$(sed -n 's/^[[:space:]]*POSTGRES_DB=//p'   .env | tail -1 | tr -d '\"') && \
    $COMPOSE exec -T db pg_dump -U \$PGU -d \$PGD -Fc -f /tmp/pre-deploy.dump && \
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
  # Muhit uzatilmaydi: `migrate.sh` `.env` ni o'zi, `envlib.sh` orqali
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
  # Bellashuv havolasi (`?join=KOD`) SHU manzilga quriladi.
  #
  # Standart — ilova HOZIR turgan joy, kelajakda turadigan joy emas.
  # `app.topagon.uz` `split` bajarilgandan keyin paydo bo'ladi; undan oldin
  # uni standart qilib qo'yish har bir taklif havolasini mavjud bo'lmagan
  # domenga yuboradi (DNS_PROBE_FINISHED_NXDOMAIN) — va buni faqat havolani
  # bosgan odam ko'radi, deploy esa "muvaffaqiyatli" deb tugaydi.
  # `split` tugagach: WEB_BASE_URL=https://app.topagon.uz bash deploy.sh app
  local web_base="${WEB_BASE_URL:-https://topagon.uz}"

  # MANZIL HAQIQATAN OCHILADIMI. Yuqoridagi xato aynan shu tekshiruv
  # yo'qligi uchun prodga chiqdi: build muvaffaqiyatli tugadi, havola esa
  # ochilmadi va buni faqat uni bosgan odam ko'rdi.
  #
  # `nslookup` ATAYLAB ishlatilmadi: Windows'da u mavjud bo'lmagan domen
  # uchun ham 0 qaytaradi, ya'ni qo'riqchi jim o'tkazib yuborardi. `curl`
  # esa DNS, TLS va HTTP — uchalasini birdan tekshiradi, va aynan shu
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
    # va sinovchilar yangi versiyani ko'rmaydi.
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
  # Sabab: birinchi tashrifda brauzer ~8 MB CanvasKit wasm va 3.8 MB
  # `main.dart.js` so'raydi. `gzip on` bilan nginx ularni HAR SO'ROVDA
  # qaytadan siqadi — 2 yadroli VPS'da bu bir necha soniya CPU, va bir
  # nechta yangi foydalanuvchi bir vaqtda kirsa navbat hosil bo'ladi.
  # Qaytgan foydalanuvchida kesh borligi uchun muammo faqat YANGILARDA
  # ko'rinardi.
  #
  # `gzip_static on` bilan nginx tayyor `.gz` ni beradi: siqish bir marta,
  # shu yerda bo'ladi. `-9` shu sababdan — build vaqtida qimmat emas.
  # `.gz` topilmasa nginx odatdagidek o'zi siqadi, ya'ni bu qadam
  # yiqilsa ham sayt ishlaydi.
  step "2.5/4  Statikani oldindan siqish"
  # `.symbols` — stack trace'ni ochish uchun, brauzer ularni HECH QACHON
  # so'ramaydi. Diskda 4.7 MB va har deployda rsync orqali o'tadi.
  find mobile/build/web -name "*.symbols" -delete
  find mobile/build/web \
       \( -name "*.js" -o -name "*.css" -o -name "*.json" -o -name "*.wasm" \
          -o -name "*.svg" \) -size +1k -print0 \
    | xargs -0 -r -n 8 gzip -9 -k -f
  ok "$(find mobile/build/web -name '*.gz' | wc -l) ta fayl oldindan siqildi"

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
# --------------------------------------------------------------------------- #
#  API nginx konfiguratsiyasi — admin IP bilan
#
#  NEGA ALOHIDA BUYRUQ. `deploy/nginx.conf` da ikkita to'ldiriladigan joy bor:
#  `__DOMAIN__` va `__ADMIN_IP__`. Ular REPODA QOLADI — haqiqiy IP git'ga
#  tushmasligi kerak (u sizning uy/ofis manzilingiz, va u o'zgarib turadi).
#  Qiymat VPS `.env` da `ADMIN_IP=` sifatida saqlanadi, `.env` esa git'da yo'q.
#
#  `ADMIN_IP` bo'sh bo'lsa konfiguratsiya YIQILMAYDI: `allow all` qo'yiladi va
#  ogohlantirish chiqadi. Sabab: himoyasiz admin yuzasidan ko'ra ishlaydigan
#  sayt afzal, va kalit + 20/soat cheklov baribir joyida turadi.
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
  # MAVJUD faylning ustiga yoziladi — yangi nom bilan yozish ikkinchi faol
  # sayt yaratadi va `limit_req_zone` takrorlanib nginx umuman ko'tarilmaydi.
  ssh "$VPS" "test -f $site" \
    || die "$site VPS'da topilmadi — sayt nomi o'zgarganmi? NGINX_API_SITE ni tekshiring"

  # Manba — LOKAL fayl, VPS'dagi nusxa emas.
  #
  # NEGA (2026-08-09 da boshdan kechirilgan). Ilgari bu yerda VPS'dagi
  # `deploy/nginx.conf` o'qilardi. Lekin u faqat `deploy.sh backend`
  # muvaffaqiyatli tugagandagina yangilanadi — backend deployi yiqilgan
  # bo'lsa, bu qadam ESKI faylni o'qib, hech narsa o'zgarmagan holda
  # "muvaffaqiyatli" tugaydi. Sabab esa hech qayerda ko'rinmaydi.
  scp -q backend/deploy/nginx.conf "$VPS:/tmp/nginx-api.src"
  ssh "$VPS" "grep -q '__ADMIN_IP__' /tmp/nginx-api.src" \
    || die "nginx.conf da __ADMIN_IP__ yo'q — noto'g'ri yoki eski fayl yuborildi"

  ssh "$VPS" "cp -f $site $site.bak && \
    sed -e 's/__DOMAIN__/api.topagon.uz/g' \
        -e 's/allow __ADMIN_IP__;/allow $admin_ip;/' \
        /tmp/nginx-api.src > $site && rm -f /tmp/nginx-api.src"

  step "3/3  Sintaksis va qayta yuklash"
  # `nginx -t` yiqilsa eski konfiguratsiya QAYTARILADI va yana tekshiriladi:
  # bu qadamdan keyin nginx har doim yaroqli holatda qolishi kerak, aks holda
  # keyingi reload (masalan certbot yangilanishi) butun saytni o'chiradi.
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
#  QAYTA ISHGA TUSHIRISH KERAK bo'ladigan holat: `allowed_updates` o'zgarganda.
#  2026-08-09 da unga `callback_query` qo'shildi (kirishni tasdiqlash tugmasi).
#  Eski webhook'da bu tur umuman kelmaydi — tugma jim ishlamaydi, xato ham
#  chiqmaydi. Aynan shu sababli buni deploy qadamiga aylantirdik.
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

# --------------------------------------------------------------------------- #
case "${1:-}" in
  backend) deploy_backend ;;
  app)     deploy_app ;;
  landing) deploy_landing ;;
  nginx)   deploy_nginx ;;
  webhook) deploy_webhook ;;
  split)   do_split ;;
  # `nginx` va `webhook` `all` ICHIGA KIRMAYDI — ataylab. Ikkalasi ham
  # ishlab turgan xizmatni to'xtatib qo'yishi mumkin (nginx qayta yuklanadi,
  # webhook esa Telegram tomonda almashadi), shuning uchun ular ongli,
  # alohida qadam bo'lishi kerak.
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
