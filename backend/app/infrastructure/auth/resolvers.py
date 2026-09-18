from __future__ import annotations

from hmac import compare_digest
from typing import Any

import jwt

from app.config import AuthAdapter, Settings
from app.domain.auth import AccountStatus, ExternalIdentity, TokenIdentityResolver
from app.domain.errors import UnauthorizedError


# rejects every token on purpose, replace it rather than fall back to development
class UnavailableHostPrincipalResolver:
    async def resolve(self, token: str) -> ExternalIdentity:
        raise UnauthorizedError(
            "host_auth_unconfigured",
            "The host authentication adapter is not configured.",
        )


# verifies what the host issued; it never mints, refreshes or stores a token
class HostPrincipalResolver:
    def __init__(self, settings: Settings) -> None:
        issuer = settings.host_jwt_issuer
        secret = settings.host_jwt_secret
        key = settings.host_jwt_public_key or (
            secret.get_secret_value() if secret is not None else None
        )
        if not issuer or not key:
            raise ValueError("host authentication is not configured")
        self._issuer = issuer
        self._key = key
        self._audience = settings.host_jwt_audience
        self._algorithm = settings.host_jwt_algorithm.upper()
        self._subject_claim = settings.host_subject_claim
        self._operator_claim = settings.host_operator_claim
        self._operator_value = settings.host_operator_value

    async def resolve(self, token: str) -> ExternalIdentity:
        if not token:
            raise UnauthorizedError("token_missing", "Authentication is required.")

        options: dict[str, Any] = {"require": ["exp", "iss"]}
        decode: dict[str, Any] = {
            "algorithms": [self._algorithm],
            "issuer": self._issuer,
            "options": options,
        }
        # pyjwt rejects a token carrying aud when the verifier passes none, so
        # the claim is only enforced once an audience has been agreed
        if self._audience:
            decode["audience"] = self._audience
            options["require"].append("aud")
        else:
            options["verify_aud"] = False

        try:
            claims = jwt.decode(token, self._key, **decode)
        except jwt.InvalidTokenError as error:
            raise UnauthorizedError(
                "token_invalid",
                "The authentication token is not valid.",
            ) from error

        return ExternalIdentity(
            external_issuer=self._issuer,
            external_subject=self._subject_of(claims),
            account_status=AccountStatus.active,
            is_operator=self._is_operator(claims),
        )

    def _subject_of(self, claims: dict[str, Any]) -> str:
        raw = claims.get(self._subject_claim)
        # a subject that is absent, blank or absurdly long identifies nobody
        subject = "" if raw is None else str(raw).strip()
        if not subject or len(subject) > 255:
            raise UnauthorizedError(
                "token_invalid",
                "The authentication token is not valid.",
            )
        return subject

    # a role is a claim the issuer made, never one the token holder asserts, and
    # it stays false unless the configured claim matches the configured value
    def _is_operator(self, claims: dict[str, Any]) -> bool:
        if not self._operator_claim or self._operator_value is None:
            return False
        value = claims.get(self._operator_claim)
        if value is None or isinstance(value, bool):
            return False
        return compare_digest(str(value), self._operator_value)


# config refuses to build this in production
class DevelopmentPrincipalResolver:
    def __init__(self, settings: Settings) -> None:
        student = settings.development_auth_token
        operator = settings.development_operator_auth_token
        if student is None or operator is None:
            raise ValueError("development authentication tokens are missing")
        self._student_token = student.get_secret_value()
        self._operator_token = operator.get_secret_value()
        self._student_subject = settings.development_auth_subject
        self._operator_subject = settings.development_operator_auth_subject

    async def resolve(self, token: str) -> ExternalIdentity:
        is_student = bool(token) and compare_digest(token, self._student_token)
        is_operator = bool(token) and compare_digest(token, self._operator_token)
        if not is_student and not is_operator:
            raise UnauthorizedError(
                "token_invalid",
                "The development authentication token is invalid.",
            )
        return ExternalIdentity(
            external_issuer="clavis-development",
            external_subject=(
                self._operator_subject if is_operator else self._student_subject
            ),
            account_status=AccountStatus.active,
            is_operator=is_operator,
        )


def create_principal_resolver(settings: Settings) -> TokenIdentityResolver:
    if settings.auth_adapter == AuthAdapter.development:
        return DevelopmentPrincipalResolver(settings)
    if settings.host_auth_configured:
        return HostPrincipalResolver(settings)
    return UnavailableHostPrincipalResolver()
