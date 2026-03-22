from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from pydantic import BaseModel
import os
import uvicorn

from database import get_db, init_db, TaskDB
from models import Task, TaskCreate, TaskUpdate
from routers import tasks, agent


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield

app = FastAPI(
    title="Agentic POC Backend",
    description="Backend API for the Agentic POC application",
    version="0.1.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
from routers.tasks import router as tasks_router
from routers.agent import router as agent_router

app.include_router(tasks_router, prefix="/api/tasks", tags=["tasks"])
app.include_router(agent_router, prefix="/api/agent", tags=["agent"])

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.get("/ready")
async def readiness_check():
    return {"status": "ready"}

@app.get("/")
async def root():
    return {"message": "Agentic POC Backend API", "version": "0.1.0"}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "8000")), reload=False)
