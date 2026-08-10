"""
DSN normalizatsiyasi — ingest skriptlari uchun yagona manba.

MUAMMO: `.env` da `DATABASE_URL` hosti `db:5432` (compose servis nomi). Bu
KONTEYNER ICHIDA to'g'ri, lekin Windows hostdan `getaddrinfo failed` beradi.
Shu sababli ingest skriptlari `@db:` ni `@127.0.0.1:` ga almashtirardi.

Lekin bu almashtirish SHARTSIZ edi va aynan teskari holatda buzardi:

    docker compose exec api python -m app.ingest.audit_grading

Bu yerda `127.0.0.1` — api konteynerining o'zi, u yerda Postgres yo'q.
Prodda esa `db` porti tashqariga UMUMAN ochilmagan (`docker-compose.prod.yml`
da `ports:` yo'q), ya'ni skriptni faqat konteyner ichida ishlatish mumkin —
va aynan o'sha holatda u ishlamasdi.

YECHIM: konteyner ichida ekanligimizni aniqlaymiz (`/.dockerenv` fayli — uni
Docker har bir konteynerda yaratadi) va faqat HOSTDA turganda almashtiramiz.
"""
from __future__ import annotations

import os
import re

def in_container() -> bool:
    """Konteyner ichidamizmi.

    `/.dockerenv` — Docker'ning o'zi qo'yadigan belgi. Zaxira sifatida
    `/proc/1/cgroup` ham tekshiriladi (podman va ba'zi runtime'lar uchun).
    """
    if os.path.exists("/.dockerenv"):
        return True
    try:
        with open("/proc/1/cgroup", "rt") as f:
            return any(x in f.read() for x in ("docker", "containerd", "kubepods"))
    except OSError:
        return False

def resolve_url(url: str | None = None) -> str:
    """Ishlayotgan muhitga mos DSN qaytaradi.

    Konteyner ichida `.env` dagi qiymat o'zgarishsiz ishlatiladi.
    Hostda `db`/`localhost` -> `127.0.0.1` va SSL o'chiriladi.
    """
    if url is None:
        from app.core.config import get_settings
        url = os.environ.get("DATABASE_URL") or get_settings().database_url

    if in_container():
        return url

    url = re.sub(r"@db:", "@127.0.0.1:", url).replace("@localhost:", "@127.0.0.1:")
    # Windows/Docker: port proxy asyncpg ning SSL muzokarasini uzib qo'yishi
    if "ssl=" not in url and "127.0.0.1" in url:
        url += ("&" if "?" in url else "?") + "ssl=disable"
    return url
