from __future__ import annotations

import asyncio
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
from zoneinfo import ZoneInfo

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


def _parse_google_event_time(value: Dict[str, Any], *, user_timezone: str = "UTC") -> Optional[datetime]:
    if "dateTime" not in value:
        return None
    raw = value["dateTime"]
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    dt = datetime.fromisoformat(raw)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _parse_google_all_day_range(
    start: Dict[str, Any], end: Dict[str, Any], *, user_timezone: str
) -> Optional[Tuple[datetime, datetime]]:
    start_raw = start.get("date")
    end_raw = end.get("date")
    if not start_raw or not end_raw:
        return None

    try:
        local_zone = ZoneInfo(user_timezone)
    except Exception:
        local_zone = timezone.utc

    start_date = date.fromisoformat(start_raw)
    end_date = date.fromisoformat(end_raw)
    if end_date <= start_date:
        return None

    start_dt = datetime.combine(start_date, time.min, tzinfo=local_zone).astimezone(timezone.utc)
    end_dt = datetime.combine(end_date, time.min, tzinfo=local_zone).astimezone(timezone.utc)
    return start_dt, end_dt


async def sync_events_to_schedule(user_doc: dict, max_results: int = 50) -> int:
    user_key = str(user_doc.get("firebase_uid") or user_doc.get("_id"))
    user_timezone = str(user_doc.get("timezone") or "UTC")
    events = await list_calendar_events(user_key, max_results=max_results)
    schedule_collection = mongo.collection("schedule_blocks")
    await schedule_collection.delete_many({"user_id": user_doc["_id"], "source": "calendar_sync"})
    await schedule_collection.delete_many({"user_id": user_doc["_id"], "source": "demo"})
    inserted = 0

    for item in events:
        title = (item.get("summary") or "Calendar event").strip()
        if not title:
            continue

        start_value = item.get("start", {})
        end_value = item.get("end", {})
        is_all_day = "date" in start_value

        if is_all_day:
            parsed_range = _parse_google_all_day_range(start_value, end_value, user_timezone=user_timezone)
            if parsed_range is None:
                continue
            start_time, end_time = parsed_range
        else:
            start_time = _parse_google_event_time(start_value, user_timezone=user_timezone)
            end_time = _parse_google_event_time(end_value, user_timezone=user_timezone)
            if start_time is None or end_time is None or end_time <= start_time:
                continue

        google_event_id = item.get("id")
        doc = {
            "user_id": user_doc["_id"],
            "title": title,
            "priority": "Medium",
            "start_time": start_time,
            "end_time": end_time,
            "type": "Meeting",
            "source": "calendar_sync",
            "all_day": is_all_day,
            "google_event_id": google_event_id,
            "google_html_link": item.get("htmlLink"),
        }

        await schedule_collection.insert_one(doc)
        inserted += 1

    return inserted


def _format_google_event_datetime(dt: datetime, *, user_timezone: str) -> dict:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    local = dt.astimezone(ZoneInfo(user_timezone))
    return {"dateTime": local.isoformat(), "timeZone": user_timezone}


async def update_calendar_event(
    user_id: str,
    google_event_id: str,
    *,
    title: str,
    start_time: datetime,
    end_time: datetime,
    user_timezone: str = "UTC",
    all_day: bool = False,
) -> dict:
    creds = await _get_credentials_for_user(user_id)

    def sync_update(c: Credentials) -> dict:
        service = build("calendar", "v3", credentials=c)
        event = service.events().get(calendarId="primary", eventId=google_event_id).execute()
        event["summary"] = title
        if all_day:
            start_date = start_time.astimezone(ZoneInfo(user_timezone)).date().isoformat()
            end_date = end_time.astimezone(ZoneInfo(user_timezone)).date().isoformat()
            event["start"] = {"date": start_date}
            event["end"] = {"date": end_date}
        else:
            event["start"] = _format_google_event_datetime(start_time, user_timezone=user_timezone)
            event["end"] = _format_google_event_datetime(end_time, user_timezone=user_timezone)
        return service.events().update(calendarId="primary", eventId=google_event_id, body=event).execute()

    return await asyncio.to_thread(sync_update, creds)


async def delete_calendar_event(user_id: str, google_event_id: str) -> None:
    creds = await _get_credentials_for_user(user_id)

    def sync_delete(c: Credentials) -> None:
        service = build("calendar", "v3", credentials=c)
        service.events().delete(calendarId="primary", eventId=google_event_id).execute()

    await asyncio.to_thread(sync_delete, creds)


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
