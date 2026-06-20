from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


def test_health_check(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.integration
def test_trigger_brief(client: TestClient, auth_headers: tuple[dict, str]) -> None:
    headers, _ = auth_headers

    response = client.post("/api/v1/brief/trigger", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["text"]
