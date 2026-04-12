from datetime import date, datetime
from bson import ObjectId


def mongo_to_dict(document: dict | None) -> dict | None:
    if document is None:
        return None

    parsed: dict = {}
    for key, value in document.items():
        if isinstance(value, ObjectId):
            parsed[key] = str(value)
        elif isinstance(value, datetime):
            parsed[key] = value
        elif isinstance(value, date):
            parsed[key] = value.isoformat()
        elif isinstance(value, list):
            parsed[key] = [mongo_to_dict(v) if isinstance(v, dict) else v for v in value]
        elif isinstance(value, dict):
            parsed[key] = mongo_to_dict(value)
        else:
            parsed[key] = value
    return parsed
