from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
import uuid

class TaskBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    status: str = Field(default="pending", pattern="^(pending|active|done)$")

class TaskCreate(TaskBase):
    pass

class TaskUpdate(TaskBase):
    pass

class Task(TaskBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=12000)

class ChatResponse(BaseModel):
    message: str
    is_calculation: bool = False
    mode: str = "direct"
    direct_response: str = ""
    code_result: str = ""
    generated_python: str = ""
    execution_backend: str = ""
