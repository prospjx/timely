from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi import Header

from app.db.mongo import mongo
from app.models.schemas import BriefResponse
from app.routers.deps import get_current_user
from app.services.brief_service import trigger_brief_for_user


router = APIRouter(prefix="/brief", tags=["brief"])


@router.post("/trigger", response_model=BriefResponse)
async def trigger_brief(
    user_doc: dict = Depends(get_current_user),
    x_client_local_time: str | None = Header(default=None, alias="X-Client-Local-Time"),
    x_client_time_display: str | None = Header(default=None, alias="X-Client-Time-Display"),
):
    result = await trigger_brief_for_user(
        user_doc,
        schedule_collection=mongo.collection("schedule_blocks"),
        diagnostics_collection=mongo.collection("diagnostic_logs"),
        client_local_time_iso=x_client_local_time,
        client_time_display=x_client_time_display,
    )
    return result
