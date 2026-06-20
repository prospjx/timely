from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from tests.conftest import future_local_iso


@pytest.mark.integration
def test_get_month_schedule_returns_created_blocks(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=2, hour=15)
    end = future_local_iso(days=2, hour=16)

    created = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Month View Event",
            "start_time": start,
            "end_time": end,
            "priority": "Medium",
        },
    )
    assert created.status_code == 200
    block_id = created.json()["_id"]

    now = datetime.now(ZoneInfo("America/New_York"))
    response = client.get(
        "/api/v1/schedule/month",
        headers=headers,
        params={"year": now.year, "month": now.month},
    )

    assert response.status_code == 200
    ids = {item["_id"] for item in response.json()}
    assert block_id in ids


@pytest.mark.integration
def test_update_block_title_only(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=6, hour=11)
    end = future_local_iso(days=6, hour=12)

    created = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Original Title",
            "start_time": start,
            "end_time": end,
            "priority": "Medium",
        },
    )
    assert created.status_code == 200
    block_id = created.json()["_id"]

    updated = client.patch(
        f"/api/v1/schedule/blocks/{block_id}",
        headers=headers,
        json={"title": "Renamed Title"},
    )
    assert updated.status_code == 200
    assert updated.json()["title"] == "Renamed Title"


@pytest.mark.integration
def test_delete_schedule_block(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=7, hour=9)
    end = future_local_iso(days=7, hour=10)

    created = client.post(
        "/api/v1/tasks/events",
        headers=headers,
        json={
            "title": "Delete Me",
            "start_time": start,
            "end_time": end,
            "priority": "Medium",
        },
    )
    assert created.status_code == 200
    block_id = created.json()["_id"]

    deleted = client.delete(f"/api/v1/schedule/blocks/{block_id}", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["success"] is True

    now = datetime.now(ZoneInfo("America/New_York"))
    month = client.get(
        "/api/v1/schedule/month",
        headers=headers,
        params={"year": now.year, "month": now.month},
    )
    ids = {item["_id"] for item in month.json()}
    assert block_id not in ids


@pytest.mark.integration
def test_calendar_import_inserts_meeting_blocks(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers
    start = future_local_iso(days=8, hour=14)
    end = future_local_iso(days=8, hour=15)

    response = client.post(
        "/api/v1/schedule/calendar/import",
        headers=headers,
        json={
            "events": [
                {
                    "title": "Imported Standup",
                    "start_time": start,
                    "end_time": end,
                }
            ]
        },
    )

    assert response.status_code == 200
    assert response.json()["imported"] == 1
