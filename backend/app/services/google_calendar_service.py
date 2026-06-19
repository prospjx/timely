from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
from bson import ObjectId

from app.core.config import get_settings
from app.db.mongo import mongo

settings = get_settings()


def get_callback_url_scheme() -> str:
    redirect_uri = settings.google_oauth_redirect_uri or ""
    if ":/" in redirect_uri:
        return redirect_uri.split(":/", 1)[0]
    return ""


def _client_config() -> Dict[str, Any]:
    if not settings.google_oauth_client_id or not settings.google_oauth_client_secret:
        raise RuntimeError("Google OAuth client ID/secret not configured")
    return {
        "web": {
            "client_id": settings.google_oauth_client_id,
            "client_secret": settings.google_oauth_client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    }


async def get_authorization_url(user_id: str, state: Optional[str] = None) -> Dict[str, str]:
    def sync() -> Dict[str, str]:
        flow = Flow.from_client_config(
            _client_config(), scopes=settings.google_oauth_scopes, redirect_uri=settings.google_oauth_redirect_uri
        )
        auth_url, used_state = flow.authorization_url(access_type="offline", include_granted_scopes="true", state=state or user_id)
        return {"auth_url": auth_url, "state": used_state}

    return await asyncio.to_thread(sync)


async def exchange_server_auth_code(server_auth_code: str, user_id: str) -> Dict[str, Any]:
    import httpx

    if not settings.google_oauth_client_id or not settings.google_oauth_client_secret:
        raise RuntimeError("Google OAuth client ID/secret not configured")

    code = server_auth_code.strip()
    if not code:
        raise RuntimeError("Missing server auth code")

    def sync() -> Dict[str, Any]:
        token_data: Dict[str, Any] | None = None
        last_error = "Unknown token exchange error"

        # Android server auth codes are exchanged without redirect_uri.
        payload_variants = [
            {
                "code": code,
                "client_id": settings.google_oauth_client_id,
                "client_secret": settings.google_oauth_client_secret,
                "grant_type": "authorization_code",
            },
            {
                "code": code,
                "client_id": settings.google_oauth_client_id,
                "client_secret": settings.google_oauth_client_secret,
                "grant_type": "authorization_code",
                "redirect_uri": "",
            },
        ]

        for payload in payload_variants:
            response = httpx.post("https://oauth2.googleapis.com/token", data=payload, timeout=30.0)
            if response.is_success:
                token_data = response.json()
                break
            try:
                body = response.json()
                last_error = body.get("error_description") or body.get("error") or response.text
            except Exception:
                last_error = response.text or last_error

        if token_data is None:
            try:
                flow = Flow.from_client_config(
                    _client_config(),
                    scopes=settings.google_oauth_scopes,
                    redirect_uri="",
                )
                flow.fetch_token(code=code)
                creds = flow.credentials
                token_data = {
                    "access_token": creds.token,
                    "refresh_token": creds.refresh_token,
                    "id_token": getattr(creds, "id_token", None),
                    "scope": " ".join(creds.scopes or []),
                }
            except Exception as exc:
                raise RuntimeError(f"Google token exchange failed: {last_error} ({exc})") from exc

        scopes = token_data.get("scope", "")
        return {
            "token": token_data.get("access_token"),
            "refresh_token": token_data.get("refresh_token"),
            "token_uri": "https://oauth2.googleapis.com/token",
            "client_id": settings.google_oauth_client_id,
            "client_secret": settings.google_oauth_client_secret,
            "scopes": scopes.split() if isinstance(scopes, str) else [],
            "expiry": None,
            "id_token": token_data.get("id_token"),
        }

    info = await asyncio.to_thread(sync)
    coll = mongo.collection("google_tokens")
    await coll.update_one({"user_id": user_id}, {"$set": {"credentials": info, "updated_at": datetime.utcnow()}}, upsert=True)
    return info


async def exchange_code_and_store(authorization_response_url: str, user_id: str) -> Dict[str, Any]:
    def sync() -> Dict[str, Any]:
        flow = Flow.from_client_config(
            _client_config(), scopes=settings.google_oauth_scopes, redirect_uri=settings.google_oauth_redirect_uri
        )
        flow.fetch_token(authorization_response=authorization_response_url)
        creds: Credentials = flow.credentials
        info: Dict[str, Any] = {
            "token": creds.token,
            "refresh_token": creds.refresh_token,
            "token_uri": creds.token_uri,
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "scopes": list(creds.scopes) if creds.scopes else [],
            "expiry": creds.expiry.isoformat() if creds.expiry else None,
            "id_token": getattr(creds, "id_token", None),
        }
        return info

    info = await asyncio.to_thread(sync)
    coll = mongo.collection("google_tokens")
    await coll.update_one({"user_id": user_id}, {"$set": {"credentials": info, "updated_at": datetime.utcnow()}}, upsert=True)
    return info


async def _get_credentials_for_user(user_id: str) -> Credentials:
    coll = mongo.collection("google_tokens")
    doc = await coll.find_one({"user_id": user_id})
    if not doc or "credentials" not in doc:
        raise RuntimeError("No Google credentials for user")
    info = doc["credentials"]
    creds = Credentials(
        token=info.get("token"),
        refresh_token=info.get("refresh_token"),
        token_uri=info.get("token_uri"),
        client_id=info.get("client_id"),
        client_secret=info.get("client_secret"),
        scopes=info.get("scopes"),
    )
    if info.get("expiry"):
        try:
            creds.expiry = datetime.fromisoformat(info["expiry"])
        except Exception:
            creds.expiry = None

    if creds.expired and creds.refresh_token:
        def refresh_and_persist() -> Dict[str, Any]:
            from google.auth.transport.requests import Request

            creds.refresh(Request())
            updated: Dict[str, Any] = {
                "token": creds.token,
                "refresh_token": creds.refresh_token,
                "token_uri": creds.token_uri,
                "client_id": creds.client_id,
                "client_secret": creds.client_secret,
                "scopes": list(creds.scopes) if creds.scopes else info.get("scopes", []),
                "expiry": creds.expiry.isoformat() if creds.expiry else None,
                "id_token": info.get("id_token"),
            }
            return updated

        updated_info = await asyncio.to_thread(refresh_and_persist)
        await coll.update_one(
            {"user_id": user_id},
            {"$set": {"credentials": updated_info, "updated_at": datetime.utcnow()}},
        )

    return creds


async def list_calendar_events(user_id: str, max_results: int = 10) -> List[Dict[str, Any]]:
    creds = await _get_credentials_for_user(user_id)

    def sync_list(c: Credentials, m: int) -> List[Dict[str, Any]]:
        service = build("calendar", "v3", credentials=c)
        time_min = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat().replace("+00:00", "Z")
        events_result = (
            service.events()
            .list(calendarId="primary", timeMin=time_min, maxResults=m, singleEvents=True, orderBy="startTime")
            .execute()
        )
        return events_result.get("items", [])

    return await asyncio.to_thread(sync_list, creds, max_results)


def _parse_google_event_time(value: Dict[str, Any]) -> Optional[datetime]:
    if "dateTime" in value:
        raw = value["dateTime"]
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        return datetime.fromisoformat(raw)
    if "date" in value:
        return datetime.fromisoformat(f"{value['date']}T00:00:00+00:00")
    return None


async def sync_events_to_schedule(user_doc: dict, max_results: int = 50) -> int:
    user_key = str(user_doc.get("firebase_uid") or user_doc.get("_id"))
    events = await list_calendar_events(user_key, max_results=max_results)
    schedule_collection = mongo.collection("schedule_blocks")
    inserted = 0

    for item in events:
        title = (item.get("summary") or "Calendar event").strip()
        if not title:
            continue

        start_time = _parse_google_event_time(item.get("start", {}))
        end_time = _parse_google_event_time(item.get("end", {}))
        if start_time is None or end_time is None or end_time <= start_time:
            continue

        conflict = await schedule_collection.find_one(
            {
                "user_id": user_doc["_id"],
                "start_time": {"$lt": end_time},
                "end_time": {"$gt": start_time},
                "source": "calendar_sync",
                "title": title,
            }
        )
        if conflict is not None:
            continue

        await schedule_collection.insert_one(
            {
                "user_id": user_doc["_id"],
                "title": title,
                "priority": "Medium",
                "start_time": start_time,
                "end_time": end_time,
                "type": "Meeting",
                "source": "calendar_sync",
            }
        )
        inserted += 1

    return inserted


async def get_stored_credentials_info(user_id: str) -> Optional[Dict[str, Any]]:
    coll = mongo.collection("google_tokens")
    doc = await coll.find_one({"user_id": user_id})
    if not doc:
        # try ObjectId match if possible
        try:
            oid = ObjectId(user_id)
            doc = await coll.find_one({"user_id": oid})
        except Exception:
            doc = None

    if not doc or "credentials" not in doc:
        return None

    info = doc["credentials"]
    return {
        "user_id": doc.get("user_id"),
        "scopes": info.get("scopes", []),
        "expiry": info.get("expiry"),
        "id_token": info.get("id_token"),
        "token_uri": info.get("token_uri"),
        "updated_at": doc.get("updated_at"),
    }


async def delete_credentials(user_id: str) -> bool:
    coll = mongo.collection("google_tokens")
    result = await coll.delete_one({"user_id": user_id})
    if result.deleted_count:
        return True
    try:
        oid = ObjectId(user_id)
        result = await coll.delete_one({"user_id": oid})
        return bool(result.deleted_count)
    except Exception:
        return False
