from langchain_openai import AzureChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
import os

class FoundryAgent:
    """Simple agent that uses Microsoft Foundry for LLM completions."""

    def __init__(self):
        self.endpoint = os.getenv("FOUNDRY_ENDPOINT", "")
        self.api_key = os.getenv("FOUNDRY_API_KEY", "")
        self.model = os.getenv("FOUNDRY_MODEL", "gpt-4mini")

        # Parse endpoint to get base URL and deployment
        # Expected format: https://<resource>.openai.azure.com/
        base_url = self.endpoint.rstrip("/")
        if not base_url.endswith("/openai"):
            base_url = f"{base_url}/openai"

        self.llm = AzureChatOpenAI(
            azure_endpoint=base_url,
            api_key=self.api_key,
            api_version="2024-02-15-preview",
            deployment_name=self.model,
            temperature=0.7
        )

    async def chat(self, message: str) -> str:
        """Send a message to the LLM and get a response."""
        try:
            response = await self.llm.ainvoke([
                SystemMessage(content="You are a helpful AI assistant. Respond concisely and helpfully."),
                HumanMessage(content=message)
            ])
            return response.content
        except Exception as e:
            return f"Error: Unable to get response from Foundry. Details: {str(e)}"

# Singleton instance
_agent = None

def get_agent() -> FoundryAgent:
    global _agent
    if _agent is None:
        _agent = FoundryAgent()
    return _agent
