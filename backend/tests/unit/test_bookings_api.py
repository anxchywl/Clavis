from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from app.main import create_app
from tests.conftest import (
    OPERATOR_TOKEN,
    STUDENT_TOKEN,
    almaty,
    bearer,
    development_env,
    settings,
    slot,
)

KEY = "request-key-0001"


def book(
    client: TestClient,
    slot_id: str,
    *,
    key: str = KEY,
    token: str = STUDENT_TOKEN,
) -> Any:
    return client.post(
        "/api/v1/bookings",
        json={"slotId": slot_id},
        headers={**bearer(token), "Idempotency-Key": key},
    )


def week(client: TestClient, token: str = STUDENT_TOKEN) -> dict[str, Any]:
    response = client.get("/api/v1/weeks/2026-09-21", headers=bearer(token))
    assert response.status_code == 200
    data: dict[str, Any] = response.json()["data"]
    return data


def slot_of(data: dict[str, Any], slot_id: str) -> dict[str, Any]:
    for day in data["days"]:
        for item in day["slots"]:
            if item["id"] == slot_id:
                found: dict[str, Any] = item
                return found
    raise AssertionError(slot_id)


def test_every_student_route_requires_a_token(client: TestClient) -> None:
    for method, path in [
        ("GET", "/api/v1/clock"),
        ("GET", "/api/v1/weeks/2026-09-21"),
        ("POST", "/api/v1/bookings"),
        ("POST", "/api/v1/bookings/any/release"),
    ]:
        response = client.request(method, path)
        assert response.status_code == 401, path
        assert response.json()["error"]["code"] == "token_missing"


def test_the_clock_is_the_servers(client: TestClient) -> None:
    response = client.get("/api/v1/clock", headers=bearer(STUDENT_TOKEN))
    assert response.json()["data"]["now"] == "2026-09-20T16:15:00Z"
    assert response.json()["meta"]["server_time"] == "2026-09-20T16:15:00Z"


def test_a_week_has_seven_days_of_thirteen_slots(client: TestClient) -> None:
    data = week(client)
    assert data["monday"] == "2026-09-21"
    assert data["timezone"] == "Asia/Almaty"
    assert data["window"] == "open"
    assert data["quota"] == {"booked": 0, "limit": 2, "defaultLimit": 2}
    assert [day["date"] for day in data["days"]][0] == "2026-09-21"
    assert all(len(day["slots"]) == 13 for day in data["days"])
    first = data["days"][0]["slots"][0]
    assert first == {
        "id": slot(21, 9),
        "start": "2026-09-21T04:00:00Z",
        "end": "2026-09-21T05:00:00Z",
        "availability": "available",
        "eligible": True,
        "bookingId": None,
    }


def test_a_week_must_start_on_monday(client: TestClient) -> None:
    response = client.get("/api/v1/weeks/2026-09-22", headers=bearer(STUDENT_TOKEN))
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "week_invalid"


def test_booking_commits_and_shows_as_own(client: TestClient) -> None:
    response = book(client, slot(21, 10))
    assert response.status_code == 201
    booking = response.json()["data"]
    assert booking["slotId"] == slot(21, 10)
    assert booking["status"] == "confirmed"
    assert "subject" not in booking

    data = week(client)
    own = slot_of(data, slot(21, 10))
    assert (own["availability"], own["bookingId"]) == ("own", booking["id"])
    assert data["quota"]["booked"] == 1
    assert [item["id"] for item in data["bookings"]] == [booking["id"]]


def test_a_retry_with_the_same_key_returns_the_same_booking(
    client: TestClient,
) -> None:
    first = book(client, slot(21, 10))
    second = book(client, slot(21, 10))
    assert second.status_code == 200
    assert second.headers["Idempotent-Replayed"] == "true"
    assert second.json()["data"]["id"] == first.json()["data"]["id"]
    assert week(client)["quota"]["booked"] == 1


def test_a_key_reused_for_another_slot_is_refused(client: TestClient) -> None:
    book(client, slot(21, 10))
    response = book(client, slot(21, 11))
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "idempotency_key_reused"


def test_a_missing_or_malformed_key_is_refused(client: TestClient) -> None:
    for key in ["", "short", "has spaces in it!!"]:
        response = book(client, slot(21, 10), key=key)
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "idempotency_key_invalid"


def test_another_students_slot_is_unavailable_and_anonymous(
    client: TestClient,
) -> None:
    book(client, slot(21, 10), token=OPERATOR_TOKEN)
    taken = slot_of(week(client), slot(21, 10))
    assert (taken["availability"], taken["bookingId"], taken["eligible"]) == (
        "unavailable",
        None,
        False,
    )
    response = book(client, slot(21, 10), key="request-key-0002")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "slot_taken"


def test_the_weekly_limit_holds(client: TestClient) -> None:
    assert book(client, slot(21, 10), key="request-key-0001").status_code == 201
    assert book(client, slot(22, 10), key="request-key-0002").status_code == 201
    response = book(client, slot(23, 10), key="request-key-0003")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "quota_exceeded"
    assert not any(
        item["eligible"] for day in week(client)["days"] for item in day["slots"]
    )


def test_an_invalid_slot_is_refused(client: TestClient) -> None:
    response = book(client, "2026-09-21T04:30:00.000Z")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "slot_invalid"
    extra = client.post(
        "/api/v1/bookings",
        json={"slotId": slot(21, 10), "studentId": "someone-else"},
        headers={**bearer(STUDENT_TOKEN), "Idempotency-Key": KEY},
    )
    assert extra.status_code == 422
    assert extra.json()["error"]["code"] == "request_validation_failed"


def test_a_closed_week_cannot_be_booked() -> None:
    closed = settings(**development_env(DEVELOPMENT_CLOCK=almaty(20, 22).isoformat()))
    with TestClient(create_app(closed), raise_server_exceptions=False) as client:
        response = book(client, slot(21, 10))
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "booking_window_closed"
        assert week(client)["window"] == "closed"


def test_release_returns_the_quota_and_repeats_safely(client: TestClient) -> None:
    booking_id = book(client, slot(21, 10)).json()["data"]["id"]
    path = f"/api/v1/bookings/{booking_id}/release"

    first = client.post(path, headers=bearer(STUDENT_TOKEN))
    again = client.post(path, headers=bearer(STUDENT_TOKEN))

    assert first.status_code == 200
    assert first.json()["data"]["status"] == "released"
    assert again.status_code == 200
    data = week(client)
    assert data["quota"]["booked"] == 0
    assert slot_of(data, slot(21, 10))["availability"] == "available"
    # the freed slot can be booked again, by anyone
    assert book(client, slot(21, 10), key="request-key-0002").status_code == 201


def test_another_students_booking_cannot_be_released(client: TestClient) -> None:
    booking_id = book(client, slot(21, 10), token=OPERATOR_TOKEN).json()["data"]["id"]
    response = client.post(
        f"/api/v1/bookings/{booking_id}/release",
        headers=bearer(STUDENT_TOKEN),
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "booking_not_found"


def test_bookings_survive_a_restart_and_release_closes_on_time(
    tmp_path: Path,
) -> None:
    database = str(tmp_path / "clavis.sqlite3")

    def started(at: datetime) -> TestClient:
        configured = settings(
            **development_env(
                DATABASE_PATH=database,
                DEVELOPMENT_CLOCK=at.isoformat(),
            )
        )
        return TestClient(create_app(configured), raise_server_exceptions=False)

    with started(almaty(20, 21, 15)) as client:
        booking_id = book(client, slot(21, 10)).json()["data"]["id"]

    # ten minutes before 10:00 is the last moment, and 09:51 is past it
    with started(almaty(21, 9, 51)) as client:
        assert week(client)["bookings"][0]["id"] == booking_id
        response = client.post(
            f"/api/v1/bookings/{booking_id}/release",
            headers=bearer(STUDENT_TOKEN),
        )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "release_deadline_passed"
