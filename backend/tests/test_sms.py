"""SMS layer: provider selection, message templating, console no-op, and the prod
config guard that refuses to boot on a dev SMS setup."""
import asyncio

from app.core.config import Settings
from app.services import sms
from app.services.sms.console import ConsoleSmsProvider
from app.services.sms.eskiz import EskizSmsProvider


def test_default_provider_is_console():
    assert isinstance(sms.get_sms_provider(), ConsoleSmsProvider)


def test_render_otp_message_inserts_code():
    msg = sms.render_otp_message("123456")
    assert "123456" in msg


def test_console_send_is_noop():
    # logs only, never raises, no network
    asyncio.run(ConsoleSmsProvider().send("+998901234567", "hi 0000"))


def test_eskiz_provider_constructs_without_network():
    p = EskizSmsProvider("https://notify.eskiz.uz/api", "e@x.uz", "pw", "4546")
    assert p._token is None  # not logged in until first send


def _prod(**over):
    base = dict(
        environment="prod",
        jwt_secret="x" * 40,
        otp_debug_return=False,
        database_url="postgresql+asyncpg://u:pw@h:5432/db",
        cors_origins="https://app.bilim.uz",
        sms_provider="eskiz",
        eskiz_email="e@x.uz",
        eskiz_password="pw",
    )
    base.update(over)
    return Settings(**base)


def test_prod_clean_config_has_no_problems():
    assert _prod(allow_client_ad_rewards=False).validate_runtime() == []


def test_prod_rejects_client_trusted_ad_rewards():
    # The dev ad stub mints coins on the client's word. Prod boot must refuse
    # until AdMob server-side verification ships (or it's consciously enabled).
    problems = _prod().validate_runtime()
    assert any("ALLOW_CLIENT_AD_REWARDS" in p for p in problems)


def test_prod_rejects_console_sms():
    problems = _prod(sms_provider="console").validate_runtime()
    assert any("SMS_PROVIDER" in p for p in problems)


def test_prod_requires_eskiz_credentials():
    problems = _prod(eskiz_email="", eskiz_password="").validate_runtime()
    assert any("ESKIZ" in p for p in problems)
