from __future__ import annotations

from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.config import Settings
from app.domain.errors import UnauthorizedError
from app.infrastructure.auth import create_principal_resolver
from app.infrastructure.auth.resolvers import (
    DevelopmentPrincipalResolver,
    HostPrincipalResolver,
    UnavailableHostPrincipalResolver,
)
from tests.conftest import (
    HOST_AUDIENCE,
    HOST_ISSUER,
    public_pem,
    settings,
)


async def test_host_resolver_rejects_every_token() -> None:
    resolver = create_principal_resolver(settings())
    assert isinstance(resolver, UnavailableHostPrincipalResolver)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve("any-token-at-all")


async def test_development_resolver_distinguishes_the_two_identities(
    development_settings: Settings,
) -> None:
    resolver = create_principal_resolver(development_settings)
    assert isinstance(resolver, DevelopmentPrincipalResolver)

    student = await resolver.resolve("student-token-value")
    operator = await resolver.resolve("operator-token-value")

    assert student.is_operator is False
    assert operator.is_operator is True
    assert student.external_subject != operator.external_subject


async def test_development_resolver_rejects_an_unknown_token(
    development_settings: Settings,
) -> None:
    resolver = create_principal_resolver(development_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve("not-a-configured-token")


async def test_development_resolver_rejects_an_empty_token(
    development_settings: Settings,
) -> None:
    resolver = create_principal_resolver(development_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve("")


def _token(
    key: rsa.RSAPrivateKey,
    *,
    issuer: str | None = HOST_ISSUER,
    audience: str | None = HOST_AUDIENCE,
    expires_in: int | None = 300,
    subject: object = "student-42",
    extra: dict[str, object] | None = None,
) -> str:
    claims: dict[str, object] = {}
    if subject is not None:
        claims["sub"] = subject
    if issuer is not None:
        claims["iss"] = issuer
    if audience is not None:
        claims["aud"] = audience
    if expires_in is not None:
        claims["exp"] = datetime.now(UTC) + timedelta(seconds=expires_in)
    claims.update(extra or {})
    return jwt.encode(claims, key, algorithm="RS256")


async def test_host_resolver_accepts_a_token_the_issuer_signed(
    host_settings: Settings,
    host_signing_key: rsa.RSAPrivateKey,
) -> None:
    resolver = create_principal_resolver(host_settings)
    assert isinstance(resolver, HostPrincipalResolver)

    identity = await resolver.resolve(_token(host_signing_key))

    assert identity.external_subject == "student-42"
    assert identity.external_issuer == HOST_ISSUER
    assert identity.is_operator is False


async def test_host_resolver_rejects_a_foreign_signature(
    host_settings: Settings,
    host_foreign_key: rsa.RSAPrivateKey,
) -> None:
    resolver = create_principal_resolver(host_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve(_token(host_foreign_key))


async def test_host_resolver_rejects_an_unsigned_token(
    host_settings: Settings,
) -> None:
    # the alg=none forgery: a token with no signature at all
    forged = jwt.encode(
        {
            "sub": "student-42",
            "iss": HOST_ISSUER,
            "aud": HOST_AUDIENCE,
            "exp": datetime.now(UTC) + timedelta(seconds=300),
        },
        key="",
        algorithm="none",
    )
    resolver = create_principal_resolver(host_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve(forged)


@pytest.mark.parametrize(
    "claims",
    [
        pytest.param({"issuer": "https://someone-else.example"}, id="wrong issuer"),
        pytest.param({"issuer": None}, id="no issuer"),
        pytest.param({"audience": "another-service"}, id="wrong audience"),
        pytest.param({"audience": None}, id="no audience"),
        pytest.param({"expires_in": None}, id="no expiry"),
        pytest.param({"expires_in": -30}, id="expired"),
        pytest.param({"subject": None}, id="no subject"),
        pytest.param({"subject": "   "}, id="blank subject"),
        pytest.param({"subject": "s" * 256}, id="oversized subject"),
    ],
)
async def test_host_resolver_rejects_a_token_it_cannot_trust(
    host_settings: Settings,
    host_signing_key: rsa.RSAPrivateKey,
    claims: dict[str, object],
) -> None:
    resolver = create_principal_resolver(host_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve(_token(host_signing_key, **claims))


async def test_host_resolver_rejects_an_empty_token(
    host_settings: Settings,
) -> None:
    resolver = create_principal_resolver(host_settings)
    with pytest.raises(UnauthorizedError):
        await resolver.resolve("")


async def test_a_token_cannot_claim_operator_status(
    host_settings: Settings,
    host_signing_key: rsa.RSAPrivateKey,
) -> None:
    # no operator claim is configured, so nothing in the token can grant it
    resolver = create_principal_resolver(host_settings)

    identity = await resolver.resolve(
        _token(
            host_signing_key,
            extra={"role": "operator", "is_operator": True, "operator": True},
        )
    )

    assert identity.is_operator is False


async def test_operator_status_comes_from_the_configured_claim(
    host_signing_key: rsa.RSAPrivateKey,
) -> None:
    configured = settings(
        HOST_JWT_ISSUER=HOST_ISSUER,
        HOST_JWT_AUDIENCE=HOST_AUDIENCE,
        HOST_JWT_PUBLIC_KEY=public_pem(host_signing_key),
        HOST_OPERATOR_CLAIM="role",
        HOST_OPERATOR_VALUE="clavis-operator",
    )
    resolver = create_principal_resolver(configured)

    operator = await resolver.resolve(
        _token(host_signing_key, extra={"role": "clavis-operator"})
    )
    student = await resolver.resolve(
        _token(host_signing_key, extra={"role": "clavis-operatorr"})
    )
    unstated = await resolver.resolve(_token(host_signing_key))

    assert operator.is_operator is True
    assert student.is_operator is False
    assert unstated.is_operator is False


async def test_host_resolver_verifies_a_shared_secret_token(
    host_signing_key: rsa.RSAPrivateKey,
) -> None:
    secret = "a" * 32
    configured = settings(
        HOST_JWT_ISSUER=HOST_ISSUER,
        HOST_JWT_ALGORITHM="HS256",
        HOST_JWT_SECRET=secret,
    )
    resolver = create_principal_resolver(configured)
    token = jwt.encode(
        {
            "sub": "student-7",
            "iss": HOST_ISSUER,
            "exp": datetime.now(UTC) + timedelta(seconds=300),
        },
        secret,
        algorithm="HS256",
    )

    identity = await resolver.resolve(token)

    assert identity.external_subject == "student-7"


async def test_an_unconfigured_host_stays_closed_rather_than_open() -> None:
    # no issuer and no key must not degrade into accepting anything
    resolver = create_principal_resolver(settings(HOST_JWT_ISSUER=HOST_ISSUER))
    assert isinstance(resolver, UnavailableHostPrincipalResolver)
