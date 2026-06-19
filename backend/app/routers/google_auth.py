from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query, Request, Depends
from fastapi.responses import RedirectResponse, JSONResponse
from pydantic import BaseModel

from app.routers.deps import get_current_user

from app.services import google_calendar_service

router = APIRouter(prefix="/google", tags=["google"])


def _google_user_id(user_doc: dict, user_id: Optional[str] = None) -> str:
    if user_id:
        return user_id
    return str(user_doc.get("firebase_uid") or user_doc.get("_id"))


class GoogleOAuthCompleteRequest(BaseModel):
    callback_url: str
    user_id: str


class GoogleConnectRequest(BaseModel):
    server_auth_code: str
    user_id: str


@router.get("/auth-url")
async def google_auth_url(user_id: str = Query(..., description="Local user id to associate tokens with")) -> JSONResponse:
    data = await google_calendar_service.get_authorization_url(user_id=user_id)
    callback_scheme = google_calendar_service.get_callback_url_scheme()
    return JSONResponse({"auth_url": data["auth_url"], "callback_url_scheme": callback_scheme})

@router.post("/complete")
async def google_complete(body: GoogleOAuthCompleteRequest) -> JSONResponse:
    await google_calendar_service.exchange_code_and_store(body.callback_url, body.user_id)
    return JSONResponse({"status": "ok", "user_id": body.user_id})


@router.post("/connect")
async def google_connect(body: GoogleConnectRequest) -> JSONResponse:
    try:
        await google_calendar_service.exchange_server_auth_code(body.server_auth_code, body.user_id)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return JSONResponse({"status": "ok", "user_id": body.user_id})


@router.get("/login")
async def google_login(user_id: str = Query(..., description="Local user id to associate tokens with")) -> RedirectResponse:
    data = await google_calendar_service.get_authorization_url(user_id=user_id)
    return RedirectResponse(data["auth_url"])


@router.get("/callback")
async def google_callback(request: Request, state: Optional[str] = None) -> JSONResponse:
    user_id = state or request.query_params.get("state")
    if not user_id:
        raise HTTPException(status_code=400, detail="Missing state/user_id")
    full_url = str(request.url)
    await google_calendar_service.exchange_code_and_store(full_url, user_id)
    return JSONResponse({"status": "ok", "user_id": user_id})


@router.post("/sync")
async def sync_google_calendar(
    user_doc: dict = Depends(get_current_user),
    max_results: int = Query(50, ge=1, le=250),
) -> JSONResponse:
    try:
        imported = await google_calendar_service.sync_events_to_schedule(user_doc, max_results=max_results)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return JSONResponse({"success": True, "imported": imported})


@router.get("/calendar/events")
async def calendar_events(user_id: str = Query(...), max_results: int = Query(10)) -> Any:
    try:
        events = await google_calendar_service.list_calendar_events(user_id=user_id, max_results=max_results)
        return {"events": events}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/accounts")
async def get_linked_account(user_id: Optional[str] = Query(None), user_doc: dict = Depends(get_current_user)) -> Any:
    target_id = _google_user_id(user_doc, user_id)
    info = await google_calendar_service.get_stored_credentials_info(target_id)
    return {"linked": bool(info), "info": info}


@router.delete("/disconnect")
async def disconnect_account(user_id: Optional[str] = Query(None), user_doc: dict = Depends(get_current_user)) -> Any:
    target_id = _google_user_id(user_doc, user_id)
    success = await google_calendar_service.delete_credentials(target_id)
    return {"success": success}
