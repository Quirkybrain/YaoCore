# YaoCore protocol v2 contract

This directory is the machine-readable contract shared by the
HarmonyOS/OpenHarmony app, the ESP32-S3M gateway firmware, and cloud adapters.
The Python server under `tools/` is a **development simulator only**. It is not
gateway firmware or proof of hardware integration.

## Files

- `discover-response.schema.json`: `GET /discover` response.
- `local-control-request.schema.json`: signed `POST /control` request.
- `local-control-ack.schema.json`: execution acknowledgement returned by the
  gateway.
- `cloud-command.schema.json`: IoTDA command envelope delivered to a gateway.
- `state-report.schema.json`: IoTDA `SmartHomeService` property report.
- `ble-enrollment-identity-request.schema.json` / `ble-enrollment-identity-response.schema.json`:
  Security1 保护的 `yaocore-id` 配网身份关联端点。
- `hmac-sha256-test-vectors.json`: cross-language signature fixtures. Every
  secret in that file is public test data and must never be used in production.
- `response-auth-test-vectors.json`: authenticated discovery/ACK response
  fixtures. Its secret is public test data too.
- `discovery-request-auth-test-vectors.json`: replay-resistant authenticated
  `GET /discover` request fixture. Its secret is public test data too.
- `module-*.schema.json`: authenticated external sensor/actuator module
  registration, heartbeat, state, command and physical-state ACK contracts.
- `module-hmac-test-vector.json`: per-module derived-key interoperability
  fixture. Its master secret and derived key are public test data.

The complete external-module integration guide is
[`docs/EXTERNAL_MODULE_PROTOCOL.md`](../docs/EXTERNAL_MODULE_PROTOCOL.md).

All timestamps use UTC `yyyyMMddTHHmmssZ`, for example
`20260714T080000Z`.

## BLE enrollment identity

After Protocomm Security1 + PoP succeeds and before sending Wi-Fi credentials,
the App sends the request schema to the custom `yaocore-id` endpoint. The
response contains only `serviceId`, protocol version, gateway ID, and display
name. It never contains the PoP, local command HMAC secret, Wi-Fi password, or
cloud credentials.

Current gateways disable provisioning auto-stop until the App has received the
connected status and final IPv4 address. The App then sends
`{"op":"finish","protocolVersion":"2.0"}` to the Security1-protected
`yaocore-done` endpoint; the gateway acknowledges it before releasing BLE.

After Wi-Fi association, the App first probes the IP returned by provisioning
with exponential backoff. Binding is permitted only when an authenticated
`GET /discover` at that address has exactly the `gatewayId` returned inside the
Security1 session. BLE name/MAC suffix and unauthenticated UDP are locators, not
identity evidence. The App then retains the existing board-LED execution check
before saving the route.

## Local control signature

The request contains these top-level fields:

`request_id`, `cmd_id`, `seq`, `target`, `payload`, `timestamp`, `nonce`,
`alg`, `key_id`, and `sign`.

The UTF-8 canonical string has no trailing newline and is exactly:

```text
request_id
cmd_id
seq
target
action
value
timestamp
nonce
alg
key_id
```

The fifth and sixth lines come from `payload.action` and `payload.value`.
`value` is encoded as one JSON atom:

- absent: an empty string (the canonical form therefore contains a blank line);
- string: JSON string syntax, including quotes and escapes;
- boolean: `true` or `false`;
- number: its finite, compact JSON number representation.

`null`, arrays, and objects are not valid command values. `sign` is
`hex_lower(HMAC-SHA256(secret, canonical_utf8))`. Implementations must compare
signatures in constant time.

The gateway accepts a timestamp skew of at most 120 seconds and remembers each
successfully authenticated `(key_id, nonce)` for 300 seconds. A nonce is added
to the replay cache only after all structural, timestamp, and signature checks
have passed.

During that 300-second cache lifetime, an exact authenticated retransmission
of the same request does not execute again. Exact means the same `key_id`,
`nonce`, `request_id`, `seq`, `sign`, and every field covered by the canonical
signature string. The gateway returns the original HTTP status and cached ACK,
optionally adding `idempotent_replay: true`. This cache lookup intentionally
precedes the 120-second freshness check so an ACK-lost retry can still recover
the original result. Reusing the same `(key_id, nonce)` with any different
signed field or signature is a conflict and returns HTTP 409 with
`result_code=1005` (`REPLAY`). Invalid timestamps and signatures are never
cached and therefore do not consume a nonce.

The App/gateway interoperability key identifier for v2 is `app-key-v1`.
Changing the key material does not change that identifier until a coordinated
key-version rollout is performed.

## Local response authentication

Plain HTTP is used only as a transport on the trusted home LAN; discovery
requests and both discovery/control responses are authenticated at the message
layer. For `GET /discover`, the App sends a fresh 16-byte lowercase hexadecimal
value in `X-YaoCore-Challenge`, a fresh 16-byte lowercase hexadecimal nonce in
`X-YaoCore-Request-Nonce`, compact UTC in `X-YaoCore-Request-Timestamp`, plus
`X-YaoCore-Request-Alg`, `X-YaoCore-Key-Id`, and
`X-YaoCore-Request-Sign`. The request canonical form has no trailing newline:

```text
YAOCORE-DISCOVER-V2
challenge
timestamp
nonce
HMAC-SHA256
app-key-v1
```

The gateway verifies the HMAC before consulting the signed time, accepts at
most ±120 seconds of clock skew, and rejects reuse of the same `(key_id, nonce)`
for 300 seconds. Thus a captured request cannot be replayed indefinitely or
twice within its validity window. The gateway returns a device snapshot only
after all checks pass. UDP discovery is an unauthenticated locator and therefore
returns gateway identity/port only, never device state. For `POST /control`,
response correlation is the already signed `request_id` followed by `:` and
decimal `seq`.

The gateway returns these headers:

- `X-YaoCore-Response-Alg: HMAC-SHA256`;
- `X-YaoCore-Key-Id: app-key-v1`;
- `X-YaoCore-Response-Correlation: <challenge-or-request_id:seq>`;
- `X-YaoCore-Response-Sign: <64 lowercase hex characters>`.

The UTF-8 canonical form has no trailing newline:

```text
YAOCORE-RESPONSE-V1
kind
correlation
sha256_lower_hex(response_body_utf8)
```

`kind` is exactly `discover` or `control`. The signature is
`hex_lower(HMAC-SHA256(secret, canonical_utf8))` and is compared in constant
time. A discovery result is only a candidate until this challenge response has
been verified. A control ACK is never trusted when its signature, correlation,
`request_id`, or `seq` fails verification.

Message authentication does not encrypt local HTTP bodies from a passive LAN
observer. A deployment that requires LAN confidentiality must use HTTPS with a
per-gateway certificate/public-key pin provisioned during pairing; the HMAC
layer remains required for command correlation and replay protection.

## Cloud command mapping

The signed cloud command uses `CmdId=3001` and the same logical canonical
fields, mapped as `RequestId`, `CmdId`, `Seq`, `TargetDevice`, `Action`,
`Value`, `Timestamp`, `Nonce`, `Alg`, and `KeyId`. `Value` is transported in
IoTDA `paras` as compact JSON atom text; it is omitted when there is no value.

A direct IoTDA REST `CreateCommand` body is:

```text
{ service_id, command_name: "SetDeviceStatus", paras }
```

The device ID belongs in the REST URI. `object_device_id` is never a member of
`paras`. IoTDA MQTT downlink messages and a custom proxy may add
`object_device_id` at the top level; the schema therefore permits that one
optional wrapper field. Diagnostic PING is `Action="PING"`, not a second IoTDA
product-model command.

## Acknowledgement rule

The gateway echoes `request_id` and `seq`. A command is confirmed only when
`result_code` is exactly `0`; HTTP 2xx by itself is not execution confirmation.
On success, `reported_state` contains the state after command execution. A
cached exact-retry ACK may include `idempotent_replay: true`; all other ACK
fields remain identical to the first response.

## Sensor and automation state provenance

`Presence_01` is a first-class read-only sensor. Its state uses `presence=true`
for detected occupancy and `false` after the configured no-motion timeout.
Gateway discovery and control ACK device states may additionally carry:

- `stateSource`: `sensor.physical`, `device.feedback`, `app.lan`, `app.cloud`,
  or `automation.local`;
- `triggerDeviceId`: the sensor that caused a local rule;
- `automationId`: the stable gateway rule ID.

Local automation never changes an App-only cache. It creates an internal
command and passes it through the same router, driver confirmation, state
callback and IoTDA report path as authenticated phone commands. An actuator
value without physical/structured downstream confirmation is not a successful
automation result.

## Development simulator

Run the standard-library tests from the repository root:

```text
python -m unittest tools.test_gateway_contract -v
```

Start the fixture on localhost:

```text
python tools/gateway_contract_server.py --port 9200
```

For a physical phone on the same trusted development LAN, explicitly pass
`--host 0.0.0.0` and allow the port through the development-machine firewall.
The server marks every response with `X-YaoCore-Simulator: DEV-ONLY` and the
health document with `DEV_SIMULATOR_ONLY`; those markers must never be accepted
as hardware evidence or enabled in a production build.
