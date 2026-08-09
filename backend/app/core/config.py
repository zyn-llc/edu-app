from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # OpenAPI sarlavhasida va /health javobida ko'rinadi.
    app_name: str = "Topag'on"
    environment: str = "dev"

    database_url: str = "postgresql+asyncpg://edu:edu@localhost:5432/edu"
    redis_url: str = "redis://localhost:6379/0"

    jwt_secret: str = "change-me-in-prod"
    jwt_access_ttl_seconds: int = 15 * 60
    jwt_refresh_ttl_seconds: int = 30 * 24 * 3600

    default_lang: str = "uz-Latn"

    # CORS — origins allowed to call the API from a browser (Flutter Web, landing
    # page). Comma-separated in env. Dev default is permissive for localhost; prod
    # MUST list explicit origins (see validate_runtime).
    cors_origins: str = "*"

    # --- OTP (phone auth) ---------------------------------------------------
    otp_ttl_seconds: int = 5 * 60          # code lifetime
    otp_length: int = 6
    otp_max_attempts: int = 5              # wrong tries before the code is burned
    otp_request_cooldown_seconds: int = 60  # min gap between code requests per phone
    otp_request_daily_cap: int = 20        # max code requests per phone per rolling day
    # Per-IP caps — SMS-pumping / enumeration protection. An attacker who rotates
    # phone numbers bypasses the per-phone caps entirely; every accepted request
    # costs real money at the SMS gateway. These bound the damage per source IP.
    otp_ip_hourly_cap: int = 15            # max code requests per IP per hour
    otp_ip_daily_cap: int = 60             # max code requests per IP per rolling day
    # Set true only when the API runs behind a trusted reverse proxy (nginx/
    # Cloudflare) that overwrites X-Forwarded-For. If false, the header is ignored
    # (a direct client could spoof it to dodge the IP caps).
    trust_proxy_headers: bool = False
    # In dev there is no SMS gateway, so the code is returned in the API response
    # (and logged). MUST be false in prod — overridden by env.
    otp_debug_return: bool = True

    # --- SMS gateway --------------------------------------------------------
    # 'console' (dev, faqat logga yozadi) | 'eskiz' (real SMS)
    # | 'disabled' (telefon+OTP kirish butunlay yopiq — Eskiz tayyor bo'lmaganda
    #   taklif kodi va/yoki Telegram orqali kiriladi).
    sms_provider: str = "console"
    # DIQQAT: Eskiz shabloni MODERATSIYADAN o'tgan matn bilan AYNAN mos
    # bo'lishi shart. Bu satrni o'zgartirsang, Eskiz kabinetida shablonni ham
    # yangilab, qayta tasdiqlatish kerak — aks holda SMS yetkazilmaydi.
    otp_message_template: str = "Topag'on tasdiqlash kodi: {code}"
    eskiz_base_url: str = "https://notify.eskiz.uz/api"
    eskiz_email: str = ""
    eskiz_password: str = ""
    eskiz_from: str = "4546"               # Eskiz test sender; replace once approved

    # --- Gamification / ranking --------------------------------------------
    xp_per_point: int = 10                 # xp awarded = score * this
    xp_per_level: int = 100                # level = 1 + xp // xp_per_level
    coins_per_correct: int = 5             # coins minted on first correct answer
    # --- coin economy v2 (gentle by design) ---
    coins_per_wrong_penalty: int = 1       # deducted per wrong answer, floored at 0
    coins_daily_login: int = 10            # first activity of the day
    coins_per_ad: int = 15                 # per rewarded-ad view
    ads_per_day_cap: int = 3               # max rewarded ads credited per day
    # Dev stub: /ad-reward credits coins on the client's word (no ad shown).
    # Prod boot REFUSES while true — flip only after AdMob SSV is implemented.
    allow_client_ad_rewards: bool = True
    # Admin stats endpoint auth. Empty = endpoint disabled (404).
    admin_api_key: str = ""
    # --- challenges (friend bets in coins) ---
    challenge_ttl_hours: int = 24          # open/unfinished challenges expire+refund
    challenge_max_stake: int = 500
    challenge_max_questions: int = 20
    # Guest user (pre-auth practice) — excluded from leaderboards.
    guest_user_id: str = "00000000-0000-0000-0000-000000000001"

    # --- Alternativ kirish yo'llari (Eskiz tayyor bo'lmaganda) --------------
    # Taklif kodi: telefonsiz akkaunt. Yopiq beta uchun.
    invite_login_enabled: bool = True
    invite_ip_hourly_cap: int = 10         # bir IP'dan soatiga kod urinishi

    # 2026-08-07: nom+parol bilan RO'YXATDAN O'TISH (login emas!) taklif
    # kodi talab qiladi. SABAB — bu yo'l hech qanday tashqi tekshiruvga
    # bog'liq emas (SMS ham, Telegram ham yo'q), ya'ni cheklovi faqat IP
    # bo'yicha soatiga 40 ta so'rov edi: skript proksi bilan istalgancha
    # soxta hisob ocha oladi, Telegram yo'lidagi kabi "haqiqiy odam"
    # barrieri yo'q. Yopiq beta davrida bu yoqilgan turadi: faqat 30
    # sinovchiga berilgan kod bilan ro'yxatdan o'tish mumkin. Ommaviy
    # ishga tushirilgandan keyin `false` qilinadi. Parol bilan KIRISH
    # (login, mavjud hisob) bunga bog'liq emas — u doim ochiq.
    require_invite_for_password_register: bool = True
    # Telegram: bot /start <nonce> qabul qiladi, ilova nonce'ni so'rab turadi.
    telegram_login_enabled: bool = False
    telegram_bot_token: str = ""           # @BotFather bergan token
    telegram_bot_username: str = ""        # '@' siz, deep link uchun
    telegram_webhook_secret: str = ""      # webhook'ni faqat Telegram chaqirsin
    telegram_login_ttl_seconds: int = 600  # nonce yashash muddati
    telegram_api_base: str = "https://api.telegram.org"
    # Murojaatlar shu chatga yuboriladi (shaxsiy chat yoki guruh ID si).
    # 0 bo'lsa yuborilmaydi — faqat bazaga yoziladi.
    # ID ni bilish: botga xabar yozing, keyin
    #   curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
    # javobidagi `message.chat.id` ni oling. Guruh ID si manfiy bo'ladi.
    telegram_admin_chat_id: int = 0

    # --- Parent linking -----------------------------------------------------
    link_code_ttl_seconds: int = 10 * 60

    @property
    def is_prod(self) -> bool:
        return self.environment.lower() in ("prod", "production")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def validate_runtime(self) -> list[str]:
        """Refuse to run with insecure config in prod. Returns a list of fatal
        problems (empty == ok). Called at startup; see app.main.lifespan.

        These are deploy-time foot-guns the Security/DevOps standard says we must
        not ship: a guessable/short signing key, or OTP codes leaking in API
        responses. In dev they're warnings; in prod they're hard failures.
        """
        problems: list[str] = []
        if self.is_prod:
            if self.jwt_secret == "change-me-in-prod" or len(self.jwt_secret) < 32:
                problems.append(
                    "JWT_SECRET must be set to a unique value of >=32 bytes in prod")
            if self.otp_debug_return:
                problems.append("OTP_DEBUG_RETURN must be false in prod")
            if "edu:edu@" in self.database_url:
                problems.append("default DB credentials must not be used in prod")
            if self.cors_origins.strip() == "*":
                problems.append(
                    "CORS_ORIGINS must list explicit origins in prod, not '*'")
            if self.sms_provider == "console":
                problems.append(
                    "SMS_PROVIDER must be a real gateway (e.g. eskiz) in prod, "
                    "or 'disabled' if phone login is intentionally off — "
                    "'console' only logs the code and never delivers it")
            if self.sms_provider == "disabled" and not (
                    self.invite_login_enabled or self.telegram_login_enabled):
                problems.append(
                    "SMS_PROVIDER=disabled leaves no way to sign in: enable "
                    "INVITE_LOGIN_ENABLED or TELEGRAM_LOGIN_ENABLED")
            if self.telegram_login_enabled and not (
                    self.telegram_bot_token and self.telegram_bot_username):
                problems.append(
                    "TELEGRAM_LOGIN_ENABLED requires TELEGRAM_BOT_TOKEN and "
                    "TELEGRAM_BOT_USERNAME")
            if self.telegram_login_enabled and not self.telegram_webhook_secret:
                problems.append(
                    "TELEGRAM_WEBHOOK_SECRET must be set in prod: without it "
                    "anyone who finds the webhook URL can forge logins")
            if self.sms_provider == "eskiz" and not (
                    self.eskiz_email and self.eskiz_password):
                problems.append("ESKIZ_EMAIL and ESKIZ_PASSWORD must be set in prod")
            if self.allow_client_ad_rewards:
                problems.append(
                    "ALLOW_CLIENT_AD_REWARDS must be false in prod: the "
                    "/ad-reward endpoint currently trusts the client (dev stub "
                    "— no ad is actually shown). Ship AdMob + server-side "
                    "verification first, or consciously re-enable knowing "
                    "every user can mint coins_per_ad × ads_per_day_cap coins "
                    "per day with one HTTP call.")
        return problems


@lru_cache
def get_settings() -> Settings:
    return Settings()
