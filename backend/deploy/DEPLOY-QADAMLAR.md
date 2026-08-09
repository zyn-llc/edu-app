# Topag'on — deploy qadamlari (haqiqiy qiymatlar bilan)

> Yozilgan: 2026-08-05. `BOSHLASH.md` ning shu VPS uchun to'ldirilgan varianti.
> Har bir fazadan keyin **TEKSHIR** qatorini bajarib, natijani ko'r. Xato
> chiqsa keyingi fazaga o'tma.

| Nima | Qiymat |
|---|---|
| VPS | `189.74.96.41` — Ubuntu 24.04, 2 vCPU / 2 GB RAM / 40 GB, KVM |
| Panel | `vps.eskiz.uz` → `vps10993` (VM ID 9803) |
| Domen | `topagon.uz`, `api.topagon.uz` (NS: `ns1..4.eskiz.uz`) |
| DNS holati | `api` → VPS ✅ · apex hali hostingda (`45.138.159.4`) ⬜ |
| Ish papkasi | `/opt/topagon` |
| SSH | `C:\Windows\System32\OpenSSH\ssh.exe root@189.74.96.41` |

---

## FAZA 1 — VPS asosi (~30 daq)

VPS'da, `root` sifatida:



Oxirgisi javob bermasa — Telegram kirishi prodda ishlamaydi, taklif kodiga tayanamiz.

---

## FAZA 2 — Kodni ko'chirish (~15 daq)

**Windowsdan** (yangi PowerShell oynasi):

```powershell
$ssh = "C:\Windows\System32\OpenSSH\ssh.exe"
$scp = "C:\Windows\System32\OpenSSH\scp.exe"

& $scp -r "D:\platform edu\backend" root@189.74.96.41:/opt/topagon/
```

⚠️ Bu `backend/.env` ni ham ko'chiradi — u **dev** konfiguratsiyasi
(`ENVIRONMENT=dev`, paroli `edu`). Prod guardlari ishga tushmasdan qolmasligi
uchun **darrov o'chir**:

```bash
# VPS'da
cd /opt/topagon/backend
rm -f .env
rm -rf __pycache__ app/__pycache__ .pytest_cache
ls -la | head
```

---

## FAZA 3 — `.env` (~20 daq)

Sirlarni yasab ol (VPS'da):

```bash
echo "JWT_SECRET=$(openssl rand -hex 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "TELEGRAM_WEBHOOK_SECRET=$(openssl rand -hex 24)"
echo "ADMIN_API_KEY=$(openssl rand -hex 24)"
```

Chiqqan qiymatlarni xavfsiz joyga ko'chir, keyin:

```bash
cd /opt/topagon/backend
cp .env.prod.example .env
chmod 600 .env
nano .env
```

To'ldirish kerak bo'lganlar (fayl ichida ⚠ bilan belgilangan):

| Kalit | Qiymat |
|---|---|
| `POSTGRES_PASSWORD` | yuqoridagi hex |
| `DATABASE_URL` | `postgresql+asyncpg://topagon:<O'SHA HEX>@db:5432/topagon` |
| `JWT_SECRET` | yuqoridagi hex |
| `CORS_ORIGINS` | `https://topagon.uz` |
| `TELEGRAM_BOT_TOKEN` | @BotFather dan **yangi** token (eskisini `/revoke` qil) |
| `TELEGRAM_WEBHOOK_SECRET` | yuqoridagi hex |
| `ADMIN_API_KEY` | yuqoridagi hex |

`SMS_PROVIDER=disabled`, `INVITE_LOGIN_ENABLED=true`,
`ALLOW_CLIENT_AD_REWARDS=false` — namunada allaqachon to'g'ri turibdi, tegma.

⚠️ Fayl nomi aynan **`.env`** bo'lsin. `.env.prod` deb qoldirsang compose
`POSTGRES_USER kerak` deb yiqiladi.

**TEKSHIR:** `grep -c '=' .env` — 40 dan ko'p qator bo'lishi kerak.

---

## FAZA 4 — Konteynerlar va migratsiya (~20 daq)

```bash
cd /opt/topagon/backend
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs --tail 40 api
```

`api` qayta-qayta ko'tarilib yiqilsa — prod guardi ushlagan. Log'da aynan
qaysi guard yozilgan bo'ladi, `.env` da o'sha qatorni tuzat va
`docker compose -f docker-compose.prod.yml up -d api` (restart EMAS).

Migratsiya:

```bash
chmod +x scripts/migrate.sh
./scripts/migrate.sh --status     # baza yangi — hammasi "kutyapti"
./scripts/migrate.sh
./scripts/migrate.sh --status     # hammasi "QO'LLANGAN"
```

**TEKSHIR:** `curl -s http://127.0.0.1:8000/health` → `{"status":"ok","env":"prod"}`

---

## FAZA 5 — Kontent (~15 daq)

**Windowsdan:**

```powershell
& $scp "D:\platform edu\backend\topagon-content.dump" root@189.74.96.41:/opt/topagon/
```

**VPS'da:**

```bash
cd /opt/topagon/backend
set -a; source .env; set +a

docker compose -f docker-compose.prod.yml cp \
  /opt/topagon/topagon-content.dump db:/tmp/content.dump

docker compose -f docker-compose.prod.yml exec -T db \
  pg_restore -U $POSTGRES_USER -d $POSTGRES_DB \
  --clean --if-exists --no-owner /tmp/content.dump
```

`--no-owner` shart: dump `edu` foydalanuvchisi nomidan olingan, prodda esa
`topagon`.

**TEKSHIR:**

```bash
docker compose -f docker-compose.prod.yml exec -T db psql -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT type, status, count(*) FROM questions GROUP BY 1,2 ORDER BY 1,2;"

docker compose -f docker-compose.prod.yml exec api python -m app.ingest.audit_grading
docker compose -f docker-compose.prod.yml exec api python scripts/preflight.py
```

`audit_grading` → **0 problem**. `preflight.py` → chiqish kodi 0.

---

## FAZA 6 — HTTPS: `api.topagon.uz` (~20 daq)

```bash
cd /opt/topagon/backend
cp deploy/proxy_params_bilim /etc/nginx/proxy_params_bilim
cp deploy/nginx.conf /etc/nginx/sites-available/topagon-api
sed -i 's/__DOMAIN__/api.topagon.uz/g' /etc/nginx/sites-available/topagon-api

# certbot 443 blokini o'zi yozadi; hozircha 443 blokini vaqtincha olib turamiz
# emas — certbot mavjud konfiguratsiyani tanadi. Avval sertifikatsiz sinaymiz:
ln -sf /etc/nginx/sites-available/topagon-api /etc/nginx/sites-enabled/topagon-api
rm -f /etc/nginx/sites-enabled/default
nginx -t
```

`nginx -t` sertifikat yo'qligi sababli yiqilsa — 443 blokini vaqtincha
izohga ol (`nano` da), `systemctl reload nginx`, keyin:

```bash
certbot --nginx -d api.topagon.uz
systemctl reload nginx
```

**TEKSHIR:**

```bash
curl -s https://api.topagon.uz/health
curl -s -o /dev/null -w "%{http_code}\n" https://api.topagon.uz/docs   # 404 bo'lishi kerak
```

Ikkinchisi 404 bermasa — `/docs` prodda ochiq qolgan, nginx konfiguratsiyasini
tekshir.

---

## FAZA 7 — Flutter Web: `topagon.uz` (~40 daq)

**1. Apex DNS'ni VPS'ga o'tkaz** (Eskiz DNS paneli):
`topagon.uz.` A yozuvi `45.138.159.4` → `189.74.96.41`, TTL `300`.
`www` CNAME o'zgarmaydi. `mail`, `ftp`, `webmail`, SPF — **tegma**.

Tarqalganini kut: `nslookup topagon.uz 8.8.8.8`

**2. Windowsda build:**

```powershell
cd "D:\platform edu\mobile"
flutter build web --release --dart-define=API_BASE_URL=https://api.topagon.uz
& $scp -r "D:\platform edu\mobile\build\web\*" root@189.74.96.41:/tmp/topagon-web/
```

**3. VPS'da:**

```bash
mkdir -p /var/www/topagon
cp -r /tmp/topagon-web/* /var/www/topagon/
chown -R www-data:www-data /var/www/topagon

cd /opt/topagon/backend
cp deploy/nginx-web.conf /etc/nginx/sites-available/topagon-web
sed -i 's/__DOMAIN__/topagon.uz/g' /etc/nginx/sites-available/topagon-web
ln -sf /etc/nginx/sites-available/topagon-web /etc/nginx/sites-enabled/topagon-web
nginx -t && systemctl reload nginx

certbot --nginx -d topagon.uz -d www.topagon.uz
systemctl reload nginx
```

**TEKSHIR:** brauzerda `https://topagon.uz` — ilova ochilsin, fanlar ro'yxati
kelsin. Oq ekran chiqsa: `F12` → Console → MIME xatosi bormi (nginx `types`
bloki), Network → `/v1/subjects` javobi nima.

---

## FAZA 8 — Telegram (~15 daq)

```bash
cd /opt/topagon/backend
docker compose -f docker-compose.prod.yml exec api python scripts/telegram_setup.py --webhook
docker compose -f docker-compose.prod.yml exec api python scripts/telegram_setup.py --info
```

**TEKSHIR:** telefondan `@topagonuzbot` ga `/start` yubor — bot javob bersin.
Keyin ilovadan "Telegram orqali kirish" → havolani ochib `/start` → ilova
o'zi kirsin.

---

## FAZA 9 — Sinovchilar va APK (~20 daq)

```bash
docker compose -f docker-compose.prod.yml exec api \
  python scripts/make_invites.py --count 1 --uses 40 --label "Beta"
```

Chiqqan kodni 30 sinovchiga tarqat.

APK (Windowsda):

```powershell
cd "D:\platform edu\mobile"
flutter build apk --release
# natija: build\app\outputs\flutter-apk\app-release.apk
```

APK ni Telegram guruhiga tashla + `https://topagon.uz` havolasini yubor.

Zaxira (cron):

```bash
cd /opt/topagon/backend && chmod +x scripts/backup.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/topagon/backend/scripts/backup.sh") | crontab -
```

---

## FAZA 10 — Prodda tekshiruv (~1 soat)

Har birini `https://topagon.uz` da, iloji bo'lsa ikkita qurilmada:

- [ ] Mehmon sifatida quiz — savol keladi, javob baholanadi
- [ ] Mehmon 5-savoldan keyin ro'yxatdan o'tish taklifini ko'radi
- [ ] Taklif kodi bilan kirish
- [ ] Telegram bilan kirish
- [ ] Kirgach XP, tanga, seriya o'sadi
- [ ] Profil saqlash (ism, hudud, sinf)
- [ ] Reyting — podium ko'rinadi, o'z o'rning ajratilgan
- [ ] Bellashuv — kod bilan qo'shilish, ikkala tarafda o'ynash, mukofot
- [ ] Ota-ona: bola kodi bilan ulanish
- [ ] Daftar: eslatma yozish/o'chirish
- [ ] Yangiliklar ro'yxati
- [ ] Fikr yuborish → bazada ko'rinsin
- [ ] Reklama tugmasi → +15 tanga (kuniga 5 marta)
- [ ] Brauzer oynasini toraytir/kengaytir — 600 px dan keng bo'lganda chapda rail

Ertasi kuni:

```bash
curl -s -H "X-Admin-Key: <ADMIN_API_KEY>" https://api.topagon.uz/v1/admin/analytics
```

`retention.d1` va foydalanuvchilar sonini ko'r.
