from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Topag'on"
    environment: str = "dev"

    database_url: str = "postgresql+asyncpg://edu:edu@localhost:5432/edu"
    redis_url: str = "redis://localhost:6379/0"

    jwt_secret: str = "change-me-in-prod"
    jwt_access_ttl_seconds: int = 15 * 60
    jwt_refresh_ttl_seconds: int = 30 * 24 * 3600

    default_lang: str = "uz-Latn"
    cors_origins: str = "*"

    otp_ttl_seconds: int = 5 * 60          # code lifetime
    otp_length: int = 6
    otp_max_attempts: int = 5             
    otp_request_cooldown_seconds: int = 60 
    otp_request_daily_cap: int = 20      
    otp_ip_hourly_cap: int = 15            
    otp_ip_daily_cap: int = 60            
    trust_proxy_headers: bool = False
    otp_debug_return: bool = True

    sms_provider: str = "console"
    otp_message_template: str = "Topag'on tasdiqlash kodi: {code}"
    eskiz_base_url: str = "https://notify.eskiz.uz/api"
    eskiz_email: str = ""
    eskiz_password: str = ""
    eskiz_from: str = "4546"              

   #gamification
    xp_per_point: int = 10                 
    xp_per_level: int = 100                
    coins_per_correct: int = 5            
    coins_per_wrong_penalty: int = 1       
    coins_daily_login: int = 10           
    coins_per_ad: int = 15                
    ads_per_day_cap: int = 3              
    allow_client_ad_rewards: bool = True

    admin_api_key: str = ""
    challenge_ttl_hours: int = 24         
    challenge_max_stake: int = 500
    challenge_max_questions: int = 20
    guest_user_id: str = "00000000-0000-0000-0000-000000000001"

    invite_login_enabled: bool = True
    invite_ip_hourly_cap: int = 10         

    require_invite_for_password_register: bool = True
    telegram_login_enabled: bool = False
    telegram_bot_token: str = ""
    telegram_bot_username: str = ""
    telegram_webhook_secret: str = ""
    telegram_login_ttl_seconds: int = 600  # nonce yashash muddati
    telegram_api_base: str = "https://api.telegram.org"
    #   curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
    telegram_admin_chat_id: int = 0

   #parent linking
    link_code_ttl_seconds: int = 10 * 60

    @property
    def is_prod(self) -> bool:
        return self.environment.lower() in ("prod", "production")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def validate_runtime(self) -> list[str]:
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
