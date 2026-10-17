#!/usr/bin/env python3
"""Mock-only ACK latency measurement against the DEV contract simulator.

Producer: agent:test-engineer | Task: T-19 / wp-082-verify
Contract: TEST-001 §7.1 (ACK p95 measurement contract); NFR 4.3.

This harness measures localhost HTTP transport + strict JSON parse + ACK
structural checks against the Python simulator. It deliberately does NOT
measure the ArkTS client (no device/emulator), response signature
verification, state application, BLE, real LAN, TLS pinning, or UI frames.
The result class is MOCK_ONLY and must never be reported as product ACK p95.

Usage:
  python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5
  python3 tools/contract/measure_ack_latency.py --samples 100 --json report.json
"""

from __future__ import annotations

import argparse
import http.client
import json
import statistics
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.simulator.gateway_contract_server import (  # noqa: E402
    DEFAULT_KEY_ID,
    PUBLIC_TEST_SECRET,
    GatewayContractState,
    create_server,
    format_timestamp,
    sign_packet,
)


def build_packet(sequence: int, now: datetime) -> dict:
    payload = {"action": "SET_BRIGHTNESS", "value": sequence % 100}
    packet = {
        "request_id": f"perf-ack-{sequence}",
        "cmd_id": 2001,
        "seq": sequence,
        "target": "Light_01",
        "payload": payload,
        "timestamp": format_timestamp(now),
        "nonce": f"{sequence:032x}",
        "alg": "HMAC-SHA256",
        "key_id": DEFAULT_KEY_ID,
    }
    return sign_packet(packet, PUBLIC_TEST_SECRET)


def percentile(sorted_values: list[float], fraction: float) -> float:
    if not sorted_values:
        raise ValueError("no samples")
    index = min(len(sorted_values) - 1, max(0, int(round(fraction * (len(sorted_values) - 1)))))
    return sorted_values[index]


def measure(samples: int, warmup: int) -> dict:
    state = GatewayContractState(log_requests=False)
    server = create_server("127.0.0.1", 0, state)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5.0)
    durations: list[float] = []
    failures: list[str] = []
    try:
        for index in range(warmup + samples):
            packet = build_packet(index + 1, datetime.now(timezone.utc))
            body = json.dumps(packet, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            started = time.perf_counter()
            try:
                connection.request("POST", "/control", body=body,
                                   headers={"Content-Type": "application/json"})
                response = connection.getresponse()
                raw = response.read()
                elapsed_ms = (time.perf_counter() - started) * 1000.0
                document = json.loads(raw.decode("utf-8"))
                if response.status != 200:
                    failures.append(f"status={response.status}")
                    continue
                if document.get("result_code") != 0:
                    failures.append(f"result_code={document.get('result_code')}")
                    continue
                reported = document.get("reported_state") or {}
                if reported.get("deviceId") != "Light_01":
                    failures.append("reported_state.deviceId mismatch")
                    continue
            except Exception as error:  # noqa: BLE001 - report, do not hide
                failures.append(f"{type(error).__name__}: {error}")
                continue
            if index >= warmup:
                durations.append(elapsed_ms)
    finally:
        connection.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    ordered = sorted(durations)
    if not ordered:
        raise SystemExit("ERROR: no successful samples")
    return {
        "metric": "ack.total_ms",
        "resultClass": "MOCK_ONLY",
        "environment": "linux localhost Python stdlib simulator (HTTP)",
        "profile": "P-HMAC / Light_01 / SET_BRIGHTNESS",
        "samples": len(ordered),
        "warmup": warmup,
        "failures": failures,
        "p50Ms": round(statistics.median(ordered), 3),
        "p95Ms": round(percentile(ordered, 0.95), 3),
        "maxMs": round(ordered[-1], 3),
        "minMs": round(ordered[0], 3),
        "limitations": [
            "not product ArkTS client code",
            "excludes response signature verification and state application",
            "excludes BLE, real LAN, TLS pinning and UI frames",
            "must not be used as NFR 4.3 acceptance evidence",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--json", help="write the report to this path")
    args = parser.parse_args()
    if args.samples < 1 or args.warmup < 0:
        print("ERROR: samples must be >= 1 and warmup >= 0", file=sys.stderr)
        return 2
    report = measure(args.samples, args.warmup)
    text = json.dumps(report, indent=2, ensure_ascii=False)
    print(text)
    if args.json:
        path = Path(args.json)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
