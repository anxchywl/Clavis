from __future__ import annotations

from pathlib import Path

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


def _book(client: TestClient, hour: int, key: str) -> str:
    response = client.post(
        "/api/v1/bookings",
        json={"slotId": slot(21, hour)},
        headers={**bearer(STUDENT_TOKEN), "Idempotency-Key": key},
    )
    assert response.status_code == 201
    booking_id: str = response.json()["data"]["id"]
    return booking_id


def test_operator_routes_refuse_a_student(client: TestClient) -> None:
    for method, path, body in [
        ("GET", "/api/v1/operator/weeks/2026-09-21/bookings", None),
        ("POST", "/api/v1/operator/bookings/x/attendance", {"status": "completed"}),
        ("PUT", "/api/v1/operator/students/student-a/weekly-limit", {"limit": 1}),
    ]:
        response = client.request(
            method, path, json=body, headers=bearer(STUDENT_TOKEN)
        )
        assert response.status_code == 403, path
        assert response.json()["error"]["code"] == "operator_required"


def test_an_operator_sees_who_booked(client: TestClient) -> None:
    booking_id = _book(client, 10, "request-key-0001")
    response = client.get(
        "/api/v1/operator/weeks/2026-09-21/bookings",
        headers=bearer(OPERATOR_TOKEN),
    )
    assert response.status_code == 200
    [booking] = response.json()["data"]
    assert (booking["id"], booking["subject"]) == (booking_id, "student-a")


def test_a_penalty_lowers_the_limit_until_an_operator_restores_it(
    client: TestClient,
) -> None:
    path = "/api/v1/operator/students/student-a/weekly-limit"
    lowered = client.put(path, json={"limit": 1}, headers=bearer(OPERATOR_TOKEN))
    assert lowered.json()["data"] == {"subject": "student-a", "limit": 1}

    _book(client, 10, "request-key-0001")
    refused = client.post(
        "/api/v1/bookings",
        json={"slotId": slot(21, 11)},
        headers={**bearer(STUDENT_TOKEN), "Idempotency-Key": "request-key-0002"},
    )
    assert refused.json()["error"]["code"] == "quota_exceeded"
    week = client.get("/api/v1/weeks/2026-09-21", headers=bearer(STUDENT_TOKEN))
    assert week.json()["data"]["quota"] == {"booked": 1, "limit": 1, "defaultLimit": 2}

    too_high = client.put(path, json={"limit": 3}, headers=bearer(OPERATOR_TOKEN))
    assert too_high.status_code == 422
    assert too_high.json()["error"]["code"] == "weekly_limit_invalid"


def test_attendance_waits_for_the_slot_and_then_sticks(tmp_path: Path) -> None:
    database = str(tmp_path / "clavis.sqlite3")

    def started(day: int, hour: int) -> TestClient:
        configured = settings(
            **development_env(
                DATABASE_PATH=database,
                DEVELOPMENT_CLOCK=almaty(day, hour).isoformat(),
            )
        )
        return TestClient(create_app(configured), raise_server_exceptions=False)

    with started(20, 21) as client:
        booking_id = _book(client, 10, "request-key-0001")
        early = client.post(
            f"/api/v1/operator/bookings/{booking_id}/attendance",
            json={"status": "no_show"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert early.json()["error"]["code"] == "attendance_too_early"

    with started(21, 11) as client:
        marked = client.post(
            f"/api/v1/operator/bookings/{booking_id}/attendance",
            json={"status": "no_show"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert marked.json()["data"]["status"] == "no_show"
        repeated = client.post(
            f"/api/v1/operator/bookings/{booking_id}/attendance",
            json={"status": "no_show"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert repeated.status_code == 200
        changed = client.post(
            f"/api/v1/operator/bookings/{booking_id}/attendance",
            json={"status": "completed"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert changed.json()["error"]["code"] == "booking_not_confirmed"
        missing = client.post(
            "/api/v1/operator/bookings/no-such-booking/attendance",
            json={"status": "completed"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert missing.status_code == 404
        # released is not an attendance outcome
        wrong = client.post(
            f"/api/v1/operator/bookings/{booking_id}/attendance",
            json={"status": "released"},
            headers=bearer(OPERATOR_TOKEN),
        )
        assert wrong.status_code == 422
