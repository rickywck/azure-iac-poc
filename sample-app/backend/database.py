from sqlalchemy import create_engine, Column, String, DateTime
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.sql import func
from datetime import datetime
import os
from urllib.parse import quote_plus
from functools import lru_cache
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

load_dotenv()


@lru_cache(maxsize=1)
def resolve_postgres_password() -> str:
    password = os.getenv("POSTGRES_PASSWORD", "")
    if password:
        return password

    key_vault_url = os.getenv("KEY_VAULT_URL", "")
    secret_name = os.getenv("POSTGRES_PASSWORD_SECRET_NAME", "")
    if not key_vault_url or not secret_name:
        return ""

    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=key_vault_url, credential=credential)
    return client.get_secret(secret_name).value


def build_database_url() -> str:
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return database_url

    postgres_user = os.getenv("POSTGRES_USER", "")
    postgres_password = resolve_postgres_password()
    postgres_host = os.getenv("POSTGRES_HOST", "localhost")
    postgres_db = os.getenv("POSTGRES_DB", "postgres")

    encoded_password = quote_plus(postgres_password)
    return f"postgresql+asyncpg://{postgres_user}:{encoded_password}@{postgres_host}/{postgres_db}"

DATABASE_URL = build_database_url()
POSTGRES_SSLMODE = os.getenv("POSTGRES_SSLMODE", "require")

connect_args = {}
if DATABASE_URL.startswith("postgresql+asyncpg://") and POSTGRES_SSLMODE:
    connect_args["ssl"] = POSTGRES_SSLMODE

# Configure async engine with connection pooling
engine = create_async_engine(
    DATABASE_URL,
    echo=False,  # Set to True only for debugging
    pool_pre_ping=True,  # Verify connections before use
    pool_size=5,  # Connection pool size
    max_overflow=10,  # Additional connections when pool is full
    connect_args=connect_args
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
