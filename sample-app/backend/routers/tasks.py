from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import get_db, TaskDB
from models import Task, TaskCreate, TaskUpdate

router = APIRouter()

@router.get("", response_model=list[Task])
async def get_tasks(db: AsyncSession = Depends(get_db)):
    """Get all tasks."""
    result = await db.execute(select(TaskDB).order_by(TaskDB.created_at.desc()))
    tasks = result.scalars().all()
    return [Task.model_validate(task) for task in tasks]

@router.get("/{task_id}", response_model=Task)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Get a specific task by ID."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return Task.model_validate(task)

@router.post("", response_model=Task, status_code=201)
async def create_task(task: TaskCreate, db: AsyncSession = Depends(get_db)):
    """Create a new task."""
    task_db = TaskDB(
        id=str(uuid.uuid4()),
        title=task.title,
        description=task.description,
        status=task.status
    )
    db.add(task_db)
    await db.commit()
    await db.refresh(task_db)
    return Task.model_validate(task_db)

@router.put("/{task_id}", response_model=Task)
async def update_task(task_id: str, task: TaskUpdate, db: AsyncSession = Depends(get_db)):
    """Update an existing task."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task_db = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    task_db.title = task.title
    task_db.description = task.description
    task_db.status = task.status

    await db.commit()
    await db.refresh(task_db)
    return Task.model_validate(task_db)

@router.delete("/{task_id}")
async def delete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Delete a task."""
    result = await db.execute(select(TaskDB).where(TaskDB.id == task_id))
    task_db = result.scalar_one_or_none()
    if not task_db:
        raise HTTPException(status_code=404, detail="Task not found")

    await db.delete(task_db)
    await db.commit()
    return {"message": "Task deleted"}
