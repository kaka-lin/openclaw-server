from datetime import datetime
from typing import Any


def fmt_ts(ms: int | None) -> str:
    """Convert epoch milliseconds to readable local time string."""
    if ms is None:
        return "N/A"

    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return str(ms)


def fmt_cost(cost: float | None) -> str:
    """Format USD cost."""
    if cost is None:
        return "N/A"

    try:
        return f"${cost:.6f}"
    except Exception:
        return str(cost)


def print_sessions_summary(sessions: list[dict[str, Any]]) -> None:
    """Print a compact summary table for sessions."""
    print(f"✅ 成功列出 {len(sessions)} 個 Sessions\n")

    if not sessions:
        print("（沒有可顯示的 session）")
        return

    print(
        f"{'#':<3} "
        f"{'Display Name':<18} "
        f"{'Model':<28} "
        f"{'Status':<10} "
        f"{'Runtime(ms)':>12}"
    )
    print("-" * 80)

    for idx, s in enumerate(sessions, start=1):
        display_name = str(s.get("displayName", "N/A"))[:18]
        model = str(s.get("model", "N/A"))[:28]
        status = str(s.get("status", "N/A"))[:10]
        runtime_ms = str(s.get("runtimeMs", "N/A"))

        print(
            f"{idx:<3} "
            f"{display_name:<18} "
            f"{model:<28} "
            f"{status:<10} "
            f"{runtime_ms:>12}"
        )

    print()


def print_sessions_details(sessions: list[dict[str, Any]]) -> None:
    """Pretty print sessions as detailed cards."""
    if not sessions:
        return

    for idx, s in enumerate(sessions, start=1):
        print("=" * 80)
        print(f"[Session {idx}] {s.get('displayName', 'N/A')}")
        print("-" * 80)
        print(f"Key            : {s.get('key', 'N/A')}")
        print(f"Session ID     : {s.get('sessionId', 'N/A')}")
        print(f"Model          : {s.get('model', 'N/A')}")
        print(f"Status         : {s.get('status', 'N/A')}")
        print(f"Kind           : {s.get('kind', 'N/A')}")
        print(f"Channel        : {s.get('channel', 'N/A')}")
        print(f"Last To        : {s.get('lastTo', 'N/A')}")
        print(f"Updated At     : {fmt_ts(s.get('updatedAt'))}")
        print(f"Started At     : {fmt_ts(s.get('startedAt'))}")
        print(f"Ended At       : {fmt_ts(s.get('endedAt'))}")
        print(f"Runtime        : {s.get('runtimeMs', 'N/A')} ms")
        print(f"Context Tokens : {s.get('contextTokens', 'N/A')}")
        print(f"Total Tokens   : {s.get('totalTokens', 'N/A')}")
        print(f"Est. Cost      : {fmt_cost(s.get('estimatedCostUsd'))}")
        print(f"System Sent    : {s.get('systemSent', 'N/A')}")
        print(f"Aborted        : {s.get('abortedLastRun', 'N/A')}")
        print(f"Transcript     : {s.get('transcriptPath', 'N/A')}")
        print()

    print("=" * 80)
    print()