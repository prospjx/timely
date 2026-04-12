from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Kairos Backend"
    app_env: str = "development"
    api_prefix: str = "/api/v1"

    mongodb_uri: str = Field(default="mongodb://localhost:27017", alias="MONGODB_URI")
    mongodb_db_name: str = Field(default="kairos", alias="MONGODB_DB_NAME")

    gemini_api_key: str | None = Field(default=None, alias="GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-1.5-flash", alias="GEMINI_MODEL")

    elevenlabs_api_key: str | None = Field(default=None, alias="ELEVENLABS_API_KEY")
    elevenlabs_voice_id: str | None = Field(default=None, alias="ELEVENLABS_VOICE_ID")
    audio_public_base_url: str | None = Field(default=None, alias="AUDIO_PUBLIC_BASE_URL")

    firebase_credentials_path: str | None = Field(default=None, alias="FIREBASE_CREDENTIALS_PATH")

    brief_cron_hour_utc: int = Field(default=5, alias="BRIEF_CRON_HOUR_UTC")
    analysis_cron_hour_utc: int = Field(default=0, alias="ANALYSIS_CRON_HOUR_UTC")
    analysis_cron_minute_utc: int = Field(default=15, alias="ANALYSIS_CRON_MINUTE_UTC")
    max_high_priority_minutes_without_break: int = Field(default=120, alias="MAX_HIGH_PRIORITY_MINUTES_WITHOUT_BREAK")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
