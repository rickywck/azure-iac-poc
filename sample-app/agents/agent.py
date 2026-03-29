from openai import AsyncAzureOpenAI
import asyncio
import json
import os
import re

import httpx

class FoundryAgent:
    """Simple agent that uses Microsoft Foundry for LLM completions."""

    def __init__(self):
        self.endpoint = os.getenv("FOUNDRY_ENDPOINT", "").rstrip("/")
        self.api_key = os.getenv("FOUNDRY_API_KEY", "")
        self.model = os.getenv("FOUNDRY_MODEL", "gpt-5.1-codex-mini")
        self.dynamic_session_executor_url = os.getenv("DYNAMIC_SESSION_EXECUTOR_URL", "").strip()
        self.dynamic_session_executor_api_key = os.getenv("DYNAMIC_SESSION_EXECUTOR_API_KEY", "").strip()
        self.responses_api_url = f"{self.endpoint}/openai/v1/responses" if self.endpoint else ""
        self.use_responses_api = self._model_uses_responses_api(self.model)

        self.client = AsyncAzureOpenAI(
            azure_endpoint=self.endpoint,
            api_key=self.api_key,
            api_version="2024-02-15-preview"
        )

    @staticmethod
    def _model_uses_responses_api(model_name: str) -> bool:
        lowered = model_name.lower()
        return 'codex' in lowered

    @staticmethod
    def _extract_response_text(response_payload: dict) -> str:
        output_text = response_payload.get("output_text")
        if isinstance(output_text, str) and output_text.strip():
            return output_text.strip()

        text_parts: list[str] = []
        for item in response_payload.get("output", []):
            if item.get("type") != "message":
                continue

            for content_item in item.get("content", []):
                if content_item.get("type") == "output_text" and content_item.get("text"):
                    text_parts.append(content_item["text"])

        return "\n".join(part.strip() for part in text_parts if part and part.strip()).strip()

    @staticmethod
    def _parse_json_object(content: str) -> dict:
        normalized = content.strip()
        if normalized.startswith("```"):
            normalized = re.sub(r"^```(?:json)?\s*", "", normalized)
            normalized = re.sub(r"\s*```$", "", normalized)

        try:
            payload = json.loads(normalized)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", normalized, re.DOTALL)
            if not match:
                raise
            payload = json.loads(match.group(0))

        if not isinstance(payload, dict):
            raise ValueError("Expected a JSON object response")

        return payload

    @staticmethod
    def _strip_markdown_code_fences(content: str) -> str:
        normalized = content.strip()
        if not normalized.startswith("```"):
            return normalized

        normalized = re.sub(r"^```(?:python)?\s*", "", normalized)
        normalized = re.sub(r"\s*```$", "", normalized)
        return normalized.strip()

    async def _responses_create(self, *, instructions: str, user_message: str, reasoning_effort: str | None = None) -> dict:
        if not self.responses_api_url:
            raise RuntimeError("FOUNDRY_ENDPOINT must be configured for Responses API calls")

        payload = {
            "model": self.model,
            "instructions": instructions,
            "input": [
                {
                    "role": "user",
                    "content": user_message,
                }
            ],
            "store": False,
        }

        if reasoning_effort:
            payload["reasoning"] = {"effort": reasoning_effort}

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                self.responses_api_url,
                headers={
                    "Content-Type": "application/json",
                    "api-key": self.api_key,
                },
                json=payload,
            )
            if response.is_error:
                raise RuntimeError(response.text)
            return response.json()

    async def _direct_llm_response(self, message: str) -> str:
        if self.use_responses_api:
            try:
                response = await self._responses_create(
                    instructions="You are a helpful AI assistant. Respond concisely and helpfully.",
                    user_message=message,
                    reasoning_effort="low",
                )
                return self._extract_response_text(response)
            except Exception as e:
                return f"Error: Unable to get response from Foundry. Details: {str(e)}"

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

    async def _detect_calculation_query(self, message: str) -> bool:
        # Quick lexical short-circuit for obvious math requests.
        quick_match = re.search(r"\d+\s*[-+*/^()]\s*\d+|calculate|sum|average|mean|median|percent|percentage|interest|ratio|multiply|divide", message, re.IGNORECASE)
        if quick_match:
            return True

        if self.use_responses_api:
            try:
                response = await self._responses_create(
                    instructions=(
                        "You classify whether a user request requires numeric calculation. "
                        "Return only strict JSON in this exact shape: {\"is_calculation\": true|false}."
                    ),
                    user_message=message,
                    reasoning_effort="low",
                )
                payload = self._parse_json_object(self._extract_response_text(response))
                return bool(payload.get("is_calculation", False))
            except Exception:
                return False

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                temperature=0,
                response_format={"type": "json_object"},
                messages=[
                    {
                        "role": "system",
                        "content": "You classify whether a user request requires numeric calculation. Reply with strict JSON: {\"is_calculation\": true|false}."
                    },
                    {
                        "role": "user",
                        "content": message
                    }
                ]
            )
            payload = json.loads(response.choices[0].message.content or "{}")
            return bool(payload.get("is_calculation", False))
        except Exception:
            return False

    async def _generate_python_script(self, message: str) -> str:
        if self.use_responses_api:
            response = await self._responses_create(
                instructions=(
                    "Generate Python code that performs the user's numeric calculation. "
                    "Return only strict JSON in this exact shape: {\"python_code\": \"...\"}. "
                    "The code must print only the final numeric result with no extra labels."
                ),
                user_message=message,
                reasoning_effort="medium",
            )
            payload = self._parse_json_object(self._extract_response_text(response))
            python_code = self._strip_markdown_code_fences((payload.get("python_code") or "").strip())
            if not python_code:
                raise RuntimeError("LLM did not return python_code")
            return python_code

        response = await self.client.chat.completions.create(
            model=self.model,
            temperature=0,
            response_format={"type": "json_object"},
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Generate Python code that performs the user's numeric calculation. "
                        "Return strict JSON: {\"python_code\": \"...\"}. "
                        "The code must print only the final numeric result with no extra labels."
                    )
                },
                {
                    "role": "user",
                    "content": message
                }
            ]
        )
        payload = json.loads(response.choices[0].message.content or "{}")
        python_code = (payload.get("python_code") or "").strip()
        if not python_code:
            raise RuntimeError("LLM did not return python_code")
        return python_code

    async def _execute_with_dynamic_session(self, python_code: str) -> tuple[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.dynamic_session_executor_api_key:
            headers["Authorization"] = f"Bearer {self.dynamic_session_executor_api_key}"

        async with httpx.AsyncClient(timeout=45.0) as client:
            response = await client.post(
                self.dynamic_session_executor_url,
                headers=headers,
                json={
                    "language": "python",
                    "code": python_code
                }
            )
            response.raise_for_status()
            data = response.json() if response.content else {}

        result = data.get("result") or data.get("output") or data.get("stdout") or ""
        if not result:
            result = json.dumps(data)
        return str(result).strip(), "dynamic-session"

    async def _execute_python_script(self, python_code: str) -> tuple[str, str]:
        if not self.dynamic_session_executor_url:
            raise RuntimeError(
                "No sandboxed execution backend is configured. "
                "Set DYNAMIC_SESSION_EXECUTOR_URL to enable Python execution."
            )
        return await self._execute_with_dynamic_session(python_code)

    async def chat(self, message: str) -> dict:
        """Send message to direct LLM path and optionally a code-execution path for calculations."""
        direct_answer = await self._direct_llm_response(message)
        is_calculation = await self._detect_calculation_query(message)

        if not is_calculation:
            return {
                "message": direct_answer,
                "is_calculation": False,
                "mode": "direct"
            }

        try:
            python_code = await self._generate_python_script(message)
            code_result, execution_backend = await self._execute_python_script(python_code)
            return {
                "message": "Calculation detected. Showing side-by-side outputs for direct LLM reasoning and Python execution.",
                "is_calculation": True,
                "mode": "comparison",
                "direct_response": direct_answer,
                "code_result": code_result,
                "generated_python": python_code,
                "execution_backend": execution_backend
            }
        except Exception as e:
            return {
                "message": f"Direct LLM response is available, but code execution path failed: {str(e)}",
                "is_calculation": True,
                "mode": "comparison",
                "direct_response": direct_answer,
                "code_result": "Execution unavailable",
                "generated_python": "",
                "execution_backend": "failed"
            }

# Singleton instance
_agent = None

def get_agent() -> FoundryAgent:
    global _agent
    if _agent is None:
        _agent = FoundryAgent()
    return _agent
