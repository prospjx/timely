from __future__ import annotations

from fastapi import Header

from app.db.mongo import mongo


async def get_current_user(
    x_firebase_uid: str = Header(default="demo-user", alias="X-Firebase-Uid"),
    x_timezone: str = Header(default="UTC", alias="X-Timezone"),
) -> dict:
    users = mongo.collection("users")
    user = await users.find_one({"firebase_uid": x_firebase_uid})
    if user:
        if user.get("timezone") != x_timezone:
            await users.update_one({"_id": user["_id"]}, {"$set": {"timezone": x_timezone}})
            user["timezone"] = x_timezone
        return user

    document = {
        "firebase_uid": x_firebase_uid,
        "fcm_token": None,
        "timezone": x_timezone,
        "preferences": {"wake_time": "07:00", "sleep_time": "22:30"},
    }
    result = await users.insert_one(document)
    document["_id"] = result.inserted_id
    return document
