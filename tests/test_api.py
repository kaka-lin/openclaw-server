"""Test script for OpenClaw APIs.

This script tests the three main OpenClaw APIs:
1. OpenAI Chat Completions
2. OpenResponses API
3. Tools Invoke API

Prerequisites:
    pip install -r tests/requirements.txt
"""

import os

import requests
from dotenv import load_dotenv

from utils.print_utils import print_sessions_details, print_sessions_summary

# Load environment variables from .env file
load_dotenv()


def get_token() -> str:
    """Retrieve the OpenClaw Gateway token from environment variables."""
    token = os.getenv("OPENCLAW_GATEWAY_TOKEN")
    if not token:
        raise ValueError(
            "OPENCLAW_GATEWAY_TOKEN not found. "
            "Please ensure it is set in your environment or .env file."
        )
    return token


def get_gateway_url() -> str:
    """Retrieve the Gateway URL from environment variables."""
    host = os.getenv("OPENCLAW_GATEWAY_HOST", "localhost")
    port = os.getenv("OPENCLAW_GATEWAY_PORT", "18789")
    return f"http://{host}:{port}"


def test_openai_chat_completions(base_url: str, token: str) -> None:
    """Test the OpenAI-compatible Chat Completions endpoint."""
    print("--- [1] Testing OpenAI Chat Completions API ---")
    url = f"{base_url}/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": "openclaw/default",
        "messages": [{"role": "user", "content": "測試"}],
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)

        if response.status_code == 200:
            data = response.json()

            if "choices" in data and len(data["choices"]) > 0:
                print("Response Base Keys:", list(data.keys()))
                reply = data["choices"][0]["message"]["content"]
                print(f"🤖 AI 回應預覽: {reply}")
            else:
                print("❌ 格式錯誤: 找不到 'choices' 欄位")
                print(f"📝 原始回應: {data}")
        else:
            print(f"❌ OpenAI API 呼叫失敗，Status Code: {response.status_code}")
            print(f"📝 錯誤訊息: {response.text}")

    except requests.exceptions.RequestException as e:
        print(f"Error testing Chat Completions: {e}")

    print("\n")


def test_openresponses_api(base_url: str, token: str) -> None:
    """Test the native OpenResponses API endpoint."""
    print("--- [2] Testing OpenResponses API ---")
    url = f"{base_url}/v1/responses"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "x-openclaw-agent-id": "main",
    }
    payload = {
        "model": "openclaw",
        "input": "Hello via OpenResponses API!",
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)

        if response.status_code == 200:
            data = response.json()

            if "output" in data and len(data["output"]) > 0:
                first_output = data["output"][0]
                if "content" in first_output and len(first_output["content"]) > 0:
                    text = first_output["content"][0].get("text", "")
                    print(f"🤖 AI 回應預覽: {text}")
                else:
                    print("Response (Unexpected Content):", data)
            else:
                print("Response (No Output):", data)
        else:
            print(f"❌ OpenResponses API 呼叫失敗，Status Code: {response.status_code}")
            print(f"📝 錯誤訊息: {response.text}")

    except requests.exceptions.RequestException as e:
        print(f"Error testing OpenResponses: {e}")

    print("\n")


def test_tools_invoke_api(base_url: str, token: str) -> None:
    """Test the Tools Invoke API endpoint by listing sessions."""
    print("--- [3] Testing Tools Invoke API ---")
    url = f"{base_url}/tools/invoke"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "x-openclaw-agent-id": "main",
    }
    payload = {
        "tool": "sessions_list",
        "action": "json",
        "args": {},
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)

        if response.status_code == 200:
            data = response.json()

            if data.get("ok"):
                result = data.get("result", {})
                details = result.get("details", {})
                sessions = details.get("sessions")

                if isinstance(sessions, list):
                    print_sessions_summary(sessions)
                    print_sessions_details(sessions)
                else:
                    print("Response (OK but unexpected data structure):", data)
            else:
                print("❌ 工具執行失敗 (ok=False):", data)
        else:
            print(f"❌ Tools Invoke API 呼叫失敗，Status Code: {response.status_code}")
            print(f"📝 錯誤訊息: {response.text}")

    except requests.exceptions.RequestException as e:
        print(f"Error testing Tools Invoke: {e}")

    print("\n")


def main() -> None:
    """Run all API tests."""
    try:
        token = get_token()
        gateway_url = get_gateway_url()
        print("Configuration loaded successfully from .env.")
        print(f"Gateway URL: {gateway_url}\n")
    except Exception as e:
        print(f"Initialization Error: {e}")
        return

    test_openai_chat_completions(gateway_url, token)
    test_openresponses_api(gateway_url, token)
    test_tools_invoke_api(gateway_url, token)


if __name__ == "__main__":
    main()