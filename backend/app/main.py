import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.auth import router as auth_router
from app.api.v1.content import router as content_router
from app.api.v1.leaderboard import router as leaderboard_router
from app.api.v1.parent import router as parent_router
from app.api.v1.challenges import router as challenges_router
from app.api.v1.coins import router as coins_router
from app.api.v1.admin import router as admin_router
from app.api.v1.feedback import router as feedback_router
from app.api.v1.notes import router as notes_router
from app.api.v1.announcements import router as announcements_router
from app.api.v1.analytics import router as analytics_router
from app.api.v1.invites import router as invites_router
from app.api.v1.password_auth import router as password_auth_router
from app.api.v1.telegram_auth import router as telegram_router
from app.core.config import get_settings
from app.core.errors import AppError, app_error_handler
from app.core.redis import close_redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

# API'da token aynan URL yo'lida turadi:
#     POST https://api.telegram.org/bot<TOKEN>/sendMessage
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

_log = logging.getLogger("topagon")
settings = get_settings()

@asynccontextmanager
async def lifespan(_: FastAPI):
    problems = settings.validate_runtime()
    if problems:
        msg = "insecure configuration: " + "; ".join(problems)
        if settings.is_prod:
            raise RuntimeError(msg)          # fail fast — do not boot insecure in prod
        _log.warning("DEV %s", msg)          # dev: allowed, but loud
    yield
    await close_redis()

app = FastAPI(title=settings.app_name, lifespan=lifespan)

# Browser clients (Flutter Web, landing page) need CORS. Mobile (Dio) ignores it.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,   # we use Bearer tokens in a header, not cookies
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(AppError, app_error_handler)
app.include_router(content_router)
app.include_router(auth_router)
app.include_router(leaderboard_router)
app.include_router(parent_router)
app.include_router(challenges_router)
app.include_router(coins_router)
app.include_router(admin_router)
app.include_router(feedback_router)
app.include_router(notes_router)
app.include_router(announcements_router)
app.include_router(analytics_router)
app.include_router(invites_router)
app.include_router(password_auth_router)
app.include_router(telegram_router)

@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.environment}
