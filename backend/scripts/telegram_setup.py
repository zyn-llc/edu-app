"""
Telegram botni sozlash va dev rejimida ishlatish.

    python scripts/telegram_setup.py --webhook https://api.MISOL.uz/v1/telegram/webhook

    python scripts/telegram_setup.py --poll

    python scripts/telegram_setup.py --info

`handle_update` funksiyasini chaqiradi — ya'ni dev'da sinaganing prod'da
ishlaydigan kodning aynan o'zi. Prod'da --poll ISHLATMA: webhook bilan birga
ikkalasi bir vaqtda ishlamaydi.
"""
from __future__ import annotations

import argparse
import asyncio
import sys

sys.path.insert(0, ".")

import httpx                                                    # noqa: E402

from app.core.config import get_settings                        # noqa: E402
from app.core.database import SessionLocal                      # noqa: E402
from app.core.redis import close_redis                          # noqa: E402
from app.services import telegram as tg                         # noqa: E402

s = get_settings()

def _api(method: str) -> str:
    return f"{s.telegram_api_base}/bot{s.telegram_bot_token}/{method}"

def _check_token() -> None:
    if not s.telegram_bot_token:
        sys.exit("TELEGRAM_BOT_TOKEN .env da yo'q")

async def info() -> None:
    _check_token()
    async with httpx.AsyncClient(timeout=20) as c:
        me = (await c.get(_api("getMe"))).json()
        hook = (await c.get(_api("getWebhookInfo"))).json()
    print("getMe:", me.get("result", me))
    print("webhook:", hook.get("result", hook))

async def set_hook(url: str) -> None:
    _check_token()
    if not s.telegram_webhook_secret:
        sys.exit("TELEGRAM_WEBHOOK_SECRET .env da yo'q — usiz webhook o'rnatma")
    print(await tg.set_webhook(url))

async def delete_hook() -> None:
    _check_token()
    async with httpx.AsyncClient(timeout=20) as c:
        print((await c.post(_api("deleteWebhook"))).json())

async def poll() -> None:
    """Dev: getUpdates long-polling. Ctrl+C bilan to'xtatiladi."""
    _check_token()
    await delete_hook()          # webhook va polling birga ishlamaydi
    offset: int | None = None
    print("polling boshlandi — botga /start yuborib ko'r (Ctrl+C to'xtatadi)")
    try:
        async with httpx.AsyncClient(timeout=40) as c:
            while True:
                params = {"timeout": 30, "allowed_updates": '["message"]'}
                if offset is not None:
                    params["offset"] = offset
                try:
                    r = await c.get(_api("getUpdates"), params=params)
                    data = r.json()
                except Exception as e:
                    print("getUpdates xato:", e)
                    await asyncio.sleep(3)
                    continue

                for update in data.get("result", []):
                    offset = update["update_id"] + 1
                    print("update:", update.get("message", {}).get("text"))
                    async with SessionLocal() as db:
                        try:
                            await tg.handle_update(db, update)
                        except Exception as e:
                            await db.rollback()
                            print("handle_update xato:", e)
    except KeyboardInterrupt:
        print("\nto'xtatildi")
    finally:
        await close_redis()

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--webhook", type=str, help="webhook URL o'rnatish")
    ap.add_argument("--delete-webhook", action="store_true")
    ap.add_argument("--poll", action="store_true", help="dev long-polling")
    ap.add_argument("--info", action="store_true")
    a = ap.parse_args()

    if a.webhook:
        asyncio.run(set_hook(a.webhook))
    elif a.delete_webhook:
        asyncio.run(delete_hook())
    elif a.poll:
        asyncio.run(poll())
    else:
        asyncio.run(info())

if __name__ == "__main__":
    main()
