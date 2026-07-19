/*
 * YaoCore (爻构) - UNO R4 WiFi RGB reference actuator
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan (Quirkybrain)
 * Created: 2026-07-18
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include <Arduino.h>
#include <ArduinoJson.h>
#include <Crypto.h>
#include <EEPROM.h>
#include <SHA256.h>
#include <WiFiS3.h>
#include <WiFiUdp.h>
#include <time.h>
#include "config.h"

namespace {

constexpr char PROTOCOL_VERSION[] = "1.0";
constexpr char ALGORITHM[] = "HMAC-SHA256";
constexpr char KEY_ID[] = "app-key-v1";
constexpr char COMMAND_PATH[] = "/yaocore/v1/command";
constexpr uint16_t COMMAND_PORT = 8080;
constexpr uint16_t DISCOVERY_PORT = 9200;
constexpr uint16_t DISCOVERY_LOCAL_PORT = 42100;
constexpr uint32_t HEARTBEAT_MS = 5000;
constexpr uint32_t REGISTER_RETRY_MS = 5000;
constexpr uint32_t WIFI_RETRY_MS = 10000;
constexpr uint32_t DISCOVERY_RETRY_MS = 5000;
constexpr uint32_t KNOB_SAMPLE_MS = 20;
constexpr uint32_t STATE_REPORT_MIN_INTERVAL_MS = 100;
constexpr uint32_t REMOTE_CONTROL_LEASE_MS = 650;
constexpr uint32_t KNOB_GESTURE_WINDOW_MS = 300;
constexpr uint16_t ANALOG_MAX_VALUE = 4095;
constexpr uint16_t KNOB_LEARN_MIN_SPAN = ANALOG_MAX_VALUE * 60U / 100U;
constexpr uint16_t KNOB_HUE_DEADBAND = 2;
constexpr uint16_t KNOB_TAKEOVER_DEGREES = 6;
constexpr uint32_t SIGNATURE_WINDOW_SECONDS = 120;
constexpr uint32_t SEQUENCE_MAGIC = 0x59414F34UL;
constexpr int SEQUENCE_EEPROM_ADDRESS = 0;
constexpr uint32_t SEQUENCE_BLOCK = 256;
constexpr size_t KEY_SIZE = 32;
constexpr size_t NONCE_CACHE_SIZE = 32;
constexpr size_t MAX_HTTP_BODY = 1024;

WiFiServer commandServer(COMMAND_PORT);
WiFiUDP discoveryUdp;

struct LightState {
  bool online;
  bool power;
  uint8_t brightness;
  uint8_t red;
  uint8_t green;
  uint8_t blue;
};

struct SequenceStore { uint32_t magic; uint32_t nextBlock; uint32_t checksum; };
struct NonceRecord { char value[65]; unsigned long acceptedAt; };

LightState light = {true, false, 0, 255, 255, 255};
uint8_t moduleKey[KEY_SIZE];
uint8_t lastNonZeroBrightness = 100;
uint32_t sequenceValue = 1;
uint32_t sequenceLimit = 1;
uint32_t lastRegisterAttempt = 0;
uint32_t lastHeartbeat = 0;
uint32_t lastWiFiAttempt = 0;
uint32_t lastDiscoveryAttempt = 0;
uint32_t lastDiagnosticLog = 0;
uint32_t lastKnobSample = 0;
uint32_t lastStateReport = 0;
uint32_t filteredKnobQ3 = 0;
uint32_t knobChangeCount = 0;
uint32_t lastStateReportDuration = 0;
uint32_t lastCommandReadDuration = 0;
uint32_t lastCommandAuthDuration = 0;
uint32_t lastCommandAckDuration = 0;
uint32_t lastCommandDuration = 0;
uint32_t lastRemoteControlAt = 0;
uint32_t lastGatewayAckAt = 0;
uint32_t udpTelemetrySent = 0;
uint32_t udpAckAccepted = 0;
uint32_t udpAckRejected = 0;
uint32_t lastKnobMovementAt = 0;
uint16_t lastKnobHue = 0;
uint16_t knobGestureDegrees = 0;
uint16_t knobObservedMin = ANALOG_MAX_VALUE;
uint16_t knobObservedMax = 0;
uint8_t gatewayFailures = 0;
int lastGatewayHttpStatus = -1;
bool keyReady = false;
bool registered = false;
bool stateDirty = true;
bool commandServerStarted = false;
bool discoverySocketStarted = false;
bool knobReady = false;
bool knobOwnsColor = false;
IPAddress gatewayIp;
uint16_t gatewayPort = 0;
String gatewayId;
NonceRecord nonceCache[NONCE_CACHE_SIZE];
size_t nonceCursor = 0;

bool hexNibble(char value, uint8_t &out) {
  if (value >= '0' && value <= '9') out = value - '0';
  else if (value >= 'A' && value <= 'F') out = value - 'A' + 10;
  else if (value >= 'a' && value <= 'f') out = value - 'a' + 10;
  else return false;
  return true;
}

bool decodeKey() {
  String source = YAOCORE_MODULE_KEY_HEX;
  if (source.length() != KEY_SIZE * 2) return false;
  for (size_t i = 0; i < KEY_SIZE; ++i) {
    uint8_t high, low;
    if (!hexNibble(source[i * 2], high) || !hexNibble(source[i * 2 + 1], low)) return false;
    moduleKey[i] = (high << 4) | low;
  }
  return true;
}

String toHex(const uint8_t *data, size_t size) {
  static const char digits[] = "0123456789abcdef";
  String result;
  result.reserve(size * 2);
  for (size_t i = 0; i < size; ++i) {
    result += digits[data[i] >> 4];
    result += digits[data[i] & 0x0f];
  }
  return result;
}

String sha256Hex(const String &input) {
  SHA256 hash;
  uint8_t digest[32];
  hash.reset();
  hash.update(input.c_str(), input.length());
  hash.finalize(digest, sizeof(digest));
  return toHex(digest, sizeof(digest));
}

String hmacHex(const String &input) {
  uint8_t innerPad[64], outerPad[64], innerDigest[32], digest[32];
  for (size_t i = 0; i < sizeof(innerPad); ++i) {
    uint8_t keyByte = i < sizeof(moduleKey) ? moduleKey[i] : 0;
    innerPad[i] = keyByte ^ 0x36;
    outerPad[i] = keyByte ^ 0x5c;
  }
  SHA256 hash;
  hash.reset();
  hash.update(innerPad, sizeof(innerPad));
  hash.update(input.c_str(), input.length());
  hash.finalize(innerDigest, sizeof(innerDigest));
  hash.reset();
  hash.update(outerPad, sizeof(outerPad));
  hash.update(innerDigest, sizeof(innerDigest));
  hash.finalize(digest, sizeof(digest));
  return toHex(digest, sizeof(digest));
}

String canonical(const String &kind, const String &timestamp, const String &nonce, const String &body) {
  return String("YAOCORE-MODULE-V1\n") + kind + '\n' + YAOCORE_MODULE_ID + '\n' + timestamp + '\n' +
    nonce + "\nHMAC-SHA256\napp-key-v1\n" + sha256Hex(body);
}

bool constantTimeEqual(const String &a, const String &b) {
  if (a.length() != b.length()) return false;
  uint8_t difference = 0;
  for (size_t i = 0; i < a.length(); ++i) difference |= a[i] ^ b[i];
  return difference == 0;
}

unsigned long epochNow() { return WiFi.getTime(); }
bool clockReady() { return epochNow() > 1700000000UL; }

String timestampNow() {
  time_t now = static_cast<time_t>(epochNow());
  struct tm utc;
  gmtime_r(&now, &utc);
  char text[17];
  strftime(text, sizeof(text), "%Y%m%dT%H%M%SZ", &utc);
  return String(text);
}

int64_t daysFromCivil(int year, unsigned month, unsigned day) {
  year -= month <= 2;
  const int era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(year - era * 400);
  const unsigned mp = month > 2 ? month - 3 : month + 9;
  return static_cast<int64_t>(era) * 146097 +
    static_cast<int64_t>(yoe * 365 + yoe / 4 - yoe / 100 + (153 * mp + 2) / 5 + day - 1) - 719468;
}

bool digits(const String &text, size_t start, size_t count, int &out) {
  out = 0;
  for (size_t i = 0; i < count; ++i) {
    char value = text[start + i];
    if (value < '0' || value > '9') return false;
    out = out * 10 + value - '0';
  }
  return true;
}

bool parseTimestamp(const String &value, int64_t &epoch) {
  int y, m, d, hh, mm, ss;
  if (value.length() != 16 || value[8] != 'T' || value[15] != 'Z' ||
      !digits(value, 0, 4, y) || !digits(value, 4, 2, m) || !digits(value, 6, 2, d) ||
      !digits(value, 9, 2, hh) || !digits(value, 11, 2, mm) || !digits(value, 13, 2, ss) ||
      y < 2024 || m < 1 || m > 12 || d < 1 || d > 31 || hh > 23 || mm > 59 || ss > 60) return false;
  epoch = daysFromCivil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss;
  return true;
}

bool nonceSeen(const String &nonce, unsigned long now) {
  for (const auto &record : nonceCache)
    if (record.value[0] && nonce.equals(record.value) &&
        now - record.acceptedAt <= 300) return true;
  return false;
}

bool verifyMessage(const String &kind, const String &algorithm, const String &keyId,
    const String &moduleId, const String &timestamp, const String &nonce,
    const String &signature, const String &body) {
  unsigned long now = epochNow();
  int64_t signedAt = 0;
  if (!keyReady || algorithm != ALGORITHM || keyId != KEY_ID || moduleId != YAOCORE_MODULE_ID ||
      nonce.length() != 64 || signature.length() != 64 || now < 1700000000UL ||
      !parseTimestamp(timestamp, signedAt) || llabs(static_cast<int64_t>(now) - signedAt) > SIGNATURE_WINDOW_SECONDS ||
      nonceSeen(nonce, now) || !constantTimeEqual(hmacHex(canonical(kind, timestamp, nonce, body)), signature)) return false;
  nonce.toCharArray(nonceCache[nonceCursor].value,
    sizeof(nonceCache[nonceCursor].value));
  nonceCache[nonceCursor].acceptedAt = now;
  nonceCursor = (nonceCursor + 1) % NONCE_CACHE_SIZE;
  return true;
}

String makeNonce() {
  uint8_t bytes[32];
  for (uint8_t &value : bytes) value = static_cast<uint8_t>(random(0, 256));
  return toHex(bytes, sizeof(bytes));
}

void reserveSequence(uint32_t start) {
  sequenceValue = start;
  sequenceLimit = start + SEQUENCE_BLOCK;
  SequenceStore store = {SEQUENCE_MAGIC, sequenceLimit, 0};
  store.checksum = store.magic ^ store.nextBlock ^ 0xC3A55A3CUL;
  EEPROM.put(SEQUENCE_EEPROM_ADDRESS, store);
}

void loadSequence() {
  SequenceStore store;
  EEPROM.get(SEQUENCE_EEPROM_ADDRESS, store);
  uint32_t checksum = store.magic ^ store.nextBlock ^ 0xC3A55A3CUL;
  reserveSequence(store.magic == SEQUENCE_MAGIC && store.checksum == checksum && store.nextBlock ? store.nextBlock : 1);
}

uint32_t nextSequence() {
  if (sequenceValue >= sequenceLimit) reserveSequence(sequenceLimit);
  return sequenceValue++;
}

uint8_t outputLevel(uint8_t component) {
  uint16_t level = light.power ? (static_cast<uint32_t>(component) * light.brightness + 50) / 100 : 0;
  return YAOCORE_COMMON_ANODE ? 255 - level : level;
}

void applyOutputs() {
  analogWrite(YAOCORE_RED_PIN, outputLevel(light.red));
  analogWrite(YAOCORE_GREEN_PIN, outputLevel(light.green));
  analogWrite(YAOCORE_BLUE_PIN, outputLevel(light.blue));
}

uint16_t knobHueDistance(uint16_t left, uint16_t right) {
  uint16_t distance = left > right ? left - right : right - left;
  return distance > 180 ? 360 - distance : distance;
}

void hueToRgb(uint16_t hue, uint8_t &red, uint8_t &green, uint8_t &blue) {
  hue %= 360;
  uint8_t sector = hue / 60;
  uint16_t offset = hue % 60;
  uint8_t rise = static_cast<uint8_t>((offset * 255U + 30U) / 60U);
  uint8_t fall = 255U - rise;
  if (sector == 0) { red = 255; green = rise; blue = 0; }
  else if (sector == 1) { red = fall; green = 255; blue = 0; }
  else if (sector == 2) { red = 0; green = 255; blue = rise; }
  else if (sector == 3) { red = 0; green = fall; blue = 255; }
  else if (sector == 4) { red = rise; green = 0; blue = 255; }
  else { red = 255; green = 0; blue = fall; }
}

uint16_t knobRawToHue(uint16_t raw) {
  if (raw < knobObservedMin) knobObservedMin = raw;
  if (raw > knobObservedMax) knobObservedMax = raw;

  uint16_t low = YAOCORE_COLOR_KNOB_ADC_MIN;
  uint16_t high = YAOCORE_COLOR_KNOB_ADC_MAX;
  uint16_t observedSpan = knobObservedMax - knobObservedMin;
  // Once the user has swept most of the potentiometer, use its measured
  // electrical endpoints. This compensates modules that cannot reach 0 V or
  // VCC while avoiding a huge hue jump from a tiny movement after boot.
  if (observedSpan >= KNOB_LEARN_MIN_SPAN) {
    low = knobObservedMin;
    high = knobObservedMax;
  }
  if (high <= low) return 0;
  uint16_t clamped = raw < low ? low : (raw > high ? high : raw);
  return static_cast<uint16_t>(
    (static_cast<uint32_t>(clamped - low) * 359U + (high - low) / 2U) /
    (high - low));
}

void handleColorKnob(uint32_t now) {
  if (now - lastKnobSample < KNOB_SAMPLE_MS) return;
  lastKnobSample = now;
  uint16_t raw = static_cast<uint16_t>(analogRead(YAOCORE_COLOR_KNOB_PIN));
  if (!knobReady) {
    filteredKnobQ3 = static_cast<uint32_t>(raw) << 3;
    lastKnobHue = knobRawToHue(raw);
    knobReady = true;
    return;
  }

  // Low-pass ADC noise before feeding the soft-takeover arbiter.
  filteredKnobQ3 = (filteredKnobQ3 * 7U + (static_cast<uint32_t>(raw) << 3)) / 8U;
  uint16_t filtered = static_cast<uint16_t>(filteredKnobQ3 >> 3);
  uint16_t hue = knobRawToHue(filtered);
  uint16_t movement = knobHueDistance(hue, lastKnobHue);
  if (movement < KNOB_HUE_DEADBAND) return;
  lastKnobHue = hue;

  // Every valid App command owns the actuator for a short lease. Samples are
  // still tracked during the lease so the old physical position cannot jump
  // back into effect as soon as the lease expires.
  if (now - lastRemoteControlAt < REMOTE_CONTROL_LEASE_MS) {
    knobGestureDegrees = 0;
    lastKnobMovementAt = now;
    return;
  }

  if (!knobOwnsColor) {
    // Sparse ADC noise must never wake a lamp that the App turned off. Only a
    // deliberate movement accumulated inside one short gesture may take over.
    if (now - lastKnobMovementAt > KNOB_GESTURE_WINDOW_MS) knobGestureDegrees = 0;
    lastKnobMovementAt = now;
    knobGestureDegrees = static_cast<uint16_t>(min(360U,
      static_cast<unsigned>(knobGestureDegrees) + movement));
    if (knobGestureDegrees < KNOB_TAKEOVER_DEGREES) return;
    knobOwnsColor = true;
    knobGestureDegrees = 0;
  }

  hueToRgb(hue, light.red, light.green, light.blue);
  if (!light.power || light.brightness == 0) {
    light.brightness = lastNonZeroBrightness ? lastNonZeroBrightness : 100;
    light.power = true;
  }
  applyOutputs();
  ++knobChangeCount;
  stateDirty = true;
}

String colorHex() {
  char value[8];
  snprintf(value, sizeof(value), "#%02X%02X%02X", light.red, light.green, light.blue);
  return String(value);
}

void addState(JsonObject state) {
  state["online"] = light.online;
  state["power"] = light.power;
  state["brightness"] = light.brightness;
  state["color"] = colorHex();
}

void forgetGateway() {
  registered = false;
  gatewayIp = IPAddress(0, 0, 0, 0);
  gatewayPort = 0;
  gatewayId = "";
}

bool discoverGateway() {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (!discoverySocketStarted) {
    discoverySocketStarted = discoveryUdp.begin(DISCOVERY_LOCAL_PORT) == 1;
    if (!discoverySocketStarted) return false;
  }

  static const char request[] =
    "{\"type\":\"YAOCORE_DISCOVER\",\"protocol_version\":2,\"service_id\":\"SmartHomeService\"}";
  discoveryUdp.beginPacket(IPAddress(255, 255, 255, 255), DISCOVERY_PORT);
  discoveryUdp.write(reinterpret_cast<const uint8_t *>(request), strlen(request));
  if (discoveryUdp.endPacket() != 1) return false;

  unsigned long started = millis();
  while (millis() - started < 1400) {
    int packetSize = discoveryUdp.parsePacket();
    if (packetSize <= 0) { delay(10); continue; }
    char response[512];
    int count = discoveryUdp.read(response, sizeof(response) - 1);
    if (count <= 0) continue;
    response[count] = '\0';
    JsonDocument document;
    if (deserializeJson(document, response)) continue;
    const char *protocol = document["protocolVersion"] | "";
    const char *service = document["serviceId"] | "";
    const char *foundId = document["gatewayId"] | "";
    int foundPort = document["port"] | 0;
    if (strcmp(protocol, "2.0") || strcmp(service, "SmartHomeService") ||
        !foundId[0] || strcmp(foundId, YAOCORE_EXPECTED_GATEWAY_ID) ||
        foundPort <= 0 || foundPort > 65535) continue;
    gatewayIp = discoveryUdp.remoteIP();
    gatewayPort = static_cast<uint16_t>(foundPort);
    gatewayId = foundId;
    Serial.print(F("Discovered gateway "));
    Serial.print(gatewayId);
    Serial.print(F(" at "));
    Serial.print(gatewayIp);
    Serial.print(':');
    Serial.println(gatewayPort);
    return true;
  }
  return false;
}

bool postSigned(const char *path, const char *kind, const String &body) {
  lastGatewayHttpStatus = -1;
  if (gatewayPort == 0) return false;
  WiFiClient transport;
  if (transport.connect(gatewayIp, gatewayPort) != 1) return false;

  // ArduinoHttpClient emits the request line, every header and the body as
  // separate WiFiS3 modem transactions.  While a heartbeat/state report is
  // doing that, the single-threaded R4 cannot accept a light command, which
  // used to create periodic 3.5 s slider stalls.  Build the same signed HTTP
  // message once and transfer it to the ESP32-S3 radio in a single write.
  String requestTimestamp = timestampNow();
  String requestNonce = makeNonce();
  String requestSignature = hmacHex(canonical(kind, requestTimestamp, requestNonce, body));
  String request;
  request.reserve(body.length() + 512);
  request += "POST "; request += path; request += " HTTP/1.1\r\nHost: ";
  request += gatewayIp.toString(); request += ':'; request += gatewayPort;
  request += "\r\nConnection: close\r\nContent-Type: application/json\r\n";
  request += "X-YaoCore-Alg: "; request += ALGORITHM;
  request += "\r\nX-YaoCore-Key-Id: "; request += KEY_ID;
  request += "\r\nX-YaoCore-Module-Id: "; request += YAOCORE_MODULE_ID;
  request += "\r\nX-YaoCore-Timestamp: "; request += requestTimestamp;
  request += "\r\nX-YaoCore-Nonce: "; request += requestNonce;
  request += "\r\nX-YaoCore-Sign: "; request += requestSignature;
  request += "\r\nContent-Length: "; request += body.length();
  request += "\r\n\r\n"; request += body;
  if (transport.write(reinterpret_cast<const uint8_t *>(request.c_str()),
      request.length()) != request.length()) {
    transport.stop();
    return false;
  }

  // ArduinoHttpClient::headerAvailable() reads without first waiting for the
  // next WiFiS3 fragment. On UNO R4 that can append -1/0xFF to a header value
  // and randomly lose authentication fields. Read complete CRLF lines from
  // the underlying stream with an inactivity timeout instead.
  auto readResponseLine = [&](String &line) -> bool {
    line = "";
    unsigned long activity = millis();
    while (millis() - activity < 2500) {
      if (!transport.available()) { delay(1); continue; }
      int next = transport.read();
      if (next < 0) continue;
      activity = millis();
      char value = static_cast<char>(next);
      if (value == '\n') return true;
      if (value != '\r' && line.length() < 1024) line += value;
    }
    return false;
  };

  String statusLine;
  int status = -1;
  if (readResponseLine(statusLine) && statusLine.startsWith("HTTP/1.1 ") &&
      statusLine.length() >= 12) {
    status = statusLine.substring(9, 12).toInt();
  }
  lastGatewayHttpStatus = status;
  String algorithm, keyId, moduleId, timestamp, nonce, signature;
  size_t responseLength = 0;
  String line;
  while (readResponseLine(line) && line.length()) {
    int colon = line.indexOf(':');
    if (colon <= 0) continue;
    String name = line.substring(0, colon);
    String value = line.substring(colon + 1);
    value.trim();
    if (name.equalsIgnoreCase("X-YaoCore-Alg")) algorithm = value;
    else if (name.equalsIgnoreCase("X-YaoCore-Key-Id")) keyId = value;
    else if (name.equalsIgnoreCase("X-YaoCore-Module-Id")) moduleId = value;
    else if (name.equalsIgnoreCase("X-YaoCore-Timestamp")) timestamp = value;
    else if (name.equalsIgnoreCase("X-YaoCore-Nonce")) nonce = value;
    else if (name.equalsIgnoreCase("X-YaoCore-Sign")) signature = value;
    else if (name.equalsIgnoreCase("Content-Length")) responseLength = value.toInt();
  }
  String response;
  response.reserve(responseLength);
  unsigned long bodyActivity = millis();
  while (response.length() < responseLength && millis() - bodyActivity < 2500) {
    if (!transport.available()) { delay(1); continue; }
    int next = transport.read();
    if (next < 0) continue;
    response += static_cast<char>(next);
    bodyActivity = millis();
  }
  bool valid = response.length() == responseLength && status == 200 &&
    verifyMessage("gateway_ack", algorithm, keyId, moduleId,
    timestamp, nonce, signature, response);
  if (!valid) {
    Serial.print(F("Gateway ACK rejected status=")); Serial.print(status);
    Serial.print(F(" alg=")); Serial.print(algorithm);
    Serial.print(F(" key=")); Serial.print(keyId);
    Serial.print(F(" module=")); Serial.print(moduleId);
    Serial.print(F(" ts=")); Serial.print(timestamp);
    Serial.print(F(" nonceLen=")); Serial.print(nonce.length());
    Serial.print(F(" signLen=")); Serial.print(signature.length());
    Serial.print(F(" body=")); Serial.println(response);
  }
  if (valid) {
    JsonDocument document;
    valid = !deserializeJson(document, response) && document["protocolVersion"] == PROTOCOL_VERSION &&
      document["resultCode"].as<int>() == 0;
  }
  transport.stop();
  return valid;
}

bool registerModule() {
  JsonDocument document;
  document["protocolVersion"] = PROTOCOL_VERSION;
  document["moduleId"] = YAOCORE_MODULE_ID;
  document["commandPort"] = COMMAND_PORT;
  document["commandPath"] = COMMAND_PATH;
  document["heartbeatSeconds"] = HEARTBEAT_MS / 1000;
  document["sequence"] = nextSequence();
  JsonObject device = document["device"].to<JsonObject>();
  device["deviceId"] = YAOCORE_DEVICE_ID;
  // User-facing name and room live on the gateway. These are only immutable
  // product fallbacks used until the App assigns metadata.
  device["name"] = YAOCORE_PRODUCT_MODEL;
  device["room"] = "Unassigned";
  device["brand"] = YAOCORE_DEVICE_BRAND;
  device["model"] = YAOCORE_PRODUCT_MODEL;
  device["protocol"] = "yaocore-r4-rgb-v2";
  device["deviceType"] = "light";
  JsonArray capabilities = device["capabilities"].to<JsonArray>();
  capabilities.add("power");
  capabilities.add("brightness");
  capabilities.add("rgbColor");
  addState(document["state"].to<JsonObject>());
  String body;
  serializeJson(document, body);
  return postSigned("/module/v1/register", "register", body);
}

bool sendHeartbeat() {
  JsonDocument document;
  document["protocolVersion"] = PROTOCOL_VERSION;
  document["moduleId"] = YAOCORE_MODULE_ID;
  document["sequence"] = nextSequence();
  String body; serializeJson(document, body);
  return postSigned("/module/v1/heartbeat", "heartbeat", body);
}

bool sendState() {
  JsonDocument document;
  document["protocolVersion"] = PROTOCOL_VERSION;
  document["moduleId"] = YAOCORE_MODULE_ID;
  document["deviceId"] = YAOCORE_DEVICE_ID;
  document["sequence"] = nextSequence();
  addState(document["state"].to<JsonObject>());
  String body; serializeJson(document, body);
  return postSigned("/module/v1/state", "state", body);
}

bool sendSignedDatagram(const char *kind, const String &body) {
  if (!registered || gatewayPort == 0 || !discoverySocketStarted) return false;
  String timestamp = timestampNow();
  String nonce = makeNonce();
  String signature = hmacHex(canonical(kind, timestamp, nonce, body));
  JsonDocument envelope;
  envelope["type"] = "YAOCORE_MODULE_EVENT";
  envelope["kind"] = kind;
  envelope["moduleId"] = YAOCORE_MODULE_ID;
  envelope["timestamp"] = timestamp;
  envelope["nonce"] = nonce;
  envelope["signature"] = signature;
  envelope["body"] = body;
  String packet; serializeJson(envelope, packet);
  if (packet.length() > 1400 ||
      discoveryUdp.beginPacket(gatewayIp, gatewayPort) != 1) return false;
  discoveryUdp.write(reinterpret_cast<const uint8_t *>(packet.c_str()),
    packet.length());
  bool sent = discoveryUdp.endPacket() == 1;
  if (sent) ++udpTelemetrySent;
  return sent;
}

bool sendStateDatagram() {
  JsonDocument document;
  document["protocolVersion"] = PROTOCOL_VERSION;
  document["moduleId"] = YAOCORE_MODULE_ID;
  document["deviceId"] = YAOCORE_DEVICE_ID;
  document["sequence"] = nextSequence();
  addState(document["state"].to<JsonObject>());
  String body; serializeJson(document, body);
  return sendSignedDatagram("state", body);
}

bool sendHeartbeatDatagram() {
  JsonDocument document;
  document["protocolVersion"] = PROTOCOL_VERSION;
  document["moduleId"] = YAOCORE_MODULE_ID;
  document["sequence"] = nextSequence();
  String body; serializeJson(document, body);
  return sendSignedDatagram("heartbeat", body);
}

void pollGatewayDatagram() {
  int packetSize = discoveryUdp.parsePacket();
  if (packetSize <= 0 || packetSize > 1400) return;
  char packet[1401];
  int count = discoveryUdp.read(packet, sizeof(packet) - 1);
  if (count <= 0) return;
  packet[count] = '\0';
  JsonDocument envelope;
  if (deserializeJson(envelope, packet) ||
      strcmp(envelope["type"] | "", "YAOCORE_MODULE_ACK") ||
      strcmp(envelope["moduleId"] | "", YAOCORE_MODULE_ID)) {
    ++udpAckRejected; return;
  }
  String body = envelope["body"] | "";
  if (!verifyMessage("gateway_ack", ALGORITHM, KEY_ID, YAOCORE_MODULE_ID,
      envelope["timestamp"] | "", envelope["nonce"] | "",
      envelope["signature"] | "", body)) {
    ++udpAckRejected; return;
  }
  JsonDocument ack;
  if (deserializeJson(ack, body)) { ++udpAckRejected; return; }
  ++udpAckAccepted;
  lastGatewayAckAt = millis();
  int resultCode = ack["resultCode"] | 40;
  if (resultCode == 0) gatewayFailures = 0;
  else if (resultCode == 44) {
    registered = false;
    stateDirty = true;
    lastRegisterAttempt = 0;
  }
}

String headerValue(const String &headers, const String &name) {
  int start = 0;
  while (start < static_cast<int>(headers.length())) {
    int end = headers.indexOf("\r\n", start);
    if (end < 0) end = headers.length();
    int colon = headers.indexOf(':', start);
    if (colon > start && colon < end && headers.substring(start, colon).equalsIgnoreCase(name)) {
      String value = headers.substring(colon + 1, end); value.trim(); return value;
    }
    start = end + 2;
  }
  return "";
}

void sendHttp(WiFiClient &client, int status, const String &body, bool sign) {
  // WiFiS3 forwards every write through the RA4M1-to-ESP32 modem protocol.
  // Sending each header fragment separately adds hundreds of milliseconds to
  // every light command, so construct and transmit the complete ACK once.
  String response;
  response.reserve(body.length() + 512);
  response += status == 200 ? "HTTP/1.1 200 OK\r\n" : status == 403 ?
    "HTTP/1.1 403 Forbidden\r\n" : "HTTP/1.1 400 Bad Request\r\n";
  response += "Content-Type: application/json\r\nConnection: keep-alive\r\n";
  if (sign) {
    String timestamp = timestampNow(), nonce = makeNonce();
    response += "X-YaoCore-Alg: HMAC-SHA256\r\nX-YaoCore-Key-Id: app-key-v1\r\nX-YaoCore-Module-Id: ";
    response += YAOCORE_MODULE_ID;
    response += "\r\nX-YaoCore-Timestamp: "; response += timestamp;
    response += "\r\nX-YaoCore-Nonce: "; response += nonce;
    response += "\r\nX-YaoCore-Sign: ";
    response += hmacHex(canonical("command_ack", timestamp, nonce, body));
    response += "\r\n";
  }
  response += "Content-Length: "; response += body.length();
  response += "\r\n\r\n"; response += body;
  client.write(reinterpret_cast<const uint8_t *>(response.c_str()), response.length());
}

bool readRequest(WiFiClient &client, String &requestLine, String &headers, String &body) {
  client.setTimeout(1500);
  requestLine = client.readStringUntil('\n'); requestLine.trim();
  if (!requestLine.length()) return false;
  while (client.connected()) {
    String line = client.readStringUntil('\n');
    if (line == "\r" || !line.length()) break;
    headers += line;
    // readStringUntil removes LF while retaining CR. Restore LF so each
    // header remains a CRLF-delimited field for headerValue(). Without this,
    // all fields are concatenated and Content-Length cannot be found.
    headers += '\n';
  }

  auto readExact = [&](size_t length) -> bool {
    if (body.length() + length > MAX_HTTP_BODY) return false;
    body.reserve(body.length() + length);
    unsigned long started = millis();
    while (length > 0 && millis() - started < 1500) {
      if (!client.available()) { delay(1); continue; }
      body += static_cast<char>(client.read());
      --length;
      started = millis();
    }
    return length == 0;
  };

  String contentLength = headerValue(headers, "Content-Length");
  if (contentLength.length()) {
    char *end = nullptr;
    long length = strtol(contentLength.c_str(), &end, 10);
    if (end == contentLength.c_str() || *end != '\0' || length < 0 ||
        length > static_cast<long>(MAX_HTTP_BODY)) return false;
    String expect = headerValue(headers, "Expect");
    expect.toLowerCase();
    if (expect.indexOf("100-continue") >= 0) {
      // HTTP/1.1 clients such as Windows HttpWebRequest may wait for this
      // interim response before transmitting the JSON body.
      client.print("HTTP/1.1 100 Continue\r\n\r\n");
      client.flush();
    }
    return readExact(static_cast<size_t>(length));
  }

  String transferEncoding = headerValue(headers, "Transfer-Encoding");
  transferEncoding.toLowerCase();
  if (transferEncoding.indexOf("chunked") >= 0) {
    while (true) {
      String chunkLine = client.readStringUntil('\n');
      chunkLine.trim();
      int extension = chunkLine.indexOf(';');
      if (extension >= 0) chunkLine.remove(extension);
      if (!chunkLine.length()) return false;
      char *end = nullptr;
      unsigned long chunkLength = strtoul(chunkLine.c_str(), &end, 16);
      if (end == chunkLine.c_str() || *end != '\0' ||
          chunkLength > MAX_HTTP_BODY - body.length()) return false;
      if (chunkLength == 0) {
        // Consume optional trailer headers and their terminating empty line.
        while (client.connected()) {
          String trailer = client.readStringUntil('\n');
          if (trailer == "\r" || !trailer.length()) break;
        }
        return true;
      }
      if (!readExact(static_cast<size_t>(chunkLength))) return false;
      char cr = 0, lf = 0;
      unsigned long started = millis();
      while ((!client.available()) && millis() - started < 1500) delay(1);
      if (client.available()) cr = static_cast<char>(client.read());
      started = millis();
      while ((!client.available()) && millis() - started < 1500) delay(1);
      if (client.available()) lf = static_cast<char>(client.read());
      if (cr != '\r' || lf != '\n') return false;
    }
  }

  // Body-less GET is valid. A command POST without an explicit framing header
  // is ambiguous and is rejected.
  return requestLine.startsWith("GET ");
}

bool parseColor(const String &value, uint8_t &r, uint8_t &g, uint8_t &b) {
  if (value.length() != 7 || value[0] != '#') return false;
  uint8_t n[6];
  for (size_t i = 0; i < 6; ++i) if (!hexNibble(value[i + 1], n[i])) return false;
  r = n[0] * 16 + n[1]; g = n[2] * 16 + n[3]; b = n[4] * 16 + n[5];
  return true;
}

void handleCommandClient(WiFiClient client) {
  uint32_t commandStarted = millis();
  String line, headers, body;
  if (!readRequest(client, line, headers, body) || line != String("POST ") + COMMAND_PATH + " HTTP/1.1") {
    sendHttp(client, 400, "{\"error\":\"bad request\"}", false); client.stop(); return;
  }
  uint32_t requestReadAt = millis();
  bool authenticated = verifyMessage("command", headerValue(headers, "X-YaoCore-Alg"),
    headerValue(headers, "X-YaoCore-Key-Id"), headerValue(headers, "X-YaoCore-Module-Id"),
    headerValue(headers, "X-YaoCore-Timestamp"), headerValue(headers, "X-YaoCore-Nonce"),
    headerValue(headers, "X-YaoCore-Sign"), body);
  if (!authenticated) { sendHttp(client, 403, "{\"error\":\"module authentication failed\"}", false); client.stop(); return; }
  uint32_t authenticatedAt = millis();

  JsonDocument command;
  DeserializationError error = deserializeJson(command, body);
  String requestId = command["requestId"] | "";
  String action = command["action"] | "";
  bool valid = !error && command["protocolVersion"] == PROTOCOL_VERSION && command["targetDevice"] == YAOCORE_DEVICE_ID &&
    requestId.length() > 0 && requestId.length() <= 127;
  uint8_t resultCode = valid ? 0 : 20;
  if (valid && action == "ON") {
    light.brightness = lastNonZeroBrightness ? lastNonZeroBrightness : 100; light.power = true;
  } else if (valid && action == "OFF") {
    if (light.brightness) lastNonZeroBrightness = light.brightness; light.power = false; light.brightness = 0;
  } else if (valid && action == "SET_BRIGHTNESS") {
    int value = command["value"] | -1;
    if (value < 0 || value > 100) resultCode = 20;
    else { light.brightness = value; light.power = value > 0; if (value) lastNonZeroBrightness = value; }
  } else if (valid && action == "SET_COLOR") {
    String value = command["value"] | "";
    if (!parseColor(value, light.red, light.green, light.blue)) resultCode = 20;
  } else if (valid) resultCode = 20;

  if (resultCode == 0) {
    lastRemoteControlAt = millis();
    // A command plus authenticated physical-state ACK is also a liveness
    // exchange in both directions. Defer the periodic heartbeat so WiFiS3's
    // single modem channel never starts a redundant outbound request in the
    // middle of a continuous App slider gesture.
    lastHeartbeat = lastRemoteControlAt;
    gatewayFailures = 0;
    knobOwnsColor = false;
    knobGestureDegrees = 0;
    applyOutputs();
    // The authenticated command ACK below already contains the complete
    // physical state and is consumed by the gateway. Do not immediately send
    // the same state again: that duplicate request can delay the next command.
    stateDirty = false;
  }
  JsonDocument ack;
  ack["requestId"] = requestId;
  ack["resultCode"] = resultCode;
  ack["message"] = resultCode == 0 ? "physical PWM output confirmed" : "invalid module command";
  addState(ack["reportedState"].to<JsonObject>());
  String response; serializeJson(ack, response);
  uint32_t ackReadyAt = millis();
  sendHttp(client, 200, response, true);
  uint32_t ackSentAt = millis();
  lastCommandReadDuration = requestReadAt - commandStarted;
  lastCommandAuthDuration = authenticatedAt - requestReadAt;
  lastCommandAckDuration = ackSentAt - ackReadyAt;
  lastCommandDuration = ackSentAt - commandStarted;
  // The gateway has read the complete Content-Length framed ACK and closes
  // the connection.  Letting the client side close avoids filling the small
  // WiFiS3 server socket/TIME_WAIT pool during a long slider gesture.
}

void connectWiFi() {
  if (WiFi.status() == WL_NO_MODULE) return;
  lastWiFiAttempt = millis();
  Serial.print(F("Connecting test actuator to Wi-Fi: "));
  Serial.println(YAOCORE_WIFI_SSID);
  int status = WiFi.begin(YAOCORE_WIFI_SSID, YAOCORE_WIFI_PASSWORD);
  Serial.print(F("Wi-Fi result="));
  Serial.print(status);
  Serial.print(F(" IPv4="));
  Serial.println(WiFi.localIP());
}

}  // namespace

void setup() {
  pinMode(YAOCORE_RED_PIN, OUTPUT); pinMode(YAOCORE_GREEN_PIN, OUTPUT); pinMode(YAOCORE_BLUE_PIN, OUTPUT);
  pinMode(YAOCORE_STATUS_LED, OUTPUT);
  pinMode(YAOCORE_COLOR_KNOB_PIN, INPUT);
  analogReadResolution(12);
  digitalWrite(YAOCORE_STATUS_LED, LOW);
  applyOutputs();
  Serial.begin(115200);
  loadSequence();
  keyReady = decodeKey();
  randomSeed(analogRead(A0) ^ micros());
  connectWiFi();
  Serial.println(F("YaoCore UNO R4 WiFi RGB reference actuator ready"));
}

void loop() {
  uint32_t diagnosticNow = millis();
  handleColorKnob(diagnosticNow);
  if (diagnosticNow - lastDiagnosticLog >= 10000) {
    lastDiagnosticLog = diagnosticNow;
    Serial.print(F("status wifi=")); Serial.print(WiFi.status());
    Serial.print(F(" ip=")); Serial.print(WiFi.localIP());
    Serial.print(F(" clock=")); Serial.print(epochNow());
    Serial.print(F(" gateway=")); Serial.print(gatewayIp);
    Serial.print(F(" registered=")); Serial.print(registered ? F("yes") : F("no"));
    Serial.print(F(" knobChanges=")); Serial.print(knobChangeCount);
    Serial.print(F(" knobOwner=")); Serial.print(knobOwnsColor ? F("physical") : F("remote"));
    Serial.print(F(" knobRange=")); Serial.print(knobObservedMin);
    Serial.print('-'); Serial.print(knobObservedMax);
    Serial.print(F(" stateReportMs=")); Serial.print(lastStateReportDuration);
    Serial.print(F(" commandMs=")); Serial.print(lastCommandDuration);
    Serial.print(F("(read=")); Serial.print(lastCommandReadDuration);
    Serial.print(F(",auth=")); Serial.print(lastCommandAuthDuration);
    Serial.print(F(",ack=")); Serial.print(lastCommandAckDuration);
    Serial.print(F(") udp=")); Serial.print(udpTelemetrySent);
    Serial.print('/'); Serial.print(udpAckAccepted);
    Serial.print('/'); Serial.print(udpAckRejected);
    Serial.println();
  }
  if (WiFi.status() != WL_CONNECTED) {
    forgetGateway();
    if (commandServerStarted) { commandServer.end(); commandServerStarted = false; }
    if (discoverySocketStarted) { discoveryUdp.stop(); discoverySocketStarted = false; }
    digitalWrite(YAOCORE_STATUS_LED, (millis() / 600) % 2);
    if (millis() - lastWiFiAttempt >= WIFI_RETRY_MS) connectWiFi();
    delay(5); return;
  }
  digitalWrite(YAOCORE_STATUS_LED, LOW);
  if (!commandServerStarted) { commandServer.begin(); commandServerStarted = true; }
  WiFiClient incoming = commandServer.available();
  // With the gateway's persistent southbound connection, a connected socket
  // can exist without a complete new request. Do not enter the blocking HTTP
  // parser until WiFiS3 reports bytes, so knob sampling and state reports keep
  // running between slider updates.
  if (incoming && incoming.available() > 0) handleCommandClient(incoming);
  pollGatewayDatagram();
  uint32_t now = millis();
  if (gatewayPort == 0 && now - lastDiscoveryAttempt >= DISCOVERY_RETRY_MS) {
    lastDiscoveryAttempt = now;
    discoverGateway();
  } else if (!registered && gatewayPort != 0 && clockReady() &&
      now - lastRegisterAttempt >= REGISTER_RETRY_MS) {
    lastRegisterAttempt = now;
    registered = registerModule();
    if (registered) { lastHeartbeat = now; lastGatewayAckAt = now;
      stateDirty = false; gatewayFailures = 0; }
    else if (++gatewayFailures >= 2) { forgetGateway(); gatewayFailures = 0; }
  } else if (registered && stateDirty && now - lastStateReport >= STATE_REPORT_MIN_INTERVAL_MS) {
    lastStateReport = now;
    uint32_t reportStarted = millis();
    bool reported = sendStateDatagram();
    lastStateReportDuration = millis() - reportStarted;
    if (reported) {
      stateDirty = false;
      gatewayFailures = 0;
      // The signed state ACK proves the gateway is reachable; sending a
      // heartbeat immediately afterwards would carry no additional evidence.
      lastHeartbeat = now;
    } else if (++gatewayFailures >= 3) { forgetGateway(); gatewayFailures = 0; }
  } else if (registered && now - lastHeartbeat >= HEARTBEAT_MS) {
    lastHeartbeat = now;
    if (!sendHeartbeatDatagram() && ++gatewayFailures >= 3) {
      forgetGateway(); gatewayFailures = 0; stateDirty = true;
    }
  }
  if (registered && lastGatewayAckAt > 0 && now - lastGatewayAckAt >= HEARTBEAT_MS * 3) {
    // No authenticated UDP acknowledgement means the gateway may have
    // rebooted and lost its volatile route. Re-register without changing the
    // device identity or Wi-Fi configuration.
    registered = false;
    stateDirty = true;
    lastRegisterAttempt = 0;
  }
  delay(2);
}
