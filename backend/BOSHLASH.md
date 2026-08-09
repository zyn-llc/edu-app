# Topag'on — BOSHLASH

Noldan `topagon.uz` + `api.topagon.uz` ishlaguncha. **13 bosqich.**
Har biri oldingisiga bog'liq — tartibni buzma.

Batafsil izohlar va muammolar jadvali: [`deploy/DEPLOY.md`](deploy/DEPLOY.md).
Bu fayl — qisqa yo'l xaritasi va tekshiruv ro'yxati.

> **Telegram bot alohida hosting talab qilmaydi.** Bot — bu `@topagonuzbot`
> ga Telegram yuboradigan webhook, uni **shu FastAPI ilovaning o'zi** qabul
> qiladi (`POST /v1/telegram/webhook`). Oracle Cloud, alohida VPS, doimiy
> ishlab turadigan `polling` jarayoni — hech biri kerak emas. Bot API bilan
> bitta konteynerda yashaydi va API bilan birga ko'tariladi.

---

## Oldindan bloklovchi shartlar

| # | Shart | Holat |
|---|---|---|
| 1 | Domen `topagon.uz` — DNS boshqaruvi qo'lda | ⬜️ |
| 2 | VPS: Ubuntu 24.04, 2 vCPU / 2 GB RAM / 40 GB | ⬜️ |
| 3 | DNS A-yozuvlari: `topagon.uz` va `api.topagon.uz` → VPS IP | ⬜️ |
| 4 | `@BotFather` dan bot token olingan | ⬜️ |

> **2 GB RAM ogohlantirishi.** Postgres + Redis + FastAPI bir vaqtda ishlaydi.
> Kontent yuklash (`pg_restore`) paytida OOM bo'lishi mumkin. 8-bosqichdan
> **oldin** 2 GB swap qo'sh (quyida, 1-bosqichda).

---

## 1 — VPS asosiy sozlamasi

```bash
adduser topagon && usermod -aG sudo topagon
# SSH kalit ko'chirilgach, parol bilan kirishni yop:
#   /etc/ssh/sshd_config → PasswordAuthentication no, PermitRootLogin no
systemctl restart ssh

apt update && apt upgrade -y
apt install -y ca-certificates curl git nginx ufw

# Swap — 2 GB RAM'da pg_restore uchun SHART
fallocate -l 2G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker topagon

ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable
timedatectl set-timezone Asia/Tashkent
```

**Tekshir:** `free -h` (swap ko'rinsin), `docker --version`, `ufw status`.

---

## 2 — Kodni joylash

```bash
sudo mkdir -p /opt/topagon && sudo chown topagon:topagon /opt/topagon
cd /opt/topagon
# git clone <repo> backend      — yoki lokaldan:
# scp -r "D:\platform edu\backend" topagon@VPS_IP:/opt/topagon/
cd backend && chmod +x scripts/*.sh
```

`.venv/` ni **ko'chirma** — Windows virtualenv Linux'da ishlamaydi.

---

## 3 — `.env` va 7 ta prod guard

```bash
cp .env.prod.example .env && chmod 600 .env && nano .env
openssl rand -hex 32   # JWT_SECRET
openssl rand -hex 24   # POSTGRES_PASSWORD
openssl rand -hex 24   # ADMIN_API_KEY
openssl rand -hex 24   # TELEGRAM_WEBHOOK_SECRET
```

Bittasi qanoatlanmasa server **ko'tarilmaydi** (bu himoya, bug emas):

| Guard | Qiymat |
|---|---|
| `JWT_SECRET` | ≥32 belgi, `change-me-in-prod` emas |
| `OTP_DEBUG_RETURN` | `false` |
| `DATABASE_URL` | `edu:edu@` bo'lmasin |
| `CORS_ORIGINS` | `https://topagon.uz` (aniq, `*` emas) |
| `SMS_PROVIDER` | `disabled` (Eskiz hali yo'q) |
| ⤷ shart | `INVITE_LOGIN_ENABLED=true` yoki `TELEGRAM_LOGIN_ENABLED=true` |
| `ALLOW_CLIENT_AD_REWARDS` | `false` |

Telegram yoqilsa yana uchtasi shart: `TELEGRAM_BOT_TOKEN`,
`TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`.

Qo'shimcha: `ENVIRONMENT=prod`, `TRUST_PROXY_HEADERS=true` (nginx orqasida),
`APP_NAME=Topag'on`.

---

## 4 — Ko'tarish

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps          # 3 ta healthy
curl -s http://127.0.0.1:8000/health                  # {"status":"ok","env":"prod"}
```

Konteyner qayta-qayta o'chsa → `logs api` da `insecure configuration:` satrini
o'qi, u aynan qaysi guard yetishmayotganini aytadi.

---

## 5 — Migratsiyalar

```bash
./scripts/migrate.sh --status     # nima kutayotganini ko'r
./scripts/migrate.sh              # qo'lla
./scripts/migrate.sh --status     # hammasi QO'LLANGAN bo'lsin
```

Toza bazada `001`–`017` ketma-ket ketadi (`013` yo'q — `014` ichiga kirgan).

> **Lokal dump'ni tiklagan bo'lsang**, avval qo'llanganlarini belgila, aks
> holda `002_seed` dublikat kiritadi:
> ```bash
> for f in 001_init 002_seed 003_app_support 004_phase2 005_coins \
>          006_challenges 007_feedback 008_repair_coins_constraint \
>          008_source_ref_unique 009_notes_announcements \
>          010_retire_legacy_duplicates 011_invite_codes 012_telegram_auth \
>          014_topic_titles 015_topic_titles_ru 016_content_cleanup \
>          017_restore_false_positives; do
>   ./scripts/migrate.sh --mark $f.sql
> done
> ```

---

## 6 — Kontent (13 430 savol)

Qayta yuklashdan ko'ra lokal dump'ni ko'chirish tez va xatosiz:

```powershell
# Windows'da:
cd "D:\platform edu\backend"
docker compose exec -T db pg_dump -U edu -d edu -Fc --no-owner > topagon-content.dump
scp topagon-content.dump topagon@VPS_IP:/opt/topagon/
```

```bash
# VPS'da:
cat /opt/topagon/topagon-content.dump | docker compose -f docker-compose.prod.yml \
    exec -T db pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists --no-owner
```

**Tekshiruv (ikkalasi ham shart):**

```bash
docker compose -f docker-compose.prod.yml exec -T db psql -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT status, count(*) FROM questions GROUP BY status;"
# active 13430 / draft 367 bo'lsin

docker compose -f docker-compose.prod.yml exec api python -m app.ingest.audit_grading
# 0 muammo
```

> ⛔️ **`UPDATE questions SET status='draft' WHERE media IS NOT NULL` — HECH
> QACHON.** `media` da SQL NULL emas, jsonb `'null'` turibdi, ya'ni shart
> **butun bankka** rost bo'ladi va 13 430 savol o'chadi. To'g'ri shart:
> `media ? 'ref'`. Batafsil: `deploy/DEPLOY.md` §6.

---

## 7 — nginx + TLS: API

```bash
sudo cp deploy/proxy_params_bilim /etc/nginx/proxy_params_bilim
sudo cp deploy/nginx.conf /etc/nginx/sites-available/topagon-api
sudo sed -i 's/__DOMAIN__/api.topagon.uz/g' /etc/nginx/sites-available/topagon-api
sudo ln -sf /etc/nginx/sites-available/topagon-api /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 443 blokini VAQTINCHA izohga ol (sertifikat hali yo'q), keyin:
sudo nginx -t && sudo systemctl reload nginx
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.topagon.uz
# 443 blokini izohdan chiqar
sudo nginx -t && sudo systemctl reload nginx
```

**Tekshir:**

```bash
curl -s https://api.topagon.uz/health
curl -s -o /dev/null -w '%{http_code}\n' https://api.topagon.uz/docs   # 404 bo'lsin
```

---

## 8 — Flutter Web build va joylash

```powershell
cd "D:\platform edu\mobile"
flutter clean && flutter pub get && flutter gen-l10n
flutter analyze                                    # 0 xato
flutter build web --release --dart-define=API_BASE_URL=https://api.topagon.uz
scp -r build\web\* topagon@VPS_IP:/tmp/topagon-web/
```

```bash
sudo mkdir -p /var/www/topagon
sudo cp -r /tmp/topagon-web/* /var/www/topagon/
sudo chown -R www-data:www-data /var/www/topagon

sudo cp deploy/nginx-web.conf /etc/nginx/sites-available/topagon-web
sudo sed -i 's/__DOMAIN__/topagon.uz/g' /etc/nginx/sites-available/topagon-web
sudo ln -sf /etc/nginx/sites-available/topagon-web /etc/nginx/sites-enabled/
# 443 bloklarini vaqtincha izohga olib:
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d topagon.uz -d www.topagon.uz
sudo nginx -t && sudo systemctl reload nginx
```

**Tekshir:** brauzerda `https://topagon.uz` ochilsin, DevTools → Network'da
so'rovlar `https://api.topagon.uz` ga ketayotganini ko'r. Konsolda CORS xatosi
bo'lsa → `.env` dagi `CORS_ORIGINS` da `https://topagon.uz` aniq yozilganini
tekshir va `docker compose up -d api` (restart emas!).

---

## 9 — Telegram bot (webhook, alohida hosting kerak emas)

Avval VPS'dan Telegram'ga chiqish borligini tekshir — bu O'zbekistondagi
ba'zi tarmoqlarda bloklangan:

```bash
nslookup api.telegram.org
curl -s -o /dev/null -w '%{http_code}\n' https://api.telegram.org
```

Chiqmasa: bot orqali kirish ishlamaydi, `TELEGRAM_LOGIN_ENABLED=false` qoldir
va taklif kodlariga tayan (10-bosqich).

Chiqsa:

```bash
docker compose -f docker-compose.prod.yml exec api \
    python scripts/telegram_setup.py --webhook
docker compose -f docker-compose.prod.yml exec api \
    python scripts/telegram_setup.py --info      # webhook URL to'g'ri ko'rinsin
```

**Tekshir:** telefonda `@topagonuzbot` → `/start` → javob kelsin. Keyin
ilovada "Telegram orqali kirish" → bot ochiladi → `/start` → ilova o'zi kirsin.

---

## 10 — Taklif kodlari (30 ta sinovchi)

```bash
docker compose -f docker-compose.prod.yml exec api \
    python scripts/make_invites.py --count 1 --uses 40 --label "Beta"
```

Chiqqan kodni 30 ta sinovchiga tarqat. Ular: `topagon.uz` → "Taklif kodi bilan
kirish" → kod → o'ynash.

---

## 11 — Zaxira (bugun, ertaga emas)

```bash
./scripts/backup.sh                   # qo'lda bir marta — ishlashini ko'r
crontab -e
# 0 3 * * * cd /opt/topagon/backend && ./scripts/backup.sh >> /var/log/topagon-backup.log 2>&1
```

Skript dump'ni yozgach `pg_restore -l` bilan **o'qib ko'radi** — chala fayl
zaxira hisoblanmaydi. Haftada bir marta tashqariga ko'chir: serverning
o'zidagi nusxa zaxira emas.

---

## 12 — Monitoring: birinchi hafta, har kuni

```bash
curl -s https://api.topagon.uz/v1/admin/analytics -H "X-Admin-Key: <kalit>"
```

| Ko'rsatkich | Nimani anglatadi |
|---|---|
| `retention.d1` | **Eng muhim raqam.** 20%+ yaxshi start. 5% — mahsulot emas, teshik chelak |
| `suspect_questions` | 20+ urinish, <15% to'g'ri → qiyin emas, **buzuq** savol |
| `subjects` | Talab qaysi fanda — kontent kuchini shunga yo'nalt |
| `timeseries` | O'sish haqiqiymi yoki bir martalik spike |

---

## 13 — Play Store (launch'dan keyin)

Web ishga tushgach, shoshilmasdan:

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.topagon.uz
```

Kerak bo'ladi:

- Google Play Developer akkaunti — **$25**, bir martalik
- **Imzo kaliti** (`upload-keystore.jks`) — yo'qotsang ilovani yangilay
  olmaysan. Ikki joyda zaxirala.
- **Privacy policy** — omma uchun ochiq URL (`topagon.uz/privacy`)
- **Data safety** formasi — telefon raqami va Telegram ID yig'ilishini e'lon qil
- Ekran rasmlari (telefon + planshet), 512×512 ikonka, feature grafika 1024×500
- `applicationId = uz.topagon.app` — **chop etilgandan keyin o'zgartirib
  bo'lmaydi**

Ko'rib chiqish odatda 3–7 kun. Deadline'ga ulgurmaydi — **web versiya asosiy
topshiriq**, Play Store keyin.

---

## Tez yordam

| Alomat | Sabab | Yechim |
|---|---|---|
| api qayta-qayta o'chadi | guard qanoatlanmagan | `logs api` → `insecure configuration:` |
| `getaddrinfo failed` | `DATABASE_URL` hosti | konteyner ichida `db`, hostdan `127.0.0.1` |
| 502 Bad Gateway | api ko'tarilmagan | `curl 127.0.0.1:8000/health` |
| Web ochiladi, ma'lumot yo'q | CORS | `.env` → `CORS_ORIGINS`, keyin `up -d api` |
| Web'da eski versiya qotib qolgan | service worker keshi | Ctrl+Shift+R; `nginx-web.conf` da `index.html` `no-store` |
| `/leaderboard` ga to'g'ridan kirilganda 404 | SPA fallback | `nginx-web.conf` da `try_files ... /index.html` |
| Telegram kirish ishlamaydi | webhook yoki tarmoq | `telegram_setup.py --info`; VPS'dan `curl api.telegram.org` |
| `.env` o'zgardi, ta'sir qilmadi | `restart` `.env` ni o'qimaydi | `docker compose up -d api` |
| Python kodi o'zgardi | image ichida eski kod | `docker compose up -d --build api` |

**Orqaga qaytarish:** `down` → oldingi kodga qayt → `up -d --build`.
Baza uchun: eng oxirgi `backups/*.dump` ni tikla (buyruq `backup.sh` oxirida).
