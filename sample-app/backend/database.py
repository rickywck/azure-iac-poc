from sqlalchemy import create_engine, Column, String, DateTime
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.sql import func
from datetime import datetime
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://user:pass@localhost/db")

# Configure async engine with connection pooling
engine = create_async_engine(
    DATABASE_URL,
    echo=False,  # Set to True only for debugging
    pool_pre_ping=True,  # Verify connections before use
    pool_size=5,  # Connection pool size
    max_overflow=10  # Additional connections when pool is full
)
async_session_maker = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

Base = declarative_base()

class TaskDB(Base):
    __tablename__ = "tasks"

    id = Column(String, primary_key=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

async def get_db():
    async with async_session_maker() as session:
        yield session

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
