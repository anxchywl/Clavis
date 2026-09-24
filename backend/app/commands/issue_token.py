from __future__ import annotations

import argparse
import re
from datetime import UTC, datetime, timedelta

import jwt

from app.config import Settings, get_settings

SUBJECT = re.compile(r"^[A-Za-z0-9._@-]{1,64}$")
MAXIMUM_HOURS = 24


# a stopgap while no host app exists to sign students in: it signs with the
# shared secret the service already verifies, only on the host that holds it,
# and only for a short time. it goes when the issuer moves to a real host
def issue(
    settings: Settings,
    *,
    subject: str,
    hours: int,
    operator: bool = False,
    now: datetime,
) -> str:
    secret = settings.host_jwt_secret
    algorithm = settings.host_jwt_algorithm.upper()
    if not settings.host_auth_configured or secret is None:
        raise ValueError("host authentication is not configured")
    if not algorithm.startswith("HS"):
        raise ValueError("only a shared-secret issuer can be signed for here")
    if SUBJECT.fullmatch(subject) is None:
        raise ValueError("the subject is not a valid student id")
    if not 1 <= hours <= MAXIMUM_HOURS:
        raise ValueError(f"a token lasts between 1 and {MAXIMUM_HOURS} hours")
    claims: dict[str, object] = {
        "sub": subject,
        "iss": settings.host_jwt_issuer,
        "iat": now,
        "exp": now + timedelta(hours=hours),
    }
    if settings.host_jwt_audience:
        claims["aud"] = settings.host_jwt_audience
    if operator:
        if not settings.host_operator_claim or settings.host_operator_value is None:
            raise ValueError("no operator claim is configured")
        claims[settings.host_operator_claim] = settings.host_operator_value
    return jwt.encode(claims, secret.get_secret_value(), algorithm=algorithm)


def main(argv: list[str] | None = None, settings: Settings | None = None) -> None:
    parser = argparse.ArgumentParser(description="Issue a short-lived token.")
    parser.add_argument("--subject", required=True)
    parser.add_argument("--hours", type=int, default=12)
    parser.add_argument("--operator", action="store_true")
    arguments = parser.parse_args(argv)
    try:
        token = issue(
            settings or get_settings(),
            subject=arguments.subject,
            hours=arguments.hours,
            operator=arguments.operator,
            now=datetime.now(UTC),
        )
    except ValueError as error:
        parser.error(str(error))
    # stdout carries the token alone, so a caller can capture it unseen
    print(token)


if __name__ == "__main__":  # pragma: no cover
    main()
