from __future__ import annotations

from datetime import UTC, datetime

import jwt
import pytest

from app.commands.issue_token import issue, main
from app.config import Settings
from app.infrastructure.auth import create_principal_resolver
from tests.conftest import HOST_AUDIENCE, HOST_ISSUER, settings

SECRET = "s" * 40
NOW = datetime.now(UTC)


def _host(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "HOST_JWT_ISSUER": HOST_ISSUER,
        "HOST_JWT_AUDIENCE": HOST_AUDIENCE,
        "HOST_JWT_ALGORITHM": "HS256",
        "HOST_JWT_SECRET": SECRET,
        "HOST_OPERATOR_CLAIM": "role",
        "HOST_OPERATOR_VALUE": "clavis-operator",
        **overrides,
    }
    return settings(**values)


async def test_an_issued_token_is_one_the_service_accepts() -> None:
    configured = _host()
    resolver = create_principal_resolver(configured)

    student = await resolver.resolve(
        issue(configured, subject="student-a", hours=12, now=NOW)
    )
    operator = await resolver.resolve(
        issue(configured, subject="operator-a", hours=1, operator=True, now=NOW)
    )

    assert (student.external_subject, student.is_operator) == ("student-a", False)
    assert (operator.external_subject, operator.is_operator) == ("operator-a", True)


def test_a_token_expires_when_it_says() -> None:
    token = issue(_host(), subject="student-a", hours=2, now=NOW)
    claims = jwt.decode(token, SECRET, algorithms=["HS256"], audience=HOST_AUDIENCE)
    assert claims["exp"] - claims["iat"] == 2 * 3600


@pytest.mark.parametrize(
    ("configured", "arguments", "message"),
    [
        (settings(), {}, "not configured"),
        (_host(), {"subject": "has spaces"}, "valid student id"),
        (_host(), {"subject": "a;rm -rf"}, "valid student id"),
        (_host(), {"hours": 0}, "between 1 and 24"),
        (_host(), {"hours": 25}, "between 1 and 24"),
        (
            _host(HOST_OPERATOR_CLAIM="", HOST_OPERATOR_VALUE=""),
            {"operator": True},
            "no operator claim",
        ),
    ],
)
def test_a_token_is_refused_rather_than_issued_loosely(
    configured: Settings,
    arguments: dict[str, object],
    message: str,
) -> None:
    options: dict[str, object] = {"subject": "student-a", "hours": 12, **arguments}
    with pytest.raises(ValueError, match=message):
        issue(configured, now=NOW, **options)  # type: ignore[arg-type]


def test_an_asymmetric_issuer_is_never_signed_for_here() -> None:
    configured = _host().model_copy(update={"host_jwt_algorithm": "RS256"})
    with pytest.raises(ValueError, match="shared-secret"):
        issue(configured, subject="student-a", hours=1, now=NOW)


def test_the_command_prints_only_the_token(
    capsys: pytest.CaptureFixture[str],
) -> None:
    main(["--subject", "student-a", "--hours", "1"], settings=_host())
    output = capsys.readouterr().out.strip()
    assert output.count(".") == 2
    assert "\n" not in output
    with pytest.raises(SystemExit):
        main(["--subject", "student-a", "--hours", "99"], settings=_host())
