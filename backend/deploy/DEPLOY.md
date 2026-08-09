# Bilim — DEPLOY runbook

Noldan ishlaydigan prod'gacha. Tartib bilan bor; har qadam oldingisiga bog'liq.

**Oldin bajarilishi shart (bloklovchi):**

- [ ] Domen olingan (Eskiz.uz orqali). Bu yerda `api.MISOL.uz` deb yozilgan —
      hamma joyda o'zingnikiga almashtir.
- [ ] Eskiz SMS shabloni moderatsiyaga **yuborilgan** (bir necha kun ketadi —
      shuni bugun boshla, oxiriga qoldirma).
- [ ] VPS: Ubuntu 24.04, 2 vCPU / 4 GB RAM / 50 GB SSD yetadi.

---

## 0 — Lokalda oxirgi tekshiruv (VPS'ga chiqishdan oldin)

```powershell
cd "D:\platform edu\backend"
$env:PYTHONPATH = "."
python -m pytest tests -q          # 63 test o'tishi kerak
python -m app.ingest.audit_grading # 0 muammo
```

Ikkalasi ham toza bo'lmasa, VPS'ga chiqma.

---

## 1 — VPS asosiy sozlamasi

```bash
# root sifatida
adduser bilim && usermod -aG sudo bilim
# SSH kalitni ko'chir, keyin parol bilan kirishni yop:
#   /etc/ssh/sshd_config -> PasswordAuthentication no, PermitRootLogin no
systemctl restart ssh

apt update && apt upgrade -y
apt install -y ca-certificates curl git nginx ufw
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker bilim

# Faqat SSH + web. 5432/6379 hech qachon ochilmaydi.
ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable
timedatectl set-timezone Asia/Tashkent
```

Chiqib, `bilim` foydalanuvchisi sifatida qayta kir.

---

## 2 — Kodni joylash

```bash
sudo mkdir -p /opt/bilim && sudo chown bilim:bilim /opt/bilim
cd /opt/bilim
# git bo'lsa: git clone <repo> backend
# bo'lmasa lokaldan:  scp -r "D:\platform edu\backend" bilim@VPS_IP:/opt/bilim/
cd backend
chmod +x scripts/*.sh
```

`.venv/` ni **ko'chirma** — Windows virtualenv Linux'da ishlamaydi va image'ga
ham tushmaydi (`.dockerignore`).

---

## 3 — `.env`

```bash
cp .env.prod.example .env
nano .env
chmod 600 .env
```

Yettita guard to'ldirilishi shart — biri yetishmasa server **ko'tarilmaydi**
(bu bug emas, himoya). Kalitlar:

```bash
openssl rand -hex 32   # JWT_SECRET
openssl rand -hex 24   # POSTGRES_PASSWORD
openssl rand -hex 24   # ADMIN_API_KEY
```

`DATABASE_URL` dagi user/parol/db `POSTGRES_*` bilan aynan mos bo'lsin.

---

## 4 — Ko'tarish

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps      # uchalasi healthy bo'lsin
docker compose -f docker-compose.prod.yml logs -f api
```

Log'da `insecure configuration: ...` chiqsa — `.env` da o'sha guard to'ldirilmagan.
Xato matni aynan qaysi biri ekanini aytadi.

```bash
curl -s http://127.0.0.1:8000/health     # {"status":"ok","env":"prod"}
```

---

## 5 — Migratsiyalar

```bash
./scripts/migrate.sh --status     # nima kutayotganini ko'r
./scripts/migrate.sh              # qo'lla
```

Toza bazada 001→010 ketma-ket qo'llanadi va `schema_migrations` da qayd etiladi.

> **Mavjud bazani ko'chirgan bo'lsang** (lokal dump'ni restore qilgan bo'lsang):
> avval allaqachon qo'llanganlarni belgilab chiq, aks holda `002_seed` dublikat
> kiritadi:
> ```bash
> for f in 001_init 002_seed 003_app_support 004_phase2 005_coins \
>          006_challenges 007_feedback 008_repair_coins_constraint \
>          008_source_ref_unique; do ./scripts/migrate.sh --mark $f.sql; done
> ./scripts/migrate.sh          # faqat 009 va 010 qo'llanadi
> ```

---

## 6 — Kontent

Eng oson yo'l: lokal bazani dump qilib, VPS'ga tiklash — 14 798 savolni qayta
yuklashdan tez va xatosiz.

```powershell
# Lokalda (Windows):
docker compose exec -T db pg_dump -U edu -d edu -Fc > bilim-content.dump
scp bilim-content.dump bilim@VPS_IP:/opt/bilim/
```

```bash
# VPS'da:
cat /opt/bilim/bilim-content.dump | docker compose -f docker-compose.prod.yml \
    exec -T db pg_restore -U bilim -d bilim --clean --if-exists --no-owner
```

> ### ⛔️ TO'XTA — quyidagi buyruqni ISHLATMA
>
> Bu runbook'ning oldingi versiyasida shu satr turardi:
>
> ```sql
> UPDATE questions SET status='draft' WHERE media IS NOT NULL AND status='active';
> ```
>
> **U butun savol bankini o'chiradi.** Sabab: `media` ustunida SQL `NULL` emas,
> jsonb `'null'` qiymati turibdi (13 584 qatorda). SQL uchun jsonb `'null'` —
> bu NULL EMAS, ya'ni `media IS NOT NULL` **hamma qatorga rost** bo'ladi va
> 13 430 ta aktiv savolning hammasi `draft` ga tushadi.
>
> To'g'ri shart — kalit mavjudligini tekshirish:
>
> ```sql
> UPDATE questions SET status='draft'
>  WHERE media ? 'ref' AND status='active';
> ```
>
> Ishlatishdan oldin doim avval SELECT bilan sanab ko'r:
>
> ```bash
> docker compose -f docker-compose.prod.yml exec -T db psql -U bilim -d bilim -c \
>   "SELECT jsonb_typeof(media) AS tur, count(*) FROM questions GROUP BY 1;"
> ```

Kontent allaqachon tozalangan (`016`, `017` migratsiyalari) — 13 430 aktiv,
367 draft. Dump'ni tiklagandan keyin bu bosqichda **hech narsa qilish shart
emas**, faqat tekshir:

Tekshiruv:

```bash
docker compose -f docker-compose.prod.yml exec -T db psql -U bilim -d bilim -c \
  "SELECT status, count(*) FROM questions GROUP BY status;"
```

---

## 7 — nginx + TLS

```bash
sudo cp deploy/proxy_params_bilim /etc/nginx/proxy_params_bilim
sudo cp deploy/nginx.conf /etc/nginx/sites-available/bilim
sudo sed -i 's/__DOMAIN__/api.MISOL.uz/g' /etc/nginx/sites-available/bilim
sudo ln -sf /etc/nginx/sites-available/bilim /etc/nginx/sites-enabled/bilim
sudo rm -f /etc/nginx/sites-enabled/default
```

Sertifikat olishdan oldin 443 blokini vaqtincha izohga ol (sertifikat hali yo'q,
nginx start bo'lmaydi), keyin:

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.MISOL.uz
# 443 blokini izohdan chiqar, yo'llar certbot yozganiga mos ekanini tekshir
sudo nginx -t && sudo systemctl reload nginx
```

DNS A-yozuvi VPS IP'siga ishora qilmasa, certbot ishlamaydi — avval DNS.

Tashqaridan tekshir:

```bash
curl -s https://api.MISOL.uz/health
curl -s https://api.MISOL.uz/v1/announcements
curl -s -o /dev/null -w '%{http_code}\n' https://api.MISOL.uz/docs   # 404 bo'lsin
curl -s https://api.MISOL.uz/v1/admin/analytics -H "X-Admin-Key: <kalit>" | head -c 300
```

---

## 8 — Zaxira (bugun, ertaga emas)

```bash
./scripts/backup.sh              # qo'lda bir marta — ishlashini ko'r
crontab -e
# 0 3 * * * cd /opt/bilim/backend && ./scripts/backup.sh >> /var/log/bilim-backup.log 2>&1
```

Skript dump'ni yozgach `pg_restore -l` bilan **o'qib ko'radi** — chala fayl
zaxira deb hisoblanmaydi. Serverning o'zidagi nusxa zaxira emas: haftada bir
marta tashqariga ko'chir (`backup.sh` oxiridagi izohga qara).

---

## 9 — Flutter release

```powershell
cd "D:\platform edu\mobile"
flutter gen-l10n
flutter analyze
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.MISOL.uz
```

`AndroidManifest.xml` dan `android:usesCleartextTraffic="true"` ni olib tashla —
endi hamma narsa HTTPS.

---

## 10 — Ishga tushgandan keyingi birinchi hafta

Har kuni bir marta:

```bash
curl -s https://api.MISOL.uz/v1/admin/analytics -H "X-Admin-Key: <kalit>"
```

- `retention.d1` — eng muhim raqam. 20%+ yaxshi start; 5% bo'lsa mahsulot emas,
  quyilgan chelak. `cohorts_counted` 0 bo'lsa hali yetilgan kohort yo'q.
- `suspect_questions` — 20+ urinish, <15% to'g'ri. Bular odatda qiyin savol
  emas, **buzuq savol**. `has_media: true` bo'lsa sabab aniq: rasm ko'rsatilmayapti.
- `subjects` — talab qaysi fanda. Kontent kuchini shunga yo'nalt.
- `timeseries` — o'sish haqiqiymi yoki bir martalik spike.

---

## Tez yordam

| Alomat | Sabab | Yechim |
|---|---|---|
| api konteyner qayta-qayta o'chadi | guard qanoatlanmagan | `logs api` → `insecure configuration:` satrini o'qi |
| `getaddrinfo failed` | `DATABASE_URL` hosti | konteyner ichida `db`, hostdan `127.0.0.1` |
| 502 Bad Gateway | api ko'tarilmagan | `ps` → api healthy'mi; `curl 127.0.0.1:8000/health` |
| OTP kelmayapti | Eskiz shabloni tasdiqlanmagan | Eskiz kabinetida moderatsiya holatini ko'r |
| Hamma IP bir xil ko'rinadi | proxy header | `TRUST_PROXY_HEADERS=true` + proxy_params joyidami |
| 429 juda erta | nginx `limit_req` | `nginx.conf` dagi `rate=` ni oshir |

**Orqaga qaytarish:** `docker compose -f docker-compose.prod.yml down` →
oldingi kodga qayt → `up -d --build`. Bazani orqaga qaytarish uchun eng oxirgi
`backups/*.dump` ni tikla (buyruq `backup.sh` oxirida).
