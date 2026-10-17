#!/usr/bin/env bash
# YaoCore host test runner (no device, no emulator).
# Producer: agent:test-engineer | Task: T-05 / wp-010-test-plan
#
# Why this exists: `hvigorw test` compiles the Hypium host entry successfully,
# but its bundled Linux Previewer cannot start the test ability on this host
# ("JsApp::Run ability start failed.Linux is not supported"), and the default
# SDK previewer is missing libshared_libz.so. This runner executes pure logic
# tests with Node's built-in test runner instead. It intentionally does not
# replace device/ohosTest evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

exec node --no-warnings \
  --import "${SCRIPT_DIR}/host/register-ets.mjs" \
  --test --test-reporter=tap \
  "${SCRIPT_DIR}"/host/*.test.mjs
