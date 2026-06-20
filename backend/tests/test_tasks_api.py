from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from tests.conftest import future_local_iso


@pytest.mark.integration
def test_create_event_returns_schedule_block(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=3, hour=10)
    end = future_local_iso(days=3, hour=11)

    response = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Integration Event",
            "start_time": start,
            "end_time": end,
            "priority": "Medium",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Integration Event"
    assert body["task_id"]
    assert body["_id"]


@pytest.mark.integration
def test_create_event_rejects_end_before_start(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=3, hour=11)
    end = future_local_iso(days=3, hour=10)

    response = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Bad Event",
            "start_time": start,
            "end_time": end,
            "priority": "Medium",
        },
    )

    assert response.status_code == 422


@pytest.mark.integration
def test_create_deadline_returns_task_block(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    deadline = future_local_iso(days=5, hour=17)

    response = client.post(
        "/api/v1/tasks/deadlines",
        headers=headers,
        json={
            "title": "Integration Deadline",
            "deadline": deadline,
            "estimated_minutes": 60,
            "priority": "High",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Integration Deadline"
    assert body["type"] == "Task"


@pytest.mark.integration
def test_create_deadline_rejects_past_deadline(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    response = client.post(
        "/api/v1/tasks/deadlines",
        headers=headers,
        json={
            "title": "Past Deadline",
            "deadline": "2020-01-01T17:00:00-05:00",
            "estimated_minutes": 60,
        },
    )

    assert response.status_code == 422


@pytest.mark.integration
def test_complete_task_removes_schedule_block(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=4, hour=13)
    end = future_local_iso(days=4, hour=14)

    created = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Complete Me",
            "start_time": start,
            "end_time": end,
            "priority": "Low",
        },
    )
    assert created.status_code == 200
    block_id = created.json()["_id"]
    task_id = created.json()["task_id"]

    completed = client.post(
        f"/api/v1/tasks/{task_id}/complete",
        headers=headers,
        json={"completed": True},
    )
    assert completed.status_code == 200

    from datetime import datetime
    from zoneinfo import ZoneInfo

    now = datetime.now(ZoneInfo("America/New_York"))
    month = client.get(
        "/api/v1/schedule/month",
        headers=headers,
        params={"year": now.year, "month": now.month},
    )
    assert month.status_code == 200
    ids = {item["_id"] for item in month.json()}
    assert block_id not in ids
