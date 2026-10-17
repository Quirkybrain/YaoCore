#!/usr/bin/env python3
# Producer: agent:test-engineer | adapted for T-05 / TEST-001 from
# artifacts/10-verification/fixtures/crosscheck_protocol_assets.py
# (sha256 eeaf8f884d6d61e71afd4d93110ea4dbaebc226bfc27351813876a3605ab3530).
# Changes: repository-relative paths (tools/contract, tools/simulator, evidence
# copied from the pinned wp-002 captures). Checks are unchanged.
"""wp-002 cross-checks for input/api/protocol self-consistency.

Independent re-implementation of the documented canonical HMAC rules re-derives
every public test vector, then compares:
  A. schema inventory and JSON-Schema dialect;
  B. hmac-sha256-test-vectors.json against the README control canonical rule;
  C. response-auth / discovery-request vectors against the README rules;
  D. module-hmac-test-vector.json against EXTERNAL_MODULE_PROTOCOL.md;
  E. canonical field coverage against local-control-request.schema.json;
  F. C-001 field-naming evidence (schema vs simulator vs API-spec examples);
  G. result-code table (API spec) vs simulator constants;
  H. BLE identity schema vs API-spec example vs README;
  I. archived original App parser field preferences.

Exit code 0 = every hard check passed; 1 = at least one hard check failed.
"""

from __future__ import annotations

import hashlib
import hmac
import importlib.util
import json
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTOCOL = REPO_ROOT / "input" / "api" / "protocol"
SPEC = REPO_ROOT / "input" / "api" / "Gateway_API_Specification.md"
APP = REPO_ROOT / "input" / "existing" / "original_app"
EVIDENCE = pathlib.Path(__file__).resolve().parent / "evidence"
TOOLS = REPO_ROOT / "tools" / "simulator"

failures: list[str] = []
findings: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> bool:
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))
    if not condition:
        failures.append(name)
    return condition


def finding(name: str, problem_detail: str) -> None:
    """Record an observed inconsistency in the immutable inputs.

    Unlike check(), a finding is expected evidence about the frozen inputs and
    does not make the harness itself fail.
    """
    if problem_detail:
        print(f"[FINDING] {name} -- {problem_detail}")
        findings.append(name)
    else:
        print(f"[OK] {name}")


def note(text: str) -> None:
    print(f"[INFO] {text}")


def load_json(path: pathlib.Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def load_server_module():
    spec = importlib.util.spec_from_file_location(
        "wp002_gateway_contract_server_check", TOOLS / "gateway_contract_server.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def value_atom(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, (int, float)):
        return str(value)
    raise ValueError(f"unsupported value: {value!r}")


def control_canonical(request: dict) -> str:
    payload = request["payload"]
    lines = [
        str(request["request_id"]),
        str(request["cmd_id"]),
        str(request["seq"]),
        str(request["target"]),
        payload["action"],
        value_atom(payload.get("value")),
        str(request["timestamp"]),
        str(request["nonce"]),
        str(request["alg"]),
        str(request["key_id"]),
    ]
    return "\n".join(lines)


def sign(secret: str, canonical: str) -> str:
    return hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()


# --------------------------------------------------------------------------
# A. Schema inventory
# --------------------------------------------------------------------------
print("== A. schema inventory ==")
schema_paths = sorted(PROTOCOL.glob("*.schema.json"))
check("A.1 twelve protocol schemas present", len(schema_paths) == 12, f"count={len(schema_paths)}")
schema_docs = {}
for path in schema_paths:
    document = load_json(path)
    schema_docs[path.name] = document
    check(
        f"A.2 {path.name} draft 2020-12",
        document.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
    )

# --------------------------------------------------------------------------
# B. Control-request HMAC vectors
# --------------------------------------------------------------------------
print("\n== B. hmac-sha256-test-vectors.json vs README control canonical ==")
hmac_vectors = load_json(PROTOCOL / "hmac-sha256-test-vectors.json")
request_schema = schema_docs["local-control-request.schema.json"]
required_fields = set(request_schema["required"])
for vector in hmac_vectors["vectors"]:
    request = vector["request"]
    canonical = control_canonical(request)
    check(f"B canonical[{vector['name']}]", canonical == vector["canonical"])
    recomputed = sign(vector["secret"], canonical)
    check(f"B signature[{vector['name']}]", recomputed == vector["expectedSign"])
    check(f"B request.sign[{vector['name']}]", request["sign"] == vector["expectedSign"])
    check(
        f"B request keys[{vector['name']}] match schema required",
        set(request) == required_fields,
        f"keys={sorted(set(request) ^ required_fields) or 'exact'}",
    )

# --------------------------------------------------------------------------
# C. Response-auth and discovery-request vectors
# --------------------------------------------------------------------------
print("\n== C. response-auth / discovery-request vectors ==")
response_vectors = load_json(PROTOCOL / "response-auth-test-vectors.json")
for vector in response_vectors["vectors"]:
    body_hash = hashlib.sha256(vector["body"].encode("utf-8")).hexdigest()
    check(f"C bodySha256[{vector['name']}]", body_hash == vector["bodySha256"])
    canonical = f"YAOCORE-RESPONSE-V1\n{vector['kind']}\n{vector['correlation']}\n{body_hash}"
    check(
        f"C canonical[{vector['name']}]",
        canonical == vector["canonical"].replace("\\n", "\n"),
    )
    check(f"C signature[{vector['name']}]", sign(vector["secret"], canonical) == vector["signature"])

discovery_vectors = load_json(PROTOCOL / "discovery-request-auth-test-vectors.json")
for vector in discovery_vectors["vectors"]:
    canonical = (
        f"YAOCORE-DISCOVER-V2\n{vector['challenge']}\n{vector['timestamp']}\n"
        f"{vector['nonce']}\n{vector['alg']}\n{vector['key_id']}"
    )
    check(
        f"C discover canonical[{vector['name']}]",
        canonical == vector["canonical"].replace("\\n", "\n"),
    )
    check(f"C discover signature[{vector['name']}]", sign(vector["secret"], canonical) == vector["signature"])

# --------------------------------------------------------------------------
# D. Module HMAC vector
# --------------------------------------------------------------------------
print("\n== D. module-hmac-test-vector.json ==")
module_vector = load_json(PROTOCOL / "module-hmac-test-vector.json")
context = f"YAOCORE-MODULE-KEY-V1\n{module_vector['moduleId']}".encode("utf-8")
module_key = hmac.new(module_vector["masterSecret"].encode("utf-8"), context, hashlib.sha256).digest()
check("D derived key", module_key.hex() == module_vector["derivedModuleKeyHex"])
module_body_hash = hashlib.sha256(module_vector["body"].encode("utf-8")).hexdigest()
check("D body sha256", module_body_hash == module_vector["bodySha256"])
module_canonical = "\n".join(
    [
        "YAOCORE-MODULE-V1",
        module_vector["kind"],
        module_vector["moduleId"],
        module_vector["timestamp"],
        module_vector["nonce"],
        "HMAC-SHA256",
        "app-key-v1",
        module_body_hash,
    ]
)
check("D canonical", module_canonical == module_vector["canonical"])
check("D signature", hmac.new(module_key, module_canonical.encode("utf-8"), hashlib.sha256).hexdigest() == module_vector["signature"])

# --------------------------------------------------------------------------
# E. Canonical field coverage vs schema
# --------------------------------------------------------------------------
print("\n== E. canonical fields vs local-control-request.schema.json ==")
canonical_lines = [
    "request_id", "cmd_id", "seq", "target", "action", "value",
    "timestamp", "nonce", "alg", "key_id",
]
payload_schema = request_schema["properties"]["payload"]
covered = (set(canonical_lines) - {"action", "value"}) | {"payload"}
check(
    "E.1 canonical lines cover schema required minus sign",
    covered == required_fields - {"sign"},
    f"diff={sorted(covered ^ (required_fields - {'sign'})) or 'exact'}",
)
check("E.2 payload properties are exactly action/value", set(payload_schema["properties"]) == {"action", "value"})
check("E.3 payload requires action", payload_schema["required"] == ["action"])
check("E.4 payload closed", payload_schema.get("additionalProperties") is False)
check("E.5 request closed", request_schema.get("additionalProperties") is False)

# --------------------------------------------------------------------------
# F. C-001 field-naming evidence
# --------------------------------------------------------------------------
print("\n== F. C-001 field-naming evidence ==")
discover_schema = schema_docs["discover-response.schema.json"]
ack_schema = schema_docs["local-control-ack.schema.json"]
device_def = discover_schema["$defs"]["device"]
device_props = set(device_def["properties"])
device_required = set(device_def["required"])
ack_device_props = set(ack_schema["$defs"]["deviceState"]["properties"])
ack_gateway_props = set(ack_schema["$defs"]["gatewayState"]["properties"])
ack_device_required = set(ack_schema["$defs"]["deviceState"]["required"])

check("F.1 discover schema requires 'online'", "online" in device_required)
check("F.2 discover schema has no isOnline/powerStatus/openStatus/targetTemperature",
      not ({"isOnline", "powerStatus", "openStatus", "targetTemperature"} & device_props))
check("F.3 discover schema uses power/open/targetTemp",
      {"power", "open", "targetTemp"} <= device_props)
check("F.4 ack schema requires 'online'", "online" in ack_device_required)
check("F.5 ack schema has no camelCase state names",
      not ({"isOnline", "powerStatus", "openStatus", "targetTemperature"} & (ack_device_props | ack_gateway_props)))
check("F.6 ack schema has no 'success' and is closed",
      "success" not in ack_schema["properties"] and ack_schema.get("additionalProperties") is False)

discover_evidence = EVIDENCE / "discover-response.json"
if discover_evidence.exists():
    document = load_json(discover_evidence)
    device_keys: set = set()
    for device in document["devices"]:
        device_keys |= set(device)
    note(f"F simulator /discover device keys: {sorted(device_keys)}")
    check("F.7 simulator device keys are schema-valid", device_keys <= device_props,
          f"unknown={sorted(device_keys - device_props) or 'none'}")
    check("F.8 simulator emits 'online' not 'isOnline'", "online" in device_keys and "isOnline" not in device_keys)
    check("F.9 simulator top-level keys == schema required",
          set(document) == set(discover_schema["required"]),
          f"extra={sorted(set(document) - set(discover_schema['properties'])) or 'none'}")
    check("F.10 simulator security.keyId is app-key-v1", document["security"]["keyId"] == "app-key-v1")
else:
    note("F: evidence/discover-response.json missing; live-capture checks skipped")

ack_evidence = EVIDENCE / "control-ack.json"
if ack_evidence.exists():
    ack = load_json(ack_evidence)
    note(f"F simulator /control ACK keys: {sorted(ack)}")
    check("F.11 simulator ACK keys are schema-valid", set(ack) <= set(ack_schema["properties"]),
          f"unknown={sorted(set(ack) - set(ack_schema['properties'])) or 'none'}")
    check("F.12 simulator ACK has no 'success'", "success" not in ack)
    reported = ack.get("reported_state", {})
    check("F.13 reported_state keys are schema-valid",
          set(reported) <= ack_device_props | ack_gateway_props,
          f"unknown={sorted(set(reported) - (ack_device_props | ack_gateway_props)) or 'none'}")
    check("F.14 reported_state uses 'online'", "online" in reported)
else:
    note("F: evidence/control-ack.json missing; live-capture checks skipped")

spec_text = SPEC.read_text(encoding="utf-8")
spec_lines = spec_text.splitlines()
for token in ('"isOnline"', '"powerStatus"', '"openStatus"', '"targetTemperature"', '"success"', '"displayName"'):
    hits = [index + 1 for index, line in enumerate(spec_lines) if token in line]
    note(f"F spec token {token}: lines {hits or 'none'}")

# Structural comparison of the fenced JSON examples in the API specification.
example_blocks = re.findall(r"```json\n(.*?)```", spec_text, re.DOTALL)
for block in example_blocks:
    try:
        example = json.loads(block)
    except json.JSONDecodeError as error:
        note(f"F unparseable spec example block: {error}")
        continue
    if not isinstance(example, dict):
        continue
    if "devices" in example:
        unknown_top = set(example) - set(discover_schema["properties"])
        finding("F.15 spec discover example top-level keys vs schema",
                f"unknown keys = {sorted(unknown_top)}" if unknown_top else "")
        missing_required = set(discover_schema["required"]) - set(example)
        if missing_required:
            finding("F.15b spec discover example missing schema-required keys",
                    f"missing = {sorted(missing_required)}")
        for device in example["devices"]:
            unknown_device = set(device) - device_props
            finding("F.16 spec discover example device keys vs schema",
                    f"unknown keys = {sorted(unknown_device)}" if unknown_device else "")
    if "result_code" in example:
        unknown_ack = set(example) - set(ack_schema["properties"])
        finding("F.17 spec ACK example keys vs schema",
                f"unknown keys = {sorted(unknown_ack)}" if unknown_ack else "")
        reported = example.get("reported_state", {})
        unknown_reported = set(reported) - (ack_device_props | ack_gateway_props)
        finding("F.18 spec ACK reported_state keys vs schema",
                f"unknown keys = {sorted(unknown_reported)}" if unknown_reported else "")
        missing_reported = sorted(ack_device_required - set(reported))
        if missing_reported:
            finding("F.18b spec ACK reported_state missing schema-required keys",
                    f"missing = {missing_reported}")

# --------------------------------------------------------------------------
# G. Result-code table: API spec vs simulator constants
# --------------------------------------------------------------------------
print("\n== G. result codes ==")
spec_codes: dict[int, str] = {}
for line in spec_lines:
    match = re.match(r"^\|\s*`(\d+)`\s*\|\s*`([A-Z_]+)`\s*\|", line)
    if match:
        spec_codes[int(match.group(1))] = match.group(2)
server = load_server_module()
sim_codes = {
    server.RESULT_INVALID_REQUEST: "INVALID_REQUEST",
    server.RESULT_UNSUPPORTED_SECURITY: "UNSUPPORTED_SECURITY",
    server.RESULT_TIMESTAMP_REJECTED: "TIMESTAMP_REJECTED",
    server.RESULT_BAD_SIGNATURE: "BAD_SIGNATURE",
    server.RESULT_REPLAY: "REPLAY",
    server.RESULT_UNSUPPORTED_COMMAND: "UNSUPPORTED_COMMAND",
    server.RESULT_DEVICE_OFFLINE: "DEVICE_OFFLINE",
}
mismatches = []
for code in sorted(set(spec_codes) | set(sim_codes)):
    spec_name = spec_codes.get(code, "-")
    sim_name = sim_codes.get(code, "-")
    if spec_name != sim_name:
        mismatches.append((code, spec_name, sim_name))
    note(f"G code {code}: spec={spec_name} simulator={sim_name}")
if mismatches:
    for code, spec_name, sim_name in mismatches:
        finding(f"G result code {code}", f"spec={spec_name} simulator={sim_name}")
else:
    finding("G.1 all non-zero result codes match", "")

# --------------------------------------------------------------------------
# H. BLE enrollment identity
# --------------------------------------------------------------------------
print("\n== H. BLE identity schema vs spec ==")
identity_request = schema_docs["ble-enrollment-identity-request.schema.json"]
identity_response = schema_docs["ble-enrollment-identity-response.schema.json"]
check("H.1 request op const", identity_request["properties"]["op"]["const"] == "get_identity")
check("H.2 request closed", identity_request.get("additionalProperties") is False)
check("H.3 response closed", identity_response.get("additionalProperties") is False)
check("H.4 gatewayId length <=63", identity_response["properties"]["gatewayId"]["maxLength"] == 63)
identity_spec_lines = [index + 1 for index, line in enumerate(spec_lines) if "get_identity" in line or '"serviceId":"SmartHomeService"' in line]
note(f"H spec identity example lines: {identity_spec_lines}")
note(f"H schema serviceId const: {identity_response['properties']['serviceId']['const']!r}; "
     f"spec example uses 'SmartHomeService'; schema requires 'gatewayName', spec example shows 'displayName'")

# --------------------------------------------------------------------------
# I. Archived original App parser preferences (wire field evidence)
# --------------------------------------------------------------------------
print("\n== I. archived App parser field preferences ==")
local_gateway = (APP / "service" / "LocalGatewayService.ets").read_text(encoding="utf-8")
discovery_service = (APP / "service" / "GatewayDiscoveryService.ets").read_text(encoding="utf-8")
check("I.1 ACK parser falls back isOnline->online",
      "payload.online === undefined ? payload.isOnline : payload.online" in local_gateway)
check("I.2 ACK parser falls back powerStatus->power",
      "payload.power === undefined ? payload.powerStatus : payload.power" in local_gateway)
check("I.3 ACK parser falls back targetTemperature->targetTemp",
      "payload.targetTemp" in local_gateway and "payload.targetTemperature" in local_gateway)
check("I.4 discovery validator requires security block with HMAC-SHA256/app-key-v1",
      "securityText.indexOf('HMAC-SHA256')" in local_gateway and "securityText.indexOf('app-key-v1')" in local_gateway)
check("I.5 discovery parser also accepts camelCase source keys",
      "item.isOnline === undefined ? item.online : item.isOnline" in discovery_service
      and "item.powerStatus === undefined ? item.power : item.powerStatus" in discovery_service)

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
print("\n== summary ==")
print(f"hard checks: {'ALL PASS' if not failures else str(len(failures)) + ' FAIL'}")
for failure in failures:
    print(f"  FAILED: {failure}")
print(f"findings about frozen inputs: {len(findings)}")
for item in findings:
    print(f"  FINDING: {item}")
sys.exit(1 if failures else 0)
