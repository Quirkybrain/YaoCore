#!/usr/bin/env bash
#
# YaoCore T-01 build/test baseline verification.
#
# Verified on 2026-10-17 with:
#   ohpm 26.0.0.630, hvigor 6.26.8, codelinter 6.0.240,
#   Node v24.15.0, Java 21.0.12.1, HarmonyOS SDK 26.0.0 (apiVersion 26).
#
# Default mode (safe for a clean checkout):
#   1. ohpm install
#   2. hvigorw clean assembleHap --no-daemon
#   3. codelinter -c code-linter.json5 -p default .
#   4. build the ohosTest HAP (compiles the Hypium probe, does NOT run it)
#   5. hvigorw assembleApp --no-daemon (unsigned app package)
#
# Runtime tests are deliberately NOT claimed as passing by default:
#   - Hypium test cases under entry/src/ohosTest require a connected device
#     (or emulator) and a signed test HAP; this project has signingConfigs: [].
#   - The host-side `hvigorw test` runner expects entry/src/test/List.test.ets,
#     which is outside this task's allowed write scope.
#
# Usage:
#   tools/build/verify-baseline.sh                     # build + lint + compile probe
#   tools/build/verify-baseline.sh --with-device-tests # require hdc device, then run onDeviceTest
#   tools/build/verify-baseline.sh --with-host-tests   # run `hvigorw test` when entry/src/test exists
#
# Prerequisites:
#   - Run from anywhere inside the repository (the script cd's to the repo root).
#   - DEVECO_SDK_HOME points at the HarmonyOS SDK root (contains default/sdk-pkg.json).
#   - ohpm, hvigorw, codelinter, node, java are on PATH.
#   - Network access to the ohpm registry for the first install.
#
# Logs are written to a temporary directory unless YAOCORE_BASELINE_LOG_DIR is set.
# Build outputs are gitignored: entry/build/, build/, .test/, oh_modules/, .hvigor/.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

WITH_DEVICE_TESTS=0
WITH_HOST_TESTS=0

for arg in "$@"; do
  case "$arg" in
    --with-device-tests) WITH_DEVICE_TESTS=1 ;;
    --with-host-tests) WITH_HOST_TESTS=1 ;;
    -h|--help)
      sed -n '2,45p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

for tool in ohpm hvigorw codelinter node java; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' is not on PATH." >&2
    exit 2
  fi
done

if [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
  echo "ERROR: DEVECO_SDK_HOME is not set." >&2
  echo "       Example: export DEVECO_SDK_HOME=\"\$HOME/harmonyos/command-line-tools/sdk\"" >&2
  exit 2
fi

if [[ ! -f "$DEVECO_SDK_HOME/default/sdk-pkg.json" ]]; then
  echo "ERROR: $DEVECO_SDK_HOME/default/sdk-pkg.json not found." >&2
  exit 2
fi

LOG_DIR="${YAOCORE_BASELINE_LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/yaocore-baseline.XXXXXX")}"
mkdir -p "$LOG_DIR"
echo "Repository: $ROOT_DIR"
echo "Logs:       $LOG_DIR"

run_step() {
  local name="$1"
  shift
  local log="$LOG_DIR/${name}.log"
  printf '\n==> %s\n    $ %s\n' "$name" "$*"
  if "$@" >"$log" 2>&1; then
    printf '    PASS (%s)\n' "$log"
    tail -n 3 "$log" | sed 's/^/    | /'
  else
    local status=$?
    printf '    FAIL (exit %d, log: %s)\n' "$status" "$log" >&2
    tail -n 40 "$log" >&2
    exit "$status"
  fi
}

{
  echo "date: $(date -Is)"
  echo "repository: $ROOT_DIR"
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  echo "commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "DEVECO_SDK_HOME: $DEVECO_SDK_HOME"
  echo "sdk: $(tr -d '\n' < "$DEVECO_SDK_HOME/default/sdk-pkg.json")"
  echo "ohpm: $(ohpm --version 2>&1)"
  echo "hvigorw: $(hvigorw --version 2>&1)"
  echo "codelinter: $(codelinter --version 2>&1)"
  echo "node: $(node -v 2>&1)"
  echo "java: $(java -version 2>&1 | head -n 1)"
  HDC_BIN="${HDC_BIN:-$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc}"
  if [[ -x "$HDC_BIN" ]]; then
    echo "hdc: $($HDC_BIN -v 2>&1 | head -n 1)"
    echo "hdc targets: $($HDC_BIN list targets 2>&1 | tr '\n' ' ')"
  else
    echo "hdc: not found at $HDC_BIN"
  fi
} | tee "$LOG_DIR/environment.log"

# 1. Resolve dependencies and generate/refresh oh-package-lock.json5.
run_step ohpm-install ohpm install

# 2. Clean HAP build. Produces an UNSIGNED HAP because signingConfigs is empty.
run_step assemble-hap hvigorw clean assembleHap --no-daemon

# 3. Static analysis with the repository code-linter.json5.
run_step codelinter codelinter -c code-linter.json5 -p default .

# 4. Compile the Hypium ohosTest probe. This validates test code compilation only.
run_step assemble-ohos-test-hap \
  hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon

# 5. Package the unsigned .app (also confirms project-level packaging works).
run_step assemble-app hvigorw assembleApp --no-daemon

if [[ "$WITH_HOST_TESTS" -eq 1 ]]; then
  if [[ ! -f entry/src/test/List.test.ets ]]; then
    echo "BLOCKED: entry/src/test/List.test.ets does not exist." >&2
    echo "         The host unit-test runner requires that path; create local tests" >&2
    echo "         under entry/src/test with the owning task before using this flag." >&2
    exit 3
  fi
  run_step host-unit-test hvigorw test --no-daemon
else
  echo
  echo "RUNTIME TESTS: NOT RUN (host unit tests require entry/src/test; not in this task's write scope)."
fi

if [[ "$WITH_DEVICE_TESTS" -eq 1 ]]; then
  HDC_BIN="${HDC_BIN:-$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc}"
  if [[ ! -x "$HDC_BIN" ]]; then
    echo "BLOCKED: hdc not found at $HDC_BIN" >&2
    exit 4
  fi
  TARGETS="$("$HDC_BIN" list targets 2>&1 || true)"
  if [[ -z "$TARGETS" || "$TARGETS" == *"[Empty]"* ]]; then
    echo "BLOCKED: no HarmonyOS device/emulator is connected (hdc list targets is empty)." >&2
    exit 4
  fi
  # Instrumented Hypium tests. Requires a signed test HAP and a connected target.
  run_step on-device-test \
    hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon
else
  echo "DEVICE TESTS:   NOT RUN (no connected device/emulator in this baseline; pass --with-device-tests when one is available)."
fi

echo
echo "BASELINE SUMMARY"
echo "  install:                 PASS"
echo "  clean HAP build:         PASS"
echo "  static check:            PASS"
echo "  ohosTest HAP compile:    PASS (compilation only)"
echo "  app packaging:           PASS (unsigned)"
if [[ "$WITH_HOST_TESTS" -eq 1 ]]; then
  echo "  host unit tests:         PASS"
else
  echo "  host unit tests:         NOT RUN"
fi
if [[ "$WITH_DEVICE_TESTS" -eq 1 ]]; then
  echo "  on-device tests:         PASS"
else
  echo "  on-device tests:         NOT RUN (device/emulator required)"
fi
echo "  logs:                    $LOG_DIR"
