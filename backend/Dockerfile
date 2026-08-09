FROM python:3.12-slim

# Loglar buferlanmasin: `docker compose logs` real vaqtda ko'rinsin, aks holda
# konteyner yiqilganda oxirgi (eng muhim) satrlar umuman chiqmay qoladi.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# curl — HEALTHCHECK uchun. `--no-install-recommends` bo'lmasa slim image
# o'nlab keraksiz paket tortadi.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# ROOT OSTIDA ISHLAMAYDI. Konteynerdagi ixtiyoriy kod bajarilishi xatosi root
# bo'lganda butun konteynerni egallaydi; oddiy foydalanuvchi bilan zarar
# /app bilan cheklanadi.
RUN useradd --create-home --uid 10001 app && chown -R app:app /app
USER app

# compose `depends_on: condition: service_healthy` ni db va redis uchun
# ishlatadi, api esa o'z holatini bildirmasdi — nginx yiqilgan konteynerga
# ham proxy qilaverardi.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1

# 2 worker — VPS'da 2 yadro bor. Bitta worker bilan bitta sekin so'rov
# (masalan katta agregat) butun API'ni to'sib turardi.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--workers", "2", "--proxy-headers", "--forwarded-allow-ips", "*"]
