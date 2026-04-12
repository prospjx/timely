from __future__ import annotations

from copy import deepcopy
from datetime import datetime
from typing import Any, Iterable

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase


class MockInsertOneResult:
    def __init__(self, inserted_id: ObjectId) -> None:
        self.inserted_id = inserted_id


class MockUpdateResult:
    def __init__(self, modified_count: int) -> None:
        self.modified_count = modified_count


class MockDeleteResult:
    def __init__(self, deleted_count: int) -> None:
        self.deleted_count = deleted_count


class MockInsertManyResult:
    def __init__(self, inserted_ids: list[ObjectId]) -> None:
        self.inserted_ids = inserted_ids


class MockCursor:
    def __init__(self, documents: list[dict[str, Any]]) -> None:
        self._documents = documents

    def sort(self, key: str, direction: int) -> MockCursor:
        reverse = direction < 0
        self._documents.sort(key=lambda document: document.get(key), reverse=reverse)
        return self

    def __aiter__(self) -> MockCursor:
        self._index = 0
        return self

    async def __anext__(self) -> dict[str, Any]:
        if self._index >= len(self._documents):
            raise StopAsyncIteration
        document = self._documents[self._index]
        self._index += 1
        return deepcopy(document)


def _matches_filter(document: dict[str, Any], filter_query: dict[str, Any]) -> bool:
    for key, expected in filter_query.items():
        actual = document.get(key)
        if isinstance(expected, dict):
            for operator, value in expected.items():
                if operator == "$lt" and not (actual < value):
                    return False
                if operator == "$lte" and not (actual <= value):
                    return False
                if operator == "$gt" and not (actual > value):
                    return False
                if operator == "$gte" and not (actual >= value):
                    return False
        elif actual != expected:
            return False
    return True


class MockCollection:
    def __init__(self) -> None:
        self._documents: list[dict[str, Any]] = []

    async def insert_one(self, document: dict[str, Any]) -> MockInsertOneResult:
        stored = deepcopy(document)
        stored.setdefault("_id", ObjectId())
        self._documents.append(stored)
        return MockInsertOneResult(stored["_id"])

    async def insert_many(self, documents: list[dict[str, Any]]) -> MockInsertManyResult:
        inserted_ids: list[ObjectId] = []
        for document in documents:
            stored = deepcopy(document)
            stored.setdefault("_id", ObjectId())
            self._documents.append(stored)
            inserted_ids.append(stored["_id"])
        return MockInsertManyResult(inserted_ids)

    async def find_one(self, filter_query: dict[str, Any] | None = None, sort: list[tuple[str, int]] | None = None) -> dict[str, Any] | None:
        documents = [deepcopy(document) for document in self._documents]
        if filter_query:
            documents = [document for document in documents if _matches_filter(document, filter_query)]
        if sort:
            for key, direction in reversed(sort):
                documents.sort(key=lambda document: document.get(key), reverse=direction < 0)
        return documents[0] if documents else None

    async def update_one(self, filter_query: dict[str, Any], update_query: dict[str, Any]) -> MockUpdateResult:
        for document in self._documents:
            if _matches_filter(document, filter_query):
                for operator, payload in update_query.items():
                    if operator == "$set":
                        document.update(payload)
                return MockUpdateResult(modified_count=1)
        return MockUpdateResult(modified_count=0)

    async def delete_many(self, filter_query: dict[str, Any]) -> MockDeleteResult:
        kept_documents: list[dict[str, Any]] = []
        deleted_count = 0

        for document in self._documents:
            if _matches_filter(document, filter_query):
                deleted_count += 1
            else:
                kept_documents.append(document)

        self._documents = kept_documents
        return MockDeleteResult(deleted_count=deleted_count)

    def find(self, filter_query: dict[str, Any] | None = None) -> MockCursor:
        documents = [deepcopy(document) for document in self._documents]
        if filter_query:
            documents = [document for document in documents if _matches_filter(document, filter_query)]
        return MockCursor(documents)


class MockDatabase:
    def __init__(self) -> None:
        self._collections: dict[str, MockCollection] = {}

    def __getitem__(self, name: str) -> MockCollection:
        if name not in self._collections:
            self._collections[name] = MockCollection()
        return self._collections[name]


class MongoManager:
    def __init__(self) -> None:
        self.client: AsyncIOMotorClient | None = None
        self.db: AsyncIOMotorDatabase | None = None
        self.mock_db: MockDatabase | None = None
        self.is_mock: bool = False

    async def connect(self, uri: str, db_name: str) -> None:
        try:
            self.client = AsyncIOMotorClient(
                uri,
                serverSelectionTimeoutMS=1500,
                connectTimeoutMS=1500,
                socketTimeoutMS=1500,
            )
            await self.client.admin.command("ping")
            self.db = self.client[db_name]
            self.mock_db = None
            self.is_mock = False
        except Exception:
            self.client = None
            self.db = None
            self.mock_db = MockDatabase()
            self.is_mock = True

    async def disconnect(self) -> None:
        if self.client is not None:
            self.client.close()
            self.client = None
        self.db = None
        self.mock_db = None
        self.is_mock = False

    def collection(self, name: str) -> Any:
        if self.db is not None:
            return self.db[name]
        if self.mock_db is not None:
            return self.mock_db[name]
        raise RuntimeError("MongoDB is not initialized")


mongo = MongoManager()
