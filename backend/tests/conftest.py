from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.config import AppEnvironment, AuthAdapter, Settings

ALMATY = ZoneInfo("Asia/Almaty")

BASE_ENV: dict[str, object] = {
    "APP_ENV": AppEnvironment.test,
    "DATABASE_PATH": ":memory:",
}

STUDENT_TOKEN = "student-token-value"
OPERATOR_TOKEN = "operator-token-value"


def settings(**overrides: object) -> Settings:
    return Settings.model_validate({**BASE_ENV, **overrides})


def almaty(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 9, day, hour, minute, tzinfo=ALMATY)


def slot(day: int, hour: int) -> str:
    return almaty(day, hour).astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")


# sunday 20 september, inside the window that opens the week of the 21st
WINDOW_OPEN = almaty(20, 21, 15)


def development_env(**overrides: object) -> dict[str, object]:
    return {
        "AUTH_ADAPTER": AuthAdapter.development,
        "DEVELOPMENT_AUTH_TOKEN": STUDENT_TOKEN,
        "DEVELOPMENT_OPERATOR_AUTH_TOKEN": OPERATOR_TOKEN,
        "DEVELOPMENT_CLOCK": WINDOW_OPEN.isoformat(),
        **overrides,
    }


@pytest.fixture
def development_settings() -> Settings:
    return settings(**development_env())


HOST_ISSUER = "https://host.example.edu"
HOST_AUDIENCE = "clavis"

# one key pair for the whole session, generating rsa material is not free
_signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def public_pem(key: rsa.RSAPrivateKey) -> str:
    return (
        key.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )


@pytest.fixture
def host_signing_key() -> rsa.RSAPrivateKey:
    return _signing_key


@pytest.fixture
def host_foreign_key() -> rsa.RSAPrivateKey:
    return _other_key


@pytest.fixture
def host_settings() -> Settings:
    return settings(
        HOST_JWT_ISSUER=HOST_ISSUER,
        HOST_JWT_AUDIENCE=HOST_AUDIENCE,
        HOST_JWT_ALGORITHM="RS256",
        HOST_JWT_PUBLIC_KEY=public_pem(_signing_key),
    )
