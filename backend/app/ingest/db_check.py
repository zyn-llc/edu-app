import asyncio, os

CANDIDATES = [
    ("env DATABASE_URL (bor bo'lsa)", os.environ.get("DATABASE_URL")),
    ("ssl=disable",  "postgresql+asyncpg://edu:edu@localhost:5432/edu?ssl=disable"),
    ("127.0.0.1 + ssl=disable", "postgresql+asyncpg://edu:edu@127.0.0.1:5432/edu?ssl=disable"),
    ("oddiy localhost", "postgresql+asyncpg://edu:edu@localhost:5432/edu"),
]

async def try_url(label, url):
    if not url:
        return False
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy import text
    eng = create_async_engine(url, pool_pre_ping=True)
    try:
        async with eng.connect() as c:
            n = (await c.execute(text("SELECT count(*) FROM questions"))).scalar()
            print(f"  OK   {label:<28} questions={n}")
            print(f"       URL: {url}")
            return True
    except Exception as e:
        print(f"  FAIL {label:<28} {type(e).__name__}: {str(e)[:110]}")
        return False
    finally:
        await eng.dispose()

async def main():
    print("DB ulanish diagnostikasi:\n")
    ok = []
    for label, url in CANDIDATES:
        if await try_url(label, url):
            ok.append(url)
    print()
    if ok:
        print("ISHLAYDIGAN URL topildi. Shuni ishlat:")
        print(f'  $env:DATABASE_URL = "{ok[0]}"')
        return 0
    print("Hech biri ishlamadi. Tekshir: docker ps (db up?), 5432 port band emasmi,")
    print("antivirus/firewall Docker port-proxy'ni to'smayaptimi.")
    return 1

if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
