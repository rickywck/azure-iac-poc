from openai import AsyncAzureOpenAI
import os

class FoundryAgent:
    """Simple agent that uses Microsoft Foundry for LLM completions."""

    def __init__(self):
        self.endpoint = os.getenv("FOUNDRY_ENDPOINT", "")
        self.api_key = os.getenv("FOUNDRY_API_KEY", "")
        self.model = os.getenv("FOUNDRY_MODEL", "gpt-4mini")

        self.client = AsyncAzureOpenAI(
            azure_endpoint=self.endpoint,
            api_key=self.api_key,
            api_version="2024-02-15-preview"
        )

    async def chat(self, message: str) -> str:
        """Send a message to the LLM and get a response."""
        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                temperature=0.7,
                messages=[
                    {
                        "role": "system",
                        "content": "You are a helpful AI assistant. Respond concisely and helpfully."
                    },
                    {
                        "role": "user",
                        "content": message
                    }
                ]
            )
            return response.choices[0].message.content or ""
        except Exception as e:
            return f"Error: Unable to get response from Foundry. Details: {str(e)}"

# Singleton instance
_agent = None

def get_agent() -> FoundryAgent:
    global _agent
    if _agent is None:
        _agent = FoundryAgent()
    return _agent
