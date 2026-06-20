from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


@pytest.mark.integration
def test_log_diagnostic_energy_score(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    response = client.post(
        "/api/v1/diagnostics/log",
        headers=headers,
        json={"interaction_type": "manual_checkin", "energy_score": 4},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["energy_score"] == 4
    assert body["interaction_type"] == "manual_checkin"


@pytest.mark.integration
def test_log_notification_interaction(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    response = client.post(
        "/api/v1/diagnostics/interaction/log",
        headers=headers,
        json={
            "action_id": "task_due",
            "action_label": "Done",
            "prompt_text": "What are you doing",
            "source": "test",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["action_id"] == "task_due"
    assert body["is_completion"] is True


@pytest.mark.integration
def test_get_today_analysis(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    client.post(
        "/api/v1/diagnostics/interaction/log",
        headers=headers,
        json={
            "action_id": "task_due",
            "action_label": "Done",
            "prompt_text": "What are you doing",
            "source": "test",
        },
    )

    response = client.get("/api/v1/diagnostics/analysis/today", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert "focus_score" in body
    assert body["total_interactions"] >= 1


@pytest.mark.integration
def test_get_today_reflections(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    response = client.get("/api/v1/diagnostics/reflections/today", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert "completion_rate_before_deadline" in body
    assert "rest_rate" in body
    assert "summary" in body
