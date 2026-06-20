from __future__ import annotations

import asyncio
import os
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("MONGODB_URI", "mongodb://localhost:27017")
os.environ.setdefault("MONGODB_DB_NAME", "kairos_test")

from app.core.config import get_settings  # noqa: E402
from app.db.mongo import mongo  # noqa: E402
from app.main import app  # noqa: E402

get_settings.cache_clear()

COLLECTIONS_WITH_USER_ID = (
    "tasks",
    "schedule_blocks",
    "diagnostic_logs",
    "notification_interactions",
    "daily_time_analysis",
)


async def _mongo_ping() -> bool:
    from motor.motor_asyncio import AsyncIOMotorClient

    client = AsyncIOMotorClient(
        os.environ["MONGODB_URI"],
        serverSelectionTimeoutMS=1500,
        connectTimeoutMS=1500,
    )
    try:
        await client.admin.command("ping")
        return True
    except Exception:
        return False
    finally:
        client.close()


@pytest.fixture(scope="session")
def mongo_available() -> None:
    if not asyncio.run(_mongo_ping()):
        pytest.skip("MongoDB is not available")


@pytest.fixture
def client(mongo_available: None) -> TestClient:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def auth_headers(mongo_available: None) -> tuple[dict[str, str], str]:
    firebase_uid = f"test-{uuid4().hex[:12]}"
    headers = {
        "X-Firebase-Uid": firebase_uid,
        "X-Timezone": "America/New_York",
        "Content-Type": "application/json",
    }
    yield headers, firebase_uid
    asyncio.run(_cleanup_user(firebase_uid))


async def _cleanup_user(firebase_uid: str) -> None:
    if mongo.db is None:
        return

    user = await mongo.collection("users").find_one({"firebase_uid": firebase_uid})
    if user is None:
        return

    user_id = user["_id"]
    for collection_name in COLLECTIONS_WITH_USER_ID:
        await mongo.collection(collection_name).delete_many({"user_id": user_id})
    await mongo.collection("users").delete_one({"_id": user_id})


def future_local_iso(*, days: int = 2, hour: int = 14, minute: int = 0) -> str:
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo

    tz = ZoneInfo("America/New_York")
    when = (datetime.now(tz) + timedelta(days=days)).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    )
    return when.isoformat()
