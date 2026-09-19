from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi import APIRouter
from fastapi.testclient import TestClient

from app.config import AppEnvironment
from app.domain.errors import NotFoundError
from app.main import create_app
from tests.conftest import settings

probe = APIRouter()


@probe.get("/api/v1/boom")
async def _boom() -> None:
    raise RuntimeError("an internal detail that must not escape")


@probe.get("/api/v1/missing")
async def _missing() -> None:
    raise NotFoundError("thing_not_found", "No such thing.")


@probe.post("/api/v1/echo")
async def _echo() -> dict[str, str]:
    return {"status": "ok"}


@pytest.fixture
def client() -> Iterator[TestClient]:
    application = create_app(settings(REQUEST_BODY_MAX_BYTES=1024))
    application.include_router(probe)
    with TestClient(application, raise_server_exceptions=False) as test_client:
        yield test_client


def test_documentation_is_off_by_default(client: TestClient) -> None:
    assert client.get("/documentation").status_code == 404
    assert client.get("/openapi.json").status_code == 404


def test_liveness_reports_a_request_id(client: TestClient) -> None:
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["data"]["status"] == "ok"
    assert response.headers["X-Request-ID"]


def test_security_headers_are_present(client: TestClient) -> None:
    headers = client.get("/health/live").headers
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["Referrer-Policy"] == "no-referrer"


def test_api_responses_are_not_cached(client: TestClient) -> None:
    response = client.get("/api/v1/missing")
    assert response.headers["Cache-Control"] == "private, no-store"


def test_hsts_only_in_production(client: TestClient) -> None:
    assert "Strict-Transport-Security" not in client.get("/health/live").headers
    with TestClient(
        create_app(settings(APP_ENV=AppEnvironment.production)),
        raise_server_exceptions=False,
    ) as production:
        headers = production.get("/health/live").headers
    assert "Strict-Transport-Security" in headers


def test_a_supplied_request_id_is_echoed_when_it_is_well_formed(
    client: TestClient,
) -> None:
    response = client.get("/health/live", headers={"X-Request-ID": "abc-123"})
    assert response.headers["X-Request-ID"] == "abc-123"


def test_a_hostile_request_id_is_replaced(client: TestClient) -> None:
    hostile = "line\nbreak and spaces"
    response = client.get("/health/live", headers={"X-Request-ID": hostile})
    assert response.headers["X-Request-ID"] != hostile


def test_domain_errors_use_the_envelope(client: TestClient) -> None:
    response = client.get("/api/v1/missing")
    assert response.status_code == 404
    error = response.json()["error"]
    assert error["code"] == "thing_not_found"
    assert error["request_id"]


def test_an_unexpected_error_leaks_nothing(client: TestClient) -> None:
    response = client.get("/api/v1/boom")
    assert response.status_code == 500
    body = response.text
    assert "an internal detail" not in body
    assert "RuntimeError" not in body
    assert "Traceback" not in body
    assert response.json()["error"]["code"] == "internal_error"


def test_an_oversized_body_is_refused(client: TestClient) -> None:
    response = client.post("/api/v1/echo", content=b"x" * 2048)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_body_too_large"


def test_an_understated_content_length_does_not_bypass_the_cap(
    client: TestClient,
) -> None:
    # the declared length is a lie; the streamed count is what must decide
    response = client.post(
        "/api/v1/echo",
        content=b"x" * 2048,
        headers={"Content-Length": "10"},
    )
    assert response.status_code in {400, 413}


def test_readiness_follows_the_database(client: TestClient) -> None:
    assert client.get("/health/ready").json()["data"]["status"] == "ready"

    class Unreachable:
        async def ready(self) -> None:
            raise OSError("disk gone")

    service = client.app.state.booking_service  # type: ignore[attr-defined]
    client.app.state.booking_service = Unreachable()  # type: ignore[attr-defined]
    try:
        response = client.get("/health/ready")
    finally:
        client.app.state.booking_service = service  # type: ignore[attr-defined]
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "database_unavailable"
    assert "disk gone" not in response.text
