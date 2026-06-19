from __future__ import annotations

from pathlib import Path

from app.core.config import get_settings

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:  # pragma: no cover
    firebase_admin = None
    credentials = None
    messaging = None


def _ensure_firebase_initialized() -> bool:
    settings = get_settings()
    if firebase_admin is None or settings.firebase_credentials_path is None:
        return False

    if firebase_admin._apps:
        return True

    cred_path = Path(settings.firebase_credentials_path)
    if not cred_path.exists():
        return False

    cred = credentials.Certificate(str(cred_path))
    firebase_admin.initialize_app(cred)
    return True


async def send_brief_to_phone(user_doc: dict, text: str, audio_url: str | None) -> bool:
    token = user_doc.get("fcm_token")
    if not token:
        return False

    if not _ensure_firebase_initialized():
        return False

    notification = messaging.Notification(title="Your Kairos Brief", body=text[:160])
    data_payload = {"type": "brief", "text": text, "audio_url": audio_url or ""}
    message = messaging.Message(token=token, notification=notification, data=data_payload)
    messaging.send(message)
    return True


async def send_micro_prompt(user_doc: dict, prompt: str = "Still working?") -> bool:
    token = user_doc.get("fcm_token")
    if not token:
        return False

    if not _ensure_firebase_initialized():
        return False

    message = messaging.Message(token=token, data={"type": "micro_checkin", "prompt": prompt})
    messaging.send(message)
    return True


async def send_activity_probe(
    user_doc: dict,
    *,
    prompt_text: str = "What are you doing",
    scheduled_task_label: str = "Studying for an exam",
) -> bool:
    token = user_doc.get("fcm_token")
    if not token:
        return False

    if not _ensure_firebase_initialized():
        return False

    payload = {
        "type": "activity_probe",
        "prompt_text": prompt_text,
        "scheduled_task_label": scheduled_task_label,
        "action_task_id": "task_due",
        "action_task_label": scheduled_task_label,
        "action_scrolling_id": "scrolling",
        "action_scrolling_label": "Scrolling",
        "action_urgent_id": "urgent_task",
        "action_urgent_label": "Impromptu task to do immediately",
        "action_snooze_id": "snooze",
        "action_snooze_label": "Snooze",
    }
    message = messaging.Message(token=token, data=payload)
    messaging.send(message)
    return True


async def send_task_moved_notification(user_doc: dict, task_title: str, new_start_time_iso: str) -> bool:
    token = user_doc.get("fcm_token")
    if not token:
        return False

    if not _ensure_firebase_initialized():
        return False

    body = f"Moved '{task_title}' to {new_start_time_iso}."
    notification = messaging.Notification(title="Schedule updated", body=body)
    data_payload = {
        "type": "task_moved",
        "task_title": task_title,
        "new_start_time": new_start_time_iso,
    }
    message = messaging.Message(token=token, notification=notification, data=data_payload)
    messaging.send(message)
    return True
