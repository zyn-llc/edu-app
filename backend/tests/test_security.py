"""Token + password primitives — the trust boundary, so tested directly."""
from datetime import datetime, timedelta, timezone

import pytest

from app.core import security


def test_access_token_roundtrip():
    tok = security.create_access_token("u-123", "student")
    claims = security.decode_access_token(tok)
    assert claims["sub"] == "u-123"
    assert claims["role"] == "student"
    assert claims["type"] == "access"


def test_expired_access_token_rejected():
    past = datetime.now(timezone.utc) - timedelta(hours=1)
    tok = security.create_access_token("u-1", "student", now=past)
    with pytest.raises(security.TokenError):
        security.decode_access_token(tok)


def test_tampered_token_rejected():
    tok = security.create_access_token("u-1", "student")
    with pytest.raises(security.TokenError):
        security.decode_access_token(tok + "x")


def test_refresh_token_is_opaque_and_hashable():
    raw = security.new_refresh_token()
    assert len(raw) > 40
    h1 = security.hash_token(raw)
    h2 = security.hash_token(raw)
    assert h1 == h2 and h1 != raw and len(h1) == 64  # sha256 hex


def test_password_hash_and_verify():
    h = security.hash_password("correct horse battery staple")
    assert security.verify_password("correct horse battery staple", h)
    assert not security.verify_password("wrong", h)
