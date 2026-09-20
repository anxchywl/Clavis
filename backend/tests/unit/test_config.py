from __future__ import annotations

from pathlib import Path

import pytest
from pydantic import ValidationError as PydanticValidationError

from app.config import AppEnvironment, AuthAdapter, Settings
from tests.conftest import settings


def test_environment_defaults_to_production(monkeypatch: pytest.MonkeyPatch) -> None:
    # an omitted APP_ENV must fail closed, never open a development path. the
    # variable is cleared because ci sets it, and a default is only a default
    # when nothing else supplies the value
    monkeypatch.delenv("APP_ENV", raising=False)

    built = Settings.model_validate({})

    assert built.environment is AppEnvironment.production


def test_development_auth_is_refused_in_production() -> None:
    with pytest.raises(PydanticValidationError, match="cannot run in production"):
        settings(
            APP_ENV=AppEnvironment.production,
            AUTH_ADAPTER=AuthAdapter.development,
            DEVELOPMENT_AUTH_TOKEN="a-token",
            DEVELOPMENT_OPERATOR_AUTH_TOKEN="another-token",
        )


def test_development_auth_requires_both_tokens() -> None:
    with pytest.raises(PydanticValidationError, match="DEVELOPMENT_AUTH_TOKEN"):
        settings(AUTH_ADAPTER=AuthAdapter.development)
    with pytest.raises(
        PydanticValidationError, match="DEVELOPMENT_OPERATOR_AUTH_TOKEN"
    ):
        settings(AUTH_ADAPTER=AuthAdapter.development, DEVELOPMENT_AUTH_TOKEN="a-token")


def test_student_and_operator_tokens_must_differ() -> None:
    with pytest.raises(PydanticValidationError, match="must differ"):
        settings(
            AUTH_ADAPTER=AuthAdapter.development,
            DEVELOPMENT_AUTH_TOKEN="same-token",
            DEVELOPMENT_OPERATOR_AUTH_TOKEN="same-token",
        )


def test_api_documentation_is_refused_in_production() -> None:
    with pytest.raises(
        PydanticValidationError, match="cannot be enabled in production"
    ):
        settings(APP_ENV=AppEnvironment.production, API_DOCS_ENABLED=True)


def test_wildcard_cors_origin_is_refused() -> None:
    with pytest.raises(PydanticValidationError, match="wildcard CORS"):
        settings(CORS_ALLOWED_ORIGINS="*")


@pytest.mark.parametrize(
    "origin",
    [
        "https://example.edu/path",
        "https://example.edu?q=1",
        "https://user:pass@example.edu",
        "ftp://example.edu",
        "not-a-url",
    ],
)
def test_malformed_cors_origins_are_refused(origin: str) -> None:
    with pytest.raises(PydanticValidationError, match="CORS origins"):
        settings(CORS_ALLOWED_ORIGINS=origin)


def test_plain_http_cors_origin_is_refused_in_production() -> None:
    with pytest.raises(PydanticValidationError, match="HTTPS in production"):
        settings(
            APP_ENV=AppEnvironment.production,
            CORS_ALLOWED_ORIGINS="http://example.edu",
        )


def test_request_body_limit_is_bounded() -> None:
    with pytest.raises(PydanticValidationError):
        settings(REQUEST_BODY_MAX_BYTES=1)


def test_host_auth_needs_both_an_issuer_and_a_key() -> None:
    # half a configuration must leave the host resolver closed, not open
    issuer_only = settings(HOST_JWT_ISSUER="https://host.example.edu")
    key_only = settings(HOST_JWT_SECRET="s" * 32)

    assert issuer_only.host_auth_configured is False
    assert key_only.host_auth_configured is False


def test_an_unlisted_signing_algorithm_is_refused() -> None:
    for algorithm in ("none", "NONE", "PS256"):
        with pytest.raises(PydanticValidationError, match="not an allowed algorithm"):
            settings(
                HOST_JWT_ISSUER="https://host.example.edu",
                HOST_JWT_ALGORITHM=algorithm,
                HOST_JWT_SECRET="s" * 32,
            )


def test_a_public_key_cannot_be_used_as_an_hmac_secret() -> None:
    with pytest.raises(PydanticValidationError, match="cannot be used with an HS"):
        settings(
            HOST_JWT_ISSUER="https://host.example.edu",
            HOST_JWT_ALGORITHM="HS256",
            HOST_JWT_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----",
        )


def test_a_short_shared_secret_is_refused() -> None:
    with pytest.raises(PydanticValidationError, match="at least 32 bytes"):
        settings(
            HOST_JWT_ISSUER="https://host.example.edu",
            HOST_JWT_ALGORITHM="HS256",
            HOST_JWT_SECRET="too-short",
        )


def test_an_asymmetric_algorithm_requires_a_public_key() -> None:
    with pytest.raises(PydanticValidationError, match="PUBLIC_KEY is required"):
        settings(
            HOST_JWT_ISSUER="https://host.example.edu",
            HOST_JWT_ALGORITHM="RS256",
            HOST_JWT_SECRET="s" * 32,
        )


def test_an_operator_claim_and_its_value_are_set_together() -> None:
    with pytest.raises(PydanticValidationError, match="together or not at all"):
        settings(
            HOST_JWT_ISSUER="https://host.example.edu",
            HOST_JWT_ALGORITHM="HS256",
            HOST_JWT_SECRET="s" * 32,
            HOST_OPERATOR_CLAIM="role",
        )


# the environment is the path production uses, and it is decoded differently
# from keyword arguments: a list field arrives as json unless told otherwise
def test_an_empty_origin_list_from_the_environment_starts_the_service(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "")

    assert Settings.model_validate({}).cors_allowed_origins == []


def test_origins_from_the_environment_are_split_on_commas(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://a.example, https://b.example")

    built = Settings.model_validate({})

    assert built.cors_allowed_origins == ["https://a.example", "https://b.example"]


def test_a_wildcard_origin_from_the_environment_is_still_refused(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "*")

    # the guard must hold on the path production takes, not only on keywords
    with pytest.raises(PydanticValidationError):
        Settings.model_validate({})


# the file a server copies must produce a service that starts. two deployments
# crash-loops on values that are present but empty in exactly this file, and
# tests that build settings from keywords would never notice
def test_the_shipped_production_example_starts_the_service(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    example = Path(__file__).parents[3] / "deploy" / "production.env.example"
    for line in example.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        monkeypatch.setenv(key, value)

    # the operator supplies these before preflight will pass; everything else
    # is whatever the example ships, empty values included
    monkeypatch.setenv("HOST_JWT_ISSUER", "https://issuer.example")
    monkeypatch.setenv("HOST_JWT_ALGORITHM", "HS256")
    monkeypatch.setenv("HOST_JWT_SECRET", "s" * 40)

    built = Settings.model_validate({})

    assert built.environment is AppEnvironment.production
    assert built.auth_adapter is AuthAdapter.host
    assert built.cors_allowed_origins == []
    assert built.development_clock is None


def test_a_development_clock_is_refused_in_production() -> None:
    with pytest.raises(PydanticValidationError, match="DEVELOPMENT_CLOCK"):
        settings(
            APP_ENV=AppEnvironment.production,
            DEVELOPMENT_CLOCK="2026-09-20T21:15:00+05:00",
        )


def test_a_development_clock_needs_an_offset() -> None:
    with pytest.raises(PydanticValidationError, match="UTC offset"):
        settings(DEVELOPMENT_CLOCK="2026-09-20T21:15:00")


def test_an_empty_development_clock_from_the_environment_means_the_real_one(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("DEVELOPMENT_CLOCK", "")

    assert Settings.model_validate({}).development_clock is None
