from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import os
import uvicorn

from agent import get_agent

load_dotenv()

app = FastAPI(
    title="Agentic POC Agents Service",
    description="LangChain agents service for the Agentic POC",
    version="0.1.0"
)

# CORS middleware - allow calls from backend service
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For POC - restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=12000)

class ChatResponse(BaseModel):
    message: str
    is_calculation: bool = False
    mode: str = 'direct'
    direct_response: str = ''
    code_result: str = ''
    generated_python: str = ''
    execution_backend: str = ''

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "agents"}

@app.get("/ready")
async def readiness_check():
    return {"status": "ready", "service": "agents"}

@app.post("/agent", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    """Process a chat message using the LangChain agent."""
    agent = get_agent()
    response = await agent.chat(request.message)
    return ChatResponse(**response)

@app.get("/")
async def root():
    return {
        "message": "Agentic POC Agents Service",
        "version": "0.1.0",
        "model": os.getenv("FOUNDRY_MODEL", "gpt-5.1-codex-mini")
    }


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "8001")), reload=False)
