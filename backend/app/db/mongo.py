from __future__ import annotations

from typing import Any

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
class MongoManager:
    def __init__(self) -> None:
        self.client: AsyncIOMotorClient | None = None
        self.db: AsyncIOMotorDatabase | None = None

    async def connect(self, uri: str, db_name: str) -> None:
        self.client = AsyncIOMotorClient(
            uri,
            serverSelectionTimeoutMS=1500,
            connectTimeoutMS=1500,
            socketTimeoutMS=1500,
        )
        await self.client.admin.command("ping")
        self.db = self.client[db_name]

    async def disconnect(self) -> None:
        if self.client is not None:
            self.client.close()
            self.client = None
        self.db = None

    def collection(self, name: str) -> Any:
        if self.db is not None:
            return self.db[name]
        raise RuntimeError("MongoDB is not initialized")


mongo = MongoManager()
