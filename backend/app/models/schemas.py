from datetime import date, datetime
from enum import Enum
from pydantic import BaseModel, Field


class TaskPriority(str, Enum):
    high = "High"
    medium = "Medium"
    low = "Low"


class TaskStatus(str, Enum):
    pending = "Pending"
    scheduled = "Scheduled"
    completed = "Completed"


class ScheduleBlockType(str, Enum):
    task = "Task"
    meeting = "Meeting"
    break_block = "Break"


class UserPreferences(BaseModel):
    wake_time: str = "07:00"
    sleep_time: str = "22:30"


class UserOut(BaseModel):
    id: str = Field(alias="_id")
    firebase_uid: str
    fcm_token: str | None = None
    timezone: str = "UTC"
    preferences: UserPreferences = Field(default_factory=UserPreferences)


class ParsedTask(BaseModel):
    title: str
    priority: TaskPriority = TaskPriority.medium
    deadline: datetime
    estimated_minutes: int = Field(default=60, ge=5, le=600)
    fixed_day: bool = False


class TaskProcessRequest(BaseModel):
    raw_text: str = Field(min_length=3)


class TaskOut(BaseModel):
    id: str = Field(alias="_id")
    user_id: str
    raw_input: str
    title: str
    priority: TaskPriority
    deadline: datetime
    estimated_minutes: int
    status: TaskStatus


class ScheduleBlockOut(BaseModel):
    id: str = Field(alias="_id")
    user_id: str
    task_id: str | None = None
    title: str | None = None
    priority: str | None = None
    start_time: datetime
    end_time: datetime
    type: ScheduleBlockType


class DiagnosticsLogRequest(BaseModel):
    interaction_type: str
    energy_score: int = Field(ge=1, le=5)


class DiagnosticsLogOut(BaseModel):
    id: str = Field(alias="_id")
    user_id: str
    timestamp: datetime
    interaction_type: str
    energy_score: int


class NotificationInteractionRequest(BaseModel):
    action_id: str = Field(min_length=1)
    action_label: str = Field(min_length=1)
    prompt_text: str = Field(default="What are you doing")
    source: str = Field(default="notification")
    scheduled_task_label: str | None = None
    metadata: dict = Field(default_factory=dict)


class NotificationInteractionOut(BaseModel):
    id: str = Field(alias="_id")
    user_id: str
    timestamp: datetime
    local_date: date
    action_id: str
    action_label: str
    prompt_text: str
    source: str
    scheduled_task_label: str | None = None
    is_snooze: bool = False
    is_completion: bool = False
    is_distraction: bool = False
    metadata: dict = Field(default_factory=dict)


class DailyTimeAnalysisOut(BaseModel):
    user_id: str
    local_date: date
    total_interactions: int
    completion_count: int
    snooze_count: int
    distraction_count: int
    deep_work_checkins: int
    distraction_ratio: float
    focus_score: int
    summary: str


class ReflectionsMetricsOut(BaseModel):
    user_id: str
    local_date: date
    tasks_due_count: int
    tasks_completed_before_deadline: int
    completion_rate_before_deadline: float
    available_minutes: int
    scheduled_minutes: int
    free_minutes: int
    rest_rate: float
    summary: str


class BriefResponse(BaseModel):
    success: bool
    text: str
    audio_url: str | None = None
