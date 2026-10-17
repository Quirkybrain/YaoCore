#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0
#
# Adapted for T-05 / TEST-001 (tools/simulator/).
# Producer: agent:test-engineer
# Origin: input/existing/tools/gateway_contract_server.py
#   sha256 80136a0c6cd6ca6be7c53c9370245e6e597536efae68ff42377a2a53fbd2c352
# Changes are limited to: TLS serving (--tls/--cert/--key), SPKI-SHA256
# startup print, and the T-05 provenance header. Protocol behaviour is
# unchanged from the pinned fixture.

"""YaoCore v2 development gateway contract simulator.

WARNING: this process is only a deterministic HTTP/HTTPS fixture for App and
protocol integration. It is not OpenHarmony firmware, an IoTDA client, a
hardware driver, or evidence that a physical gateway works.

Only the Python standard library is used so the fixture can run in a clean
development environment. The bundled certificate and key under `certs/` are
PUBLIC TEST DATA ONLY and must never be used outside local testing.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import hmac
import json
import math
import os
import pathlib
import re
import ssl
import threading
import time
from datetime import datetime, timezone
from decimal import Decimal
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Mapping
from urllib.parse import urlsplit


PROTOCOL_VERSION = "2.0"
SERVICE_ID = "SmartHomeService"
SIGNATURE_ALGORITHM = "HMAC-SHA256"
CONTROL_COMMAND_ID = 2001
TIME_WINDOW_SECONDS = 120
NONCE_TTL_SECONDS = 300
MAX_BODY_BYTES = 64 * 1024
TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"
PUBLIC_TEST_SECRET = "YaoCore-Contract-Secret-v2"
DEFAULT_KEY_ID = "app-key-v1"

RESULT_INVALID_REQUEST = 1001
RESULT_UNSUPPORTED_SECURITY = 1002
RESULT_TIMESTAMP_REJECTED = 1003
RESULT_BAD_SIGNATURE = 1004
RESULT_REPLAY = 1005
RESULT_UNSUPPORTED_COMMAND = 1006
RESULT_DEVICE_OFFLINE = 1007

IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
ACTION_RE = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")
NONCE_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
SIGNATURE_RE = re.compile(r"^[0-9a-f]{64}$")
TIMESTAMP_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


class ContractError(Exception):
    """Expected protocol rejection with both HTTP and contract result codes."""

    def __init__(self, http_status: int, result_code: int, message: str) -> None:
        super().__init__(message)
        self.http_status = http_status
        self.result_code = result_code
        self.message = message


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def format_timestamp(value: datetime | None = None) -> str:
    current = value if value is not None else utc_now()
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    return current.astimezone(timezone.utc).strftime(TIMESTAMP_FORMAT)


def parse_timestamp(value: str) -> datetime:
    if not isinstance(value, str) or TIMESTAMP_RE.fullmatch(value) is None:
        raise ValueError("timestamp must use yyyyMMddTHHmmssZ")
    return datetime.strptime(value, TIMESTAMP_FORMAT).replace(tzinfo=timezone.utc)


def _read_der_tlv(data: bytes, offset: int) -> tuple[int, int, int]:
    """Return ``(tag, value_start, next_offset)`` for one DER TLV element."""

    if offset + 2 > len(data):
        raise ValueError("truncated DER element")
    tag = data[offset]
    length = data[offset + 1]
    header = 2
    if length & 0x80:
        count = length & 0x7F
        if count == 0 or count > 4 or offset + 2 + count > len(data):
            raise ValueError("unsupported DER length encoding")
        length = int.from_bytes(data[offset + 2:offset + 2 + count], "big")
        header = 2 + count
    value_start = offset + header
    next_offset = value_start + length
    if next_offset > len(data):
        raise ValueError("truncated DER value")
    return tag, value_start, next_offset


def certificate_spki_sha256(cert_path: str | os.PathLike[str]) -> str:
    """Return lowercase hex SHA-256 over the certificate SubjectPublicKeyInfo.

    The pin format used by ADR-002/CB is ``sha256(spki_der)`` as 64 lowercase
    hex characters. Only the Python standard library is used: read the PEM
    certificate, convert it to DER, walk the X.509 structure to the
    ``subjectPublicKeyInfo`` element, then hash the exact DER bytes.
    """

    pem_text = pathlib.Path(cert_path).read_text(encoding="ascii")
    der = ssl.PEM_cert_to_DER_cert(pem_text)

    tag, tbs_start, _ = _read_der_tlv(der, 0)
    if tag != 0x30:
        raise ValueError("certificate is not a DER SEQUENCE")
    tag, tbs_value_start, _ = _read_der_tlv(der, tbs_start)
    if tag != 0x30:
        raise ValueError("tbsCertificate is not a DER SEQUENCE")

    cursor = tbs_value_start
    tag, _, cursor = _read_der_tlv(der, cursor)
    if tag != 0xA0:
        # No [0] EXPLICIT version: the first element was serialNumber, so only
        # four more fields (signature, issuer, validity, subject) remain.
        for _ in range(4):
            tag, _, cursor = _read_der_tlv(der, cursor)
    else:
        # version was consumed; then serialNumber, signature, issuer,
        # validity, and subject.
        for _ in range(5):
            tag, _, cursor = _read_der_tlv(der, cursor)
    spki_start = cursor
    tag, _, spki_end = _read_der_tlv(der, cursor)
    if tag != 0x30:
        raise ValueError("subjectPublicKeyInfo is not a DER SEQUENCE")
    return hashlib.sha256(der[spki_start:spki_end]).hexdigest()


def build_tls_context(cert_path: str, key_path: str) -> ssl.SSLContext:
    """Build a server TLS context from PUBLIC TEST certificate/key files."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certfile=cert_path, keyfile=key_path)
    return context


def _ecmascript_like_number(value: int | float) -> str:
    """Return the compact JSON number form used by ArkTS for domain values.

    Python and ECMAScript use the same shortest-round-trip principle but differ
    in exponent formatting thresholds. Normalizing those thresholds prevents
    common signatures such as 24 and 24.0 from diverging.
    """

    if isinstance(value, bool):
        raise ValueError("boolean is not a number in the protocol")
    if isinstance(value, int):
        return str(value)
    if not math.isfinite(value):
        raise ValueError("command numbers must be finite")
    if value == 0:
        return "0"

    text = repr(value).lower()
    magnitude = abs(value)
    if "e" in text and 1e-6 <= magnitude < 1e21:
        return format(Decimal(text), "f")
    if "e" not in text:
        return text[:-2] if text.endswith(".0") else text

    coefficient, exponent_text = text.split("e", 1)
    coefficient = coefficient[:-2] if coefficient.endswith(".0") else coefficient
    exponent = int(exponent_text)
    sign = "+" if exponent >= 0 else ""
    return f"{coefficient}e{sign}{exponent}"


def encode_json_atom(value: Any) -> str:
    """Encode a permitted command value for the canonical signature line."""

    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return _ecmascript_like_number(value)
    raise ValueError("value must be a string, finite number, or boolean")


def canonicalize_control_request(packet: Mapping[str, Any]) -> str:
    """Build the exact v2 UTF-8 canonical string (without trailing newline)."""

    payload = packet["payload"]
    if not isinstance(payload, Mapping):
        raise ValueError("payload must be an object")
    value_text = "" if "value" not in payload else encode_json_atom(payload["value"])
    lines = [
        str(packet["request_id"]),
        str(packet["cmd_id"]),
        str(packet["seq"]),
        str(packet["target"]),
        str(payload["action"]),
        value_text,
        str(packet["timestamp"]),
        str(packet["nonce"]),
        str(packet["alg"]),
        str(packet["key_id"]),
    ]
    return "\n".join(lines)


def compute_signature(packet: Mapping[str, Any], secret: str) -> str:
    canonical = canonicalize_control_request(packet).encode("utf-8")
    return hmac.new(secret.encode("utf-8"), canonical, hashlib.sha256).hexdigest()


def sign_packet(packet: Mapping[str, Any], secret: str) -> dict[str, Any]:
    result = copy.deepcopy(dict(packet))
    result["sign"] = compute_signature(result, secret)
    return result


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON number is forbidden: {value}")


def _strict_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key is forbidden: {key}")
        result[key] = value
    return result


def decode_strict_json(raw: bytes) -> Any:
    text = raw.decode("utf-8")
    return json.loads(
        text,
        object_pairs_hook=_strict_json_object,
        parse_constant=_reject_json_constant,
    )


def _is_integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _require_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str) or IDENTIFIER_RE.fullmatch(value) is None:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            f"{field} is not a valid identifier",
        )
    return value


def validate_control_request(packet: Any) -> dict[str, Any]:
    if not isinstance(packet, dict):
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "request body must be a JSON object",
        )

    required = {
        "request_id",
        "cmd_id",
        "seq",
        "target",
        "payload",
        "timestamp",
        "nonce",
        "alg",
        "key_id",
        "sign",
    }
    actual = set(packet)
    missing = sorted(required - actual)
    extras = sorted(actual - required)
    if missing:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            f"missing fields: {', '.join(missing)}",
        )
    if extras:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            f"unexpected fields: {', '.join(extras)}",
        )

    _require_identifier(packet["request_id"], "request_id")
    _require_identifier(packet["target"], "target")
    _require_identifier(packet["key_id"], "key_id")
    if not _is_integer(packet["cmd_id"]) or packet["cmd_id"] != CONTROL_COMMAND_ID:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            f"cmd_id must be {CONTROL_COMMAND_ID}",
        )
    if not _is_integer(packet["seq"]) or not 0 <= packet["seq"] <= 2147483647:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "seq must be an integer between 0 and 2147483647",
        )

    payload = packet["payload"]
    if not isinstance(payload, dict):
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "payload must be a JSON object",
        )
    if set(payload) - {"action", "value"}:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "payload contains unexpected fields",
        )
    action = payload.get("action")
    if not isinstance(action, str) or ACTION_RE.fullmatch(action) is None:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "payload.action is invalid",
        )
    if "value" in payload:
        try:
            encode_json_atom(payload["value"])
        except ValueError as error:
            raise ContractError(
                HTTPStatus.BAD_REQUEST,
                RESULT_INVALID_REQUEST,
                str(error),
            ) from error

    timestamp = packet["timestamp"]
    try:
        parse_timestamp(timestamp)
    except ValueError as error:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            str(error),
        ) from error
    nonce = packet["nonce"]
    if not isinstance(nonce, str) or NONCE_RE.fullmatch(nonce) is None:
        raise ContractError(
            HTTPStatus.BAD_REQUEST,
            RESULT_INVALID_REQUEST,
            "nonce must contain 8 to 64 URL-safe characters",
        )
    if packet["alg"] != SIGNATURE_ALGORITHM:
        raise ContractError(
            HTTPStatus.UNAUTHORIZED,
            RESULT_UNSUPPORTED_SECURITY,
            f"alg must be {SIGNATURE_ALGORITHM}",
        )
    signature = packet["sign"]
    if not isinstance(signature, str) or SIGNATURE_RE.fullmatch(signature) is None:
        raise ContractError(
            HTTPStatus.UNAUTHORIZED,
            RESULT_BAD_SIGNATURE,
            "sign must be 64 lowercase hexadecimal characters",
        )
    return packet


class NonceReplayCache:
    def __init__(
        self,
        ttl_seconds: int = NONCE_TTL_SECONDS,
        monotonic_clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.ttl_seconds = ttl_seconds
        self.monotonic_clock = monotonic_clock
        self._seen: dict[
            tuple[str, str],
            tuple[float, tuple[Any, ...], int, dict[str, Any]],
        ] = {}
        self._lock = threading.Lock()

    def _purge_expired(self, now: float) -> None:
        cutoff = now - self.ttl_seconds
        expired = [
            key
            for key, (seen_at, _identity, _status, _ack) in self._seen.items()
            if seen_at <= cutoff
        ]
        for key in expired:
            del self._seen[key]

    def lookup(
        self,
        key_id: str,
        nonce: str,
        identity: tuple[Any, ...],
    ) -> tuple[str, int | None, dict[str, Any] | None]:
        """Return ``miss``, ``exact``, or ``conflict`` for a nonce identity."""

        now = self.monotonic_clock()
        with self._lock:
            self._purge_expired(now)
            cache_key = (key_id, nonce)
            cached = self._seen.get(cache_key)
            if cached is None:
                return "miss", None, None
            _seen_at, cached_identity, http_status, acknowledgement = cached
            if cached_identity != identity:
                return "conflict", None, None
            return "exact", http_status, copy.deepcopy(acknowledgement)

    def store(
        self,
        key_id: str,
        nonce: str,
        identity: tuple[Any, ...],
        http_status: int,
        acknowledgement: Mapping[str, Any],
    ) -> None:
        now = self.monotonic_clock()
        with self._lock:
            self._purge_expired(now)
            cache_key = (key_id, nonce)
            if cache_key in self._seen:
                raise RuntimeError("nonce cache entry changed during request processing")
            self._seen[cache_key] = (
                now,
                identity,
                int(http_status),
                copy.deepcopy(dict(acknowledgement)),
            )


class GatewayContractState:
    """Thread-safe state and protocol validation for the development fixture."""

    def __init__(
        self,
        secret: str = PUBLIC_TEST_SECRET,
        key_id: str = DEFAULT_KEY_ID,
        gateway_id: str = "gateway_01",
        gateway_name: str = "YaoCore DEV Contract Simulator",
        clock: Callable[[], datetime] = utc_now,
        monotonic_clock: Callable[[], float] = time.monotonic,
        log_requests: bool = True,
    ) -> None:
        if not secret:
            raise ValueError("simulator secret must not be empty")
        _require_identifier(key_id, "key_id")
        _require_identifier(gateway_id, "gateway_id")
        self.keys = {key_id: secret}
        self.key_id = key_id
        self.gateway_id = gateway_id
        self.gateway_name = gateway_name
        self.clock = clock
        self.log_requests = log_requests
        self.nonces = NonceReplayCache(NONCE_TTL_SECONDS, monotonic_clock)
        initial_time = format_timestamp(self.clock())
        self._lock = threading.RLock()
        self._request_lock = threading.Lock()
        self._execution_counts: dict[str, int] = {}
        self._board_led = False
        self._devices: dict[str, dict[str, Any]] = {
            "Door_01": {
                "deviceId": "Door_01",
                "deviceName": "智能门禁",
                "roomName": "玄关",
                "deviceType": "door",
                "brand": "YaoCore-Simulator",
                "online": True,
                "open": False,
                "updatedAt": initial_time,
            },
            "Light_01": {
                "deviceId": "Light_01",
                "deviceName": "客厅灯光",
                "roomName": "客厅",
                "deviceType": "light",
                "brand": "YaoCore-Simulator",
                "online": True,
                "power": True,
                "brightness": 68,
                "updatedAt": initial_time,
            },
            "Sensor_01": {
                "deviceId": "Sensor_01",
                "deviceName": "温湿度传感器",
                "roomName": "客厅",
                "deviceType": "sensor",
                "brand": "YaoCore-Simulator",
                "online": True,
                "temperature": 26.8,
                "humidity": 58.0,
                "updatedAt": initial_time,
            },
            "AC_01": {
                "deviceId": "AC_01",
                "deviceName": "客厅空调",
                "roomName": "客厅",
                "deviceType": "ac",
                "brand": "YaoCore-Simulator",
                "online": True,
                "power": True,
                "targetTemp": 24,
                "mode": "COOL",
                "updatedAt": initial_time,
            },
        }

    def discovery_document(self) -> dict[str, Any]:
        with self._lock:
            devices = [copy.deepcopy(device) for device in self._devices.values()]
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "gatewayId": self.gateway_id,
            "gatewayName": self.gateway_name,
            "serviceId": SERVICE_ID,
            "generatedAt": format_timestamp(self.clock()),
            "security": {
                "alg": SIGNATURE_ALGORITHM,
                "keyId": self.key_id,
                "timeWindowSeconds": TIME_WINDOW_SECONDS,
                "nonceTtlSeconds": NONCE_TTL_SECONDS,
            },
            "devices": devices,
        }

    def health_document(self) -> dict[str, Any]:
        return {
            "simulator": True,
            "protocolVersion": PROTOCOL_VERSION,
            "gatewayId": self.gateway_id,
            "status": "DEV_SIMULATOR_ONLY",
            "serverTime": format_timestamp(self.clock()),
        }

    def execution_count(self, request_id: str) -> int:
        """Expose deterministic execution counts for contract tests only."""

        with self._lock:
            return self._execution_counts.get(request_id, 0)

    def error_ack(self, packet: Any, error: ContractError) -> dict[str, Any]:
        request_id = "invalid-request"
        seq = 0
        if isinstance(packet, dict):
            candidate_id = packet.get("request_id")
            candidate_seq = packet.get("seq")
            if isinstance(candidate_id, str) and IDENTIFIER_RE.fullmatch(candidate_id):
                request_id = candidate_id
            if _is_integer(candidate_seq) and 0 <= candidate_seq <= 2147483647:
                seq = candidate_seq
        return {
            "request_id": request_id,
            "seq": seq,
            "result_code": error.result_code,
            "message": error.message,
            "server_time": format_timestamp(self.clock()),
        }

    def process_control(self, packet: Any) -> tuple[int, dict[str, Any]]:
        command = validate_control_request(packet)
        key_id = command["key_id"]
        secret = self.keys.get(key_id)
        if secret is None:
            raise ContractError(
                HTTPStatus.UNAUTHORIZED,
                RESULT_UNSUPPORTED_SECURITY,
                "unknown key_id",
            )

        canonical = canonicalize_control_request(command)
        identity = (
            key_id,
            command["nonce"],
            command["request_id"],
            command["seq"],
            command["sign"],
            canonical,
        )

        # Keep lookup, verification, execution, and cache insertion atomic. This
        # makes simultaneous ACK-lost retries observe one original execution.
        with self._request_lock:
            replay_kind, cached_status, cached_ack = self.nonces.lookup(
                key_id,
                command["nonce"],
                identity,
            )
            if replay_kind == "exact":
                if cached_status is None or cached_ack is None:
                    raise RuntimeError("exact replay cache entry is incomplete")
                cached_ack["idempotent_replay"] = True
                return cached_status, cached_ack
            if replay_kind == "conflict":
                raise ContractError(
                    HTTPStatus.CONFLICT,
                    RESULT_REPLAY,
                    "nonce was already used by a different authenticated request",
                )

            command_time = parse_timestamp(command["timestamp"])
            now = self.clock()
            if now.tzinfo is None:
                now = now.replace(tzinfo=timezone.utc)
            skew = abs((now.astimezone(timezone.utc) - command_time).total_seconds())
            if skew > TIME_WINDOW_SECONDS:
                raise ContractError(
                    HTTPStatus.UNAUTHORIZED,
                    RESULT_TIMESTAMP_REJECTED,
                    f"timestamp is outside the {TIME_WINDOW_SECONDS}-second window",
                )

            expected = compute_signature(command, secret)
            if not hmac.compare_digest(expected, command["sign"]):
                raise ContractError(
                    HTTPStatus.UNAUTHORIZED,
                    RESULT_BAD_SIGNATURE,
                    "signature verification failed",
                )

            with self._lock:
                request_id = command["request_id"]
                self._execution_counts[request_id] = (
                    self._execution_counts.get(request_id, 0) + 1
                )

            try:
                reported_state = self._execute(command)
                http_status = int(HTTPStatus.OK)
                acknowledgement = {
                    "request_id": command["request_id"],
                    "seq": command["seq"],
                    "result_code": 0,
                    "message": "command executed by DEV simulator",
                    "server_time": format_timestamp(self.clock()),
                    "reported_state": reported_state,
                }
            except ContractError as error:
                http_status = int(error.http_status)
                acknowledgement = self.error_ack(command, error)

            self.nonces.store(
                key_id,
                command["nonce"],
                identity,
                http_status,
                acknowledgement,
            )
            return http_status, acknowledgement

    def _execute(self, command: Mapping[str, Any]) -> dict[str, Any]:
        target = command["target"]
        payload = command["payload"]
        action = payload["action"]
        has_value = "value" in payload
        value = payload.get("value")
        updated_at = format_timestamp(self.clock())

        with self._lock:
            if target == self.gateway_id:
                if action == "PING" and not has_value:
                    pass
                elif action == "BOARD_LED_ON" and value is True:
                    self._board_led = True
                elif action == "BOARD_LED_OFF" and value is False:
                    self._board_led = False
                else:
                    raise ContractError(
                        HTTPStatus.UNPROCESSABLE_ENTITY,
                        RESULT_UNSUPPORTED_COMMAND,
                        "unsupported gateway action or value",
                    )
                return {
                    "gatewayId": self.gateway_id,
                    "online": True,
                    "boardLed": self._board_led,
                    "updatedAt": updated_at,
                }

            device = self._devices.get(target)
            if device is None:
                raise ContractError(
                    HTTPStatus.UNPROCESSABLE_ENTITY,
                    RESULT_UNSUPPORTED_COMMAND,
                    "unknown target device",
                )
            if not device["online"]:
                raise ContractError(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    RESULT_DEVICE_OFFLINE,
                    "target device is offline",
                )

            device_type = device["deviceType"]
            if device_type == "door":
                if action == "OPEN" and not has_value:
                    device["open"] = True
                elif action == "CLOSE" and not has_value:
                    device["open"] = False
                else:
                    self._unsupported_device_action()
            elif device_type == "light":
                if action == "ON" and not has_value:
                    device["power"] = True
                elif action == "OFF" and not has_value:
                    device["power"] = False
                elif (
                    action == "SET_BRIGHTNESS"
                    and has_value
                    and _is_number(value)
                    and math.isfinite(float(value))
                    and 0 <= value <= 100
                ):
                    device["brightness"] = value
                    device["power"] = value > 0
                else:
                    self._unsupported_device_action()
            elif device_type == "ac":
                if action == "ON" and not has_value:
                    device["power"] = True
                elif action == "OFF" and not has_value:
                    device["power"] = False
                elif (
                    action == "SET_TARGET_TEMPERATURE"
                    and has_value
                    and _is_number(value)
                    and math.isfinite(float(value))
                    and 16 <= value <= 30
                ):
                    device["targetTemp"] = value
                    device["power"] = True
                elif (
                    action == "SET_MODE"
                    and has_value
                    and isinstance(value, str)
                    and 0 < len(value) <= 32
                ):
                    device["mode"] = value
                else:
                    self._unsupported_device_action()
            else:
                self._unsupported_device_action()

            device["updatedAt"] = updated_at
            return self._reported_device_state(device)

    @staticmethod
    def _unsupported_device_action() -> None:
        raise ContractError(
            HTTPStatus.UNPROCESSABLE_ENTITY,
            RESULT_UNSUPPORTED_COMMAND,
            "unsupported device action or value",
        )

    @staticmethod
    def _reported_device_state(device: Mapping[str, Any]) -> dict[str, Any]:
        allowed = {
            "deviceId",
            "online",
            "power",
            "open",
            "brightness",
            "temperature",
            "humidity",
            "targetTemp",
            "mode",
            "updatedAt",
        }
        return {key: copy.deepcopy(value) for key, value in device.items() if key in allowed}


class GatewayContractRequestHandler(BaseHTTPRequestHandler):
    """HTTP surface for the development-only contract state."""

    server_version = "YaoCoreGatewayContractDEVSimulator/2.0"

    @property
    def contract_state(self) -> GatewayContractState:
        return getattr(self.server, "contract_state")

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        path = urlsplit(self.path).path
        if path == "/discover":
            self._write_json(HTTPStatus.OK, self.contract_state.discovery_document())
            return
        if path == "/health":
            self._write_json(HTTPStatus.OK, self.contract_state.health_document())
            return
        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"simulator": True, "error": "not_found", "message": "unknown endpoint"},
        )

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        path = urlsplit(self.path).path
        if path != "/control":
            self._write_json(
                HTTPStatus.NOT_FOUND,
                {"simulator": True, "error": "not_found", "message": "unknown endpoint"},
            )
            return

        packet: Any = {}
        try:
            packet = self._read_json_body()
            http_status, acknowledgement = self.contract_state.process_control(packet)
            self._write_json(http_status, acknowledgement)
        except ContractError as error:
            self._write_json(
                error.http_status,
                self.contract_state.error_ack(packet, error),
            )
        except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as error:
            contract_error = ContractError(
                HTTPStatus.BAD_REQUEST,
                RESULT_INVALID_REQUEST,
                f"invalid JSON body: {error}",
            )
            self._write_json(
                contract_error.http_status,
                self.contract_state.error_ack(packet, contract_error),
            )

    def _read_json_body(self) -> Any:
        content_type = self.headers.get("Content-Type", "").lower()
        if not content_type.startswith("application/json"):
            raise ContractError(
                HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
                RESULT_INVALID_REQUEST,
                "Content-Type must be application/json",
            )
        length_text = self.headers.get("Content-Length")
        if length_text is None:
            raise ContractError(
                HTTPStatus.LENGTH_REQUIRED,
                RESULT_INVALID_REQUEST,
                "Content-Length is required",
            )
        try:
            length = int(length_text)
        except ValueError as error:
            raise ContractError(
                HTTPStatus.BAD_REQUEST,
                RESULT_INVALID_REQUEST,
                "Content-Length is invalid",
            ) from error
        if length <= 0:
            raise ContractError(
                HTTPStatus.BAD_REQUEST,
                RESULT_INVALID_REQUEST,
                "request body is empty",
            )
        if length > MAX_BODY_BYTES:
            raise ContractError(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                RESULT_INVALID_REQUEST,
                f"request body exceeds {MAX_BODY_BYTES} bytes",
            )
        return decode_strict_json(self.rfile.read(length))

    def _write_json(self, status: int, document: Any) -> None:
        body = json.dumps(
            document,
            ensure_ascii=False,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-YaoCore-Simulator", "DEV-ONLY")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_text: str, *args: Any) -> None:
        if self.contract_state.log_requests:
            message = format_text % args
            print(f"[YaoCore DEV SIMULATOR] {self.client_address[0]} {message}")


class GatewayContractHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def create_server(
    host: str,
    port: int,
    state: GatewayContractState,
) -> GatewayContractHTTPServer:
    server = GatewayContractHTTPServer((host, port), GatewayContractRequestHandler)
    setattr(server, "contract_state", state)
    return server


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="YaoCore v2 DEVELOPMENT contract simulator (not gateway firmware)",
    )
    parser.add_argument("--host", default="127.0.0.1", help="listen address")
    parser.add_argument("--port", type=int, default=9200, help="listen port")
    parser.add_argument("--gateway-id", default="gateway_01")
    parser.add_argument("--gateway-name", default="YaoCore DEV Contract Simulator")
    parser.add_argument(
        "--secret",
        default=os.environ.get("YAOCORE_SIMULATOR_SECRET", PUBLIC_TEST_SECRET),
        help="development HMAC secret; environment YAOCORE_SIMULATOR_SECRET is preferred",
    )
    parser.add_argument("--quiet", action="store_true", help="disable request logs")
    parser.add_argument(
        "--tls",
        action="store_true",
        help="serve HTTPS instead of HTTP (requires --cert and --key)",
    )
    parser.add_argument(
        "--cert",
        help="PEM certificate for --tls; PUBLIC TEST DATA ONLY",
    )
    parser.add_argument(
        "--key",
        help="PEM private key for --tls; PUBLIC TEST DATA ONLY",
    )
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    if args.tls and (not args.cert or not args.key):
        print("ERROR: --tls requires --cert and --key")
        return 2
    if not args.tls and (args.cert or args.key):
        print("ERROR: --cert/--key require --tls")
        return 2

    tls_context: ssl.SSLContext | None = None
    spki = ""
    if args.tls:
        tls_context = build_tls_context(args.cert, args.key)
        spki = certificate_spki_sha256(args.cert)
        if re.fullmatch(r"[0-9a-f]{64}", spki) is None:
            print("ERROR: computed SPKI-SHA256 is not 64 lowercase hex characters")
            return 2

    state = GatewayContractState(
        secret=args.secret,
        key_id=DEFAULT_KEY_ID,
        gateway_id=args.gateway_id,
        gateway_name=args.gateway_name,
        log_requests=not args.quiet,
    )
    server = create_server(args.host, args.port, state)
    scheme = "https" if tls_context is not None else "http"
    if tls_context is not None:
        server.socket = tls_context.wrap_socket(server.socket, server_side=True)
    print("=" * 72)
    print("YaoCore DEVELOPMENT CONTRACT SIMULATOR ONLY")
    print("This is not OpenHarmony firmware and does not connect to IoTDA/hardware.")
    print(f"Listening on {scheme}://{args.host}:{server.server_address[1]}")
    if spki:
        print(f"SPKI-SHA256: {spki}")
        print("TLS certificate/key are PUBLIC TEST DATA ONLY; never use in production.")
    if args.secret == PUBLIC_TEST_SECRET:
        print("Using the public test-vector secret; never use it outside local testing.")
    print("=" * 72)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        print("\nStopping DEV simulator.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
