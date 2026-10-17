#!/usr/bin/env python3
"""YaoCore C-29 layering checker (DES-A §2.2 D-01..D-06/D-08, DES-B §2.3 D-09..D-13/D-17).

Producer: agent:test-engineer | Task: T-20 / wp-085-tooling
Contract: DES-A §2.2, §27.6; DES-B §2.3, §18.1; T-18 ruling 4b99e64 (§0.8/§0.9, §18.1);
          T-20 final-system-review F-01/F-02/F-06.
Status: T-20 implementation. D-12 entries are file/symbol-level and ``status`` is
enforced (a used entry that is not ``accepted`` fails the gate). Port location
exceptions are read from ``port_location_exceptions``; the two former hardcoded
port allowlists are gone. A port path that is not registered, a symbol outside the
registered set, or a non-accepted location status fails D-09/D-11. A port exception
never widens D-12: both allowlists are applied independently and the stricter one wins.

Usage:
  python3 tools/contract/check_layering.py --root .
  python3 tools/contract/check_layering.py --root . --report reports/contract/layering.json
  python3 tools/contract/check_layering.py --root . --list-exceptions

Exit codes: 0 = no violation, 1 = violation(s), 2 = input/CLI error.

Scope (implemented here):
  D-01 common import floor
  D-02 model import floor
  D-03 contracts import floor (when contracts/ exists)
  D-05/D-09 repository may not import service implementations or platform APIs
  D-06 adapters are only imported by the composition root / entryability
  D-08/D-11 UI and ViewModel platform/transport/storage/crypto direct imports
  D-11 ViewModel does not construct services/repositories/ViewModels
  D-12 pages/components import whitelist (file/symbol level, T-17/T-18 rulings)
  D-13 AC adapters stay on common/model
  D-17 app dependency direction and reverse-import ban
  @Provide/@Consume ban in production pages/components

Delegated to other checkers (reported as NOT_RUN by this tool):
  D-04/D-10 host-safe imports -> check_host_safe_imports.py (not yet landed)
  D-07/D-14 production mock exclusion -> check_production_mock_exclusion.py (not yet landed;
          host test TransportBoundary.test.mjs provides current evidence)
  D-15 cloud HTTP isolation -> review/static scan
  D-16 i18n hardcoded text -> entry/src/test/i18n/check_i18n.py --strict-ui
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional

MAIN_PREFIX = "entry/src/main/ets"
ALLOWLIST_DEFAULT = "tools/contract/layering_allowlist.json"
ACCEPTED_D12_STATUS = "accepted"
PORT_ACCEPTED_STATUS = "accepted-location-exception"
PORT_KINDS = {"port-only", "mixed-contract-dto", "pure-seam"}
RULE_ORDER = [
    "D-01", "D-02", "D-03", "D-05", "D-06", "D-08", "D-09", "D-11",
    "D-12", "D-13", "D-17",
]

IMPORT_RE = re.compile(
    r"^\s*(?P<export>export\s+)?import\s+(?P<kind>type\s+)?"
    r"(?:(?P<named>\{[^}]*\})|(?P<namespace>\*\s+as\s+\w+)|(?P<default>\w+))?"
    r"\s*(?:from\s*)?['\"](?P<spec>[^'\"]+)['\"]",
    re.MULTILINE | re.DOTALL,
)
EXPORT_FROM_RE = re.compile(
    r"^\s*export\s+(?P<kind>type\s+)?(?:\{[^}]*\}|\*\s+from)\s*from\s*['\"](?P<spec>[^'\"]+)['\"]",
    re.MULTILINE | re.DOTALL,
)
NEW_RE = re.compile(r"\bnew\s+(?P<name>[A-Z]\w*)\s*\(")
PROVIDE_RE = re.compile(r"@(?:Provide|Consume)\b")
CLASS_RE = re.compile(r"\bexport\s+(?:abstract\s+)?class\s+(?P<name>[A-Z]\w*)")

PLATFORM_PREFIXES = ("@ohos.", "@kit.", "node:")
D08_PLATFORM_RE = re.compile(
    r"@ohos\.(?:net|bluetooth|security\.asset|data\.relationalStore|security\.cryptoFramework|"
    r"file\.asset)|@kit\.(?:NetworkKit|ConnectivityKit|UniversalKeystoreKit|ArkData|"
    r"CryptoArchitectureKit)"
)

PAGES_APP_SEAMS = {
    "AppContext.ets",
    "NavigationService.ets",
    "ShellBootstrap.ets",
    "ShellGateRouting.ets",
    "ContinuousGestureGuard.ets",
    "PermissionPolicy.ets",
}
PAGES_I18N_FILES = {"I18nService.ets", "I18nModels.ets", "I18nKeys.ets"}
COMPONENT_I18N_FILES = {"I18nService.ets", "I18nModels.ets", "I18nKeys.ets"}
COMPONENT_VIEWMODEL_CORE = {"ViewModelCore.ets", "DoorConfirmationTracker.ets"}
APP_VM_FACTORY_FILES = {
    "AppCompositionRoot.ets",
    "PageVmFactory.ets",
    "ViewModelAppContextBridge.ets",
    "AppContextAdapters.ets",
    "PermissionGate.ets",
    "AppContext.ets",
    "AppPlatformPorts.ets",
}
APP_FORBIDDEN_TARGET_LAYERS = {"pages", "components", "entryability", "entrybackupability"}
LOWER_THAN_APP = {"viewmodel", "repository", "service", "model", "common", "components"}


@dataclass
class ImportRecord:
    line: int
    spec: str
    kind: str  # "type" | "value" | "side-effect"
    symbols: list[str] = field(default_factory=list)
    source_file: str = ""
    source_layer: str = ""
    target_rel: Optional[str] = None
    target_layer: Optional[str] = None
    rule_hint: str = ""


@dataclass
class Violation:
    rule: str
    path: str
    line: int
    spec: str
    message: str

    def as_dict(self) -> dict:
        return {
            "rule": self.rule,
            "path": self.path,
            "line": self.line,
            "import": self.spec,
            "message": self.message,
        }


@dataclass
class AllowEntry:
    rule: str
    source: str
    target: str
    symbols: list[str]
    type_only: bool
    status: str
    reason: str
    evidence: str
    id: str = ""
    used: int = 0

    def matches(self, record: ImportRecord) -> bool:
        if self.rule != "" and self.rule != record.rule_hint:
            return False
        if not _glob_match(self.source, record.source_file):
            return False
        if not _glob_match(self.target, record.target_rel or record.spec):
            return False
        if self.type_only and record.kind != "type":
            return False
        if self.symbols:
            if not record.symbols:
                return False
            if not set(record.symbols).issubset(set(self.symbols)):
                return False
        return True


@dataclass
class PortLocationException:
    id: str
    path: str
    symbols: list[str]
    kind: str
    status: str
    owner: str
    reason: str
    close_condition: str
    evidence: str
    used: int = 0

    def matches_path(self, target_rel: Optional[str]) -> bool:
        return target_rel is not None and target_rel == self.path

    def symbols_cover(self, record: ImportRecord) -> bool:
        # Empty symbol lists fail closed: a namespace/side-effect import is not
        # evidence that only the registered port symbols crossed the layer.
        if not self.symbols or not record.symbols:
            return False
        return set(record.symbols).issubset(set(self.symbols))


def _glob_match(pattern: str, value: str) -> bool:
    if pattern == value:
        return True
    regex = "^" + re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$"
    return re.match(regex, value) is not None


def norm(path: Path) -> str:
    return path.as_posix()


def layer_of(target_rel: Optional[str]) -> Optional[str]:
    if target_rel is None:
        return None
    if not target_rel.startswith(MAIN_PREFIX + "/"):
        return None
    rest = target_rel[len(MAIN_PREFIX) + 1:]
    return rest.split("/", 1)[0]


def resolve_target(root: Path, source_file: Path, spec: str) -> Optional[str]:
    if spec.startswith("."):
        base = source_file.parent / spec
        candidate = Path(os.path.normpath(str(base)))
        for suffix in ("", ".ets", ".ts", ".mjs"):
            probe = Path(str(candidate) + suffix) if suffix else candidate
            if probe.is_file():
                return norm(probe.relative_to(root))
        # Keep the normalized path even when the fixture omits the file.
        return norm(Path(str(candidate) + ".ets").relative_to(root))
    if spec.startswith(MAIN_PREFIX + "/"):
        return spec
    return None


def parse_imports(root: Path, file: Path) -> list[ImportRecord]:
    text = file.read_text(encoding="utf-8")
    source_rel = norm(file.relative_to(root))
    source_layer = layer_of(source_rel) or ""
    records: list[ImportRecord] = []
    masked = _mask_comments(text)
    for match in IMPORT_RE.finditer(masked):
        spec = match.group("spec")
        kind = "type" if match.group("kind") else "value"
        symbols: list[str] = []
        if match.group("named"):
            symbols = _parse_named(match.group("named"))
        elif match.group("namespace") or match.group("default"):
            symbols = []
        if not match.group("named") and not match.group("namespace") and not match.group("default"):
            kind = "side-effect"
        line = masked[:match.start()].count("\n") + 1
        records.append(ImportRecord(
            line=line,
            spec=spec,
            kind=kind,
            symbols=symbols,
            source_file=source_rel,
            source_layer=source_layer,
            target_rel=resolve_target(root, file, spec),
            target_layer=layer_of(resolve_target(root, file, spec)),
        ))
    for match in EXPORT_FROM_RE.finditer(masked):
        spec = match.group("spec")
        line = masked[:match.start()].count("\n") + 1
        target = resolve_target(root, file, spec)
        records.append(ImportRecord(
            line=line,
            spec=spec,
            kind="type" if match.group("kind") else "value",
            symbols=[],
            source_file=source_rel,
            source_layer=source_layer,
            target_rel=target,
            target_layer=layer_of(target),
        ))
    return records


def _parse_named(body: str) -> list[str]:
    cleaned = body.strip().strip("{}").strip()
    if not cleaned:
        return []
    symbols: list[str] = []
    for part in cleaned.split(","):
        token = part.strip()
        if not token:
            continue
        token = re.sub(r"^type\s+", "", token)
        token = token.split(" as ")[0].strip()
        if token:
            symbols.append(token)
    return symbols


def _mask_comments(text: str) -> str:
    """Replace comment content with spaces, preserving newlines and offsets."""
    result = list(text)
    i = 0
    length = len(text)
    in_line = False
    in_block = False
    quote: Optional[str] = None
    while i < length:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < length else ""
        if in_line:
            if ch == "\n":
                in_line = False
            else:
                result[i] = " "
            i += 1
            continue
        if in_block:
            if ch == "*" and nxt == "/":
                result[i] = result[i + 1] = " "
                in_block = False
                i += 2
                continue
            if ch != "\n":
                result[i] = " "
            i += 1
            continue
        if quote is not None:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', "`"):
            quote = ch
            i += 1
            continue
        if ch == "/" and nxt == "/":
            result[i] = result[i + 1] = " "
            in_line = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            result[i] = result[i + 1] = " "
            in_block = True
            i += 2
            continue
        i += 1
    return "".join(result)


def collect_class_index(root: Path) -> dict[str, str]:
    index: dict[str, str] = {}
    main = root / MAIN_PREFIX
    for directory in ("service", "repository", "viewmodel"):
        base = main / directory
        if not base.is_dir():
            continue
        for path in base.rglob("*.ets"):
            text = _mask_comments(path.read_text(encoding="utf-8"))
            for match in CLASS_RE.finditer(text):
                index.setdefault(match.group("name"), norm(path.relative_to(root)))
    return index


def _load_allowlist_payload(root: Path, explicit: Optional[Path]) -> tuple[Path, dict]:
    path = explicit if explicit is not None else root / ALLOWLIST_DEFAULT
    if path is None or not path.is_file():
        return path, {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid allowlist JSON {path}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError(f"allowlist must be a JSON object: {path}")
    return path, payload


def load_allowlist(root: Path, explicit: Optional[Path]) -> list[AllowEntry]:
    _path, payload = _load_allowlist_payload(root, explicit)
    raw_entries = payload.get("entries", [])
    if not isinstance(raw_entries, list):
        raise ValueError("allowlist 'entries' must be a list")
    entries: list[AllowEntry] = []
    for raw in raw_entries:
        if not isinstance(raw, dict):
            raise ValueError("allowlist entry must be an object")
        status = str(raw.get("status", "pending-unregistered"))
        entries.append(AllowEntry(
            rule=str(raw.get("rule", "")),
            source=str(raw.get("from", "")),
            target=str(raw.get("import", "")),
            symbols=[str(item) for item in raw.get("symbols", [])],
            type_only=bool(raw.get("type_only", False)),
            status=status,
            reason=str(raw.get("reason", "")),
            evidence=str(raw.get("evidence", "")),
            id=str(raw.get("id", "")),
        ))
    return entries


def load_port_location_exceptions(root: Path, explicit: Optional[Path]) -> list[PortLocationException]:
    """Read the DES-A §27.6.2 / DES-B §18.1 port location registry.

    Schema is intentionally strict: exact file path, non-empty symbol set,
    declared kind, and an accepted/pending status. A wildcard path or unknown
    kind is an input error (exit 2) rather than a silent widening.
    """
    _path, payload = _load_allowlist_payload(root, explicit)
    raw_exceptions = payload.get("port_location_exceptions", [])
    if not isinstance(raw_exceptions, list):
        raise ValueError("allowlist 'port_location_exceptions' must be a list")
    exceptions: list[PortLocationException] = []
    seen_paths: set[str] = set()
    for raw in raw_exceptions:
        if not isinstance(raw, dict):
            raise ValueError("port_location_exceptions entry must be an object")
        path = str(raw.get("path", ""))
        symbols = [str(item) for item in raw.get("symbols", [])]
        kind = str(raw.get("kind", ""))
        status = str(raw.get("status", ""))
        if not path or "*" in path or "?" in path:
            raise ValueError(f"port exception path must be exact, got {path!r}")
        if path in seen_paths:
            raise ValueError(f"duplicate port exception path {path!r}")
        if not symbols:
            raise ValueError(f"port exception {path!r} must declare symbols")
        if kind not in PORT_KINDS:
            raise ValueError(f"port exception {path!r} has invalid kind {kind!r}")
        if status != PORT_ACCEPTED_STATUS and not status.startswith("pending-"):
            raise ValueError(
                f"port exception {path!r} has invalid status {status!r}")
        seen_paths.add(path)
        exceptions.append(PortLocationException(
            id=str(raw.get("id", "")),
            path=path,
            symbols=symbols,
            kind=kind,
            status=status,
            owner=str(raw.get("owner", "")),
            reason=str(raw.get("reason", "")),
            close_condition=str(raw.get("close_condition", "")),
            evidence=str(raw.get("evidence", "")),
        ))
    return exceptions


def _allowed(record: ImportRecord, allowlist: list[AllowEntry], rule: str) -> tuple[bool, Optional[AllowEntry]]:
    setattr(record, "rule_hint", rule)
    for entry in allowlist:
        if entry.matches(record):
            entry.used += 1
            # T-20 status enforcement: a used exception that is still pending
            # (or missing a status) is a gate failure, never a silent pass.
            if entry.status != ACCEPTED_D12_STATUS:
                return False, entry
            return True, entry
    return False, None


def _match_port_exception(
        record: ImportRecord,
        port_exceptions: list[PortLocationException]) -> tuple[bool, Optional[PortLocationException], str]:
    """Return (accepted, entry, failure detail) for a D-09/D-11 import.

    Only the target path is registry-keyed; the import symbols must be a
    non-empty subset of the registered symbols. Status other than
    accepted-location-exception fails closed. Unregistered paths fail closed.
    """
    for entry in port_exceptions:
        if not entry.matches_path(record.target_rel):
            continue
        if not entry.symbols_cover(record):
            return False, entry, (
                f"symbols {sorted(record.symbols)!r} are not covered by {entry.id or entry.path}; "
                "add a new reviewed exception instead of widening this one")
        # Count a pending match as used so used+pending is reported honestly.
        entry.used += 1
        if entry.status != PORT_ACCEPTED_STATUS:
            return False, entry, (
                f"port exception {entry.id or entry.path} status {entry.status!r} "
                "is not accepted-location-exception")
        return True, entry, ""
    return False, None, "path is not registered in port_location_exceptions"


def _base_layer(record: ImportRecord) -> Optional[str]:
    return record.target_layer


def evaluate(root: Path, allowlist: list[AllowEntry],
             port_exceptions: list[PortLocationException]) -> tuple[list[Violation], list[str]]:
    main = root / MAIN_PREFIX
    if not main.is_dir():
        raise FileNotFoundError(
            f"{main} does not exist (run with --root at the repository root)")
    files = sorted(main.rglob("*.ets"))
    class_index = collect_class_index(root)
    records: list[ImportRecord] = []
    for file in files:
        records.extend(parse_imports(root, file))
    violations: list[Violation] = []
    skipped: list[str] = []

    def add(rule: str, record: ImportRecord, message: str) -> None:
        allowed, entry = _allowed(record, allowlist, rule)
        if allowed:
            return
        if entry is not None:
            message = (f"{message}; exception {entry.id or entry.source} has status "
                       f"{entry.status!r}, only {ACCEPTED_D12_STATUS!r} is accepted")
        violations.append(Violation(rule, record.source_file, record.line, record.spec, message))

    for record in records:
        source_layer = record.source_layer
        target_layer = record.target_layer
        spec = record.spec
        target_rel = record.target_rel or ""
        is_platform = spec.startswith(PLATFORM_PREFIXES)

        # D-01 common import floor.
        if source_layer == "common":
            if is_platform or target_layer not in (None, "common"):
                add("D-01", record,
                    f"common/** may only import common/**; got {spec!r}")

        # D-02 model import floor.
        if source_layer == "model":
            if is_platform or target_layer not in (None, "common", "model"):
                add("D-02", record,
                    f"model/** may only import common/** (+ model); got {spec!r}")

        # D-03 contracts import floor (only when contracts/ exists).
        if source_layer == "contracts":
            if is_platform or target_layer not in (None, "common", "model", "contracts"):
                add("D-03", record,
                    f"contracts/** may only import common/** or model/**; got {spec!r}")

        # D-05 / D-09 repository floor. D-09 ports come only from the
        # versioned port_location_exceptions registry (no hardcoded paths).
        if source_layer == "repository":
            if is_platform:
                add("D-05", record, f"repository/** must not import platform API; got {spec!r}")
            elif target_layer == "service":
                port_ok, _port_entry, port_failure = _match_port_exception(
                    record, port_exceptions)
                if not port_ok:
                    violations.append(Violation(
                        "D-09", record.source_file, record.line, spec,
                        f"repository/** must not import service implementation; "
                        f"got {spec!r} ({port_failure})"))
            elif target_layer not in (None, "common", "model", "contracts", "repository"):
                add("D-05", record,
                    f"repository/** may only import common/model/contracts; got {spec!r}")

        # D-06 adapters are assembled only by composition root / entryability.
        if "/adapters/" in target_rel:
            same_adapter_dir = ("/adapters/" in record.source_file and
                                record.source_file.rsplit("/", 1)[0] ==
                                target_rel.rsplit("/", 1)[0])
            if source_layer not in ("app", "entryability") and not same_adapter_dir:
                add("D-06", record,
                    "adapters must only be imported by app/** or entryability/**; "
                    f"{record.source_file} imports {spec!r}")

        # D-08 UI/ViewModel platform ban (network/BLE/asset/RDB/crypto).
        if source_layer in ("pages", "components", "viewmodel") and D08_PLATFORM_RE.search(spec):
            add("D-08", record,
                f"{source_layer}/** must not call platform transport/storage/crypto directly; got {spec!r}")

        # D-11 ViewModel import rules.
        if source_layer == "viewmodel":
            if is_platform:
                add("D-11", record, f"viewmodel/** must not import platform API; got {spec!r}")
            elif "/adapters/" in target_rel:
                add("D-11", record, f"viewmodel/** must not import adapters; got {spec!r}")
            elif target_layer == "service" and _service_dir(target_rel) in (
                    "gateway", "ble", "crypto", "storage"):
                port_ok, _port_entry, port_failure = _match_port_exception(
                    record, port_exceptions)
                if not port_ok:
                    violations.append(Violation(
                        "D-11", record.source_file, record.line, spec,
                        f"viewmodel/** must not import service/{_service_dir(target_rel)} "
                        f"implementation; got {spec!r} ({port_failure})"))

        # D-12 pages import whitelist.
        if source_layer == "pages":
            if is_platform and not spec.startswith("@kit.AbilityKit"):
                add("D-12", record, f"pages/** must not import platform API; got {spec!r}")
            elif target_layer == "service":
                if not _is_pages_i18n(target_rel):
                    add("D-12", record,
                        f"pages/** may only import C-14 i18n public types from service/**; got {spec!r}")
            elif target_layer == "repository":
                if not _is_pages_repository_dto(target_rel):
                    add("D-12", record,
                        f"pages/** must not import repository implementation; got {spec!r}")
            elif target_layer == "app":
                if not _is_pages_app_seam(target_rel, record):
                    add("D-12", record,
                        f"pages/** may only import whitelisted app UI seams; got {spec!r}")
            elif target_layer not in (None, "common", "model", "viewmodel", "components",
                                      "contracts", "pages"):
                add("D-12", record,
                    f"pages/** import is outside the D-12 whitelist; got {spec!r}")

        # D-12 components import whitelist.
        if source_layer == "components":
            if is_platform:
                add("D-12", record, f"components/** must not import platform API; got {spec!r}")
            elif target_layer == "app":
                add("D-12", record, f"components/** must not import app/**; got {spec!r}")
            elif target_layer == "repository":
                if not _is_components_repository_dto(record):
                    add("D-12", record,
                        f"components/** may only import read-only DTO types from repository/**; got {spec!r}")
            elif target_layer == "service":
                if not _is_components_service_target(record):
                    add("D-12", record,
                        f"components/** service import is outside the file/symbol allowlist; got {spec!r}")
            elif target_layer == "viewmodel":
                if not _is_components_viewmodel_target(record):
                    add("D-12", record,
                        f"components/** may only import viewmodel/core pure UI vocabulary; got {spec!r}")
            elif target_layer not in (None, "common", "model", "components", "contracts"):
                add("D-12", record,
                    f"components/** import is outside the D-12 whitelist; got {spec!r}")

        # D-13 AC adapters.
        if source_layer == "service" and _service_dir(record.source_file) == "ac":
            allowed_target = (target_layer in (None, "common", "model") or
                              target_rel.startswith(MAIN_PREFIX + "/service/ac/"))
            if is_platform or not allowed_target:
                add("D-13", record,
                    f"service/ac/** may only import common/** or model/**; got {spec!r}")

        # D-17 app dependency direction.
        if source_layer == "app":
            if target_layer in APP_FORBIDDEN_TARGET_LAYERS:
                add("D-17", record, f"app/** must not import {target_layer}/**; got {spec!r}")
            elif target_layer == "viewmodel" and not _is_app_vm_port_file(record.source_file):
                add("D-17", record,
                    "app/** may only import viewmodel/** from factory/port-adapter files; "
                    f"got {record.source_file} -> {spec!r}")
        if source_layer in LOWER_THAN_APP and target_layer == "app":
            add("D-17", record,
                f"{source_layer}/** must not import app/** (reverse dependency); got {spec!r}")

    # Per-file checks.
    for file in files:
        rel = norm(file.relative_to(root))
        source_layer = layer_of(rel) or ""
        text = _mask_comments(file.read_text(encoding="utf-8"))
        if source_layer in ("pages", "components") and PROVIDE_RE.search(text):
            violations.append(Violation(
                "D-12", rel, text[:PROVIDE_RE.search(text).start()].count("\n") + 1,
                "@Provide/@Consume",
                "production pages/components must use explicit @Require props (no @Provide/@Consume)"))
        if source_layer in ("pages", "components", "viewmodel"):
            for match in NEW_RE.finditer(text):
                name = match.group("name")
                origin = class_index.get(name)
                if origin is None:
                    continue
                if not re.search(r"(?:Service|Repository|ViewModel|Adapter)$", name):
                    continue
                if origin.startswith(MAIN_PREFIX + "/service/") or \
                        origin.startswith(MAIN_PREFIX + "/repository/") or \
                        origin.startswith(MAIN_PREFIX + "/viewmodel/"):
                    rule = "D-11" if source_layer == "viewmodel" else "D-12"
                    violations.append(Violation(
                        rule, rel, text[:match.start()].count("\n") + 1, name,
                        f"{source_layer}/** must not construct service/repository/ViewModel "
                        f"({name} defined in {origin})"))

    violations.extend(validate_port_location_files(root, port_exceptions))

    skipped.extend([
        "D-04/D-10 host-safe imports -> check_host_safe_imports.py (not landed)",
        "D-07/D-14 production mock exclusion -> check_production_mock_exclusion.py (not landed); "
        "current evidence: host TransportBoundary.test.mjs",
        "D-15 cloud HTTP isolation -> review/static scan (not implemented)",
        "D-16 i18n hardcoded strings -> entry/src/test/i18n/check_i18n.py --strict-ui",
    ])
    violations.sort(key=lambda item: (item.path, item.line, item.rule))
    return violations, skipped


def _service_dir(target_rel: str) -> str:
    prefix = MAIN_PREFIX + "/service/"
    if not target_rel.startswith(prefix):
        return ""
    return target_rel[len(prefix):].split("/", 1)[0]


def validate_port_location_files(root: Path,
                                 port_exceptions: list[PortLocationException]) -> list[Violation]:
    """Fail closed when a registered port file drifts from its registration.

    DES-B §18.1 item 4: a registered file that adds ``@ohos.*`` / adapter /
    unregistered repository dependencies invalidates its exception. A repository
    import is tolerated only when the target itself has a registered location
    exception (e.g. GatewayTransportPorts -> GatewayPorts), which preserves the
    pre-existing physical-layout exception instead of hiding a new dependency.
    """
    violations: list[Violation] = []
    registered = {entry.path for entry in port_exceptions}
    for entry in port_exceptions:
        path = root / entry.path
        if not path.is_file():
            continue
        for record in parse_imports(root, path):
            spec = record.spec
            target_rel = record.target_rel or ""
            reason = ""
            if spec.startswith(PLATFORM_PREFIXES):
                reason = "registered port file must not import platform API"
            elif "/adapters/" in target_rel:
                reason = "registered port file must not import an adapter"
            elif (record.target_layer == "repository" and
                  record.source_layer != "repository" and
                  target_rel not in registered):
                reason = "registered port file must not add an unregistered repository dependency"
            if reason:
                violations.append(Violation(
                    "PORT-LOC", entry.path, record.line, spec,
                    f"{reason}; location exception {entry.id or entry.path} is invalid"))
    return violations


def _is_pages_i18n(target_rel: str) -> bool:
    prefix = MAIN_PREFIX + "/service/i18n/"
    return target_rel.startswith(prefix) and target_rel.rsplit("/", 1)[-1] in PAGES_I18N_FILES


def _is_pages_repository_dto(target_rel: str) -> bool:
    # T-18 R3-01: existing pages read-only DTO/enum imports are tracked in the
    # allowlist, not silently permitted by this function.
    return False


def _is_pages_app_seam(target_rel: str, record: ImportRecord) -> bool:
    prefix = MAIN_PREFIX + "/app/"
    if not target_rel.startswith(prefix):
        return False
    name = target_rel[len(prefix):]
    if name in PAGES_APP_SEAMS:
        return True
    if name == "PageVmFactory.ets":
        return record.kind == "type" and set(record.symbols or []).issubset({"PageVmFactoryPort"})
    return False


def _is_components_repository_dto(record: ImportRecord) -> bool:
    target_rel = record.target_rel or ""
    if target_rel != MAIN_PREFIX + "/repository/DomainModels.ets":
        return False
    if record.kind != "type":
        return False
    return set(record.symbols or []).issubset(
        {"DeviceRecord", "SceneExecutionResult", "SceneExecutionProgress"})


def _is_components_service_target(record: ImportRecord) -> bool:
    target_rel = record.target_rel or ""
    prefix = MAIN_PREFIX + "/service/"
    if not target_rel.startswith(prefix):
        return False
    name = target_rel[len(prefix):]
    if name.rsplit("/", 1)[-1] in COMPONENT_I18N_FILES:
        return True
    if name == "ac/AcModels.ets":
        if record.source_file.endswith("/components/support/UiMapping.ets"):
            return set(record.symbols or []).issubset(
                {"AcViewState", "AcBrand", "AcModeViewKind", "AcVocabulary"})
        if record.source_file.endswith("/components/DeviceCards.ets"):
            return record.kind == "type" and set(record.symbols or []).issubset({"AcViewState"})
        return False
    return False


def _is_components_viewmodel_target(record: ImportRecord) -> bool:
    target_rel = record.target_rel or ""
    prefix = MAIN_PREFIX + "/viewmodel/core/"
    if not target_rel.startswith(prefix):
        return False
    return target_rel[len(prefix):] in COMPONENT_VIEWMODEL_CORE


def _is_app_vm_port_file(source_file: str) -> bool:
    return source_file.rsplit("/", 1)[-1] in APP_VM_FACTORY_FILES


def render_report(root: Path, violations: list[Violation], skipped: list[str],
                  allowlist: list[AllowEntry],
                  port_exceptions: list[PortLocationException]) -> dict:
    used = [entry for entry in allowlist if entry.used > 0]
    pending = [entry for entry in allowlist if entry.status != ACCEPTED_D12_STATUS]
    used_ports = [entry for entry in port_exceptions if entry.used > 0]
    pending_ports = [entry for entry in port_exceptions if entry.status != PORT_ACCEPTED_STATUS]
    return {
        "tool": "check_layering.py",
        "producer": "agent:test-engineer",
        "task": "T-20 / wp-085-tooling",
        "root": norm(root),
        "main_root": MAIN_PREFIX,
        "rules_checked": RULE_ORDER,
        "rules_delegated": skipped,
        "file_count": len(list((root / MAIN_PREFIX).rglob("*.ets"))),
        "violation_count": len(violations),
        "violations": [item.as_dict() for item in violations],
        "exceptions_used_count": len(used),
        "exceptions": [
            {
                "id": entry.id,
                "rule": entry.rule,
                "from": entry.source,
                "import": entry.target,
                "symbols": entry.symbols,
                "type_only": entry.type_only,
                "status": entry.status,
                "reason": entry.reason,
                "evidence": entry.evidence,
                "used": entry.used,
            }
            for entry in used
        ],
        "unused_exceptions": [
            {
                "id": entry.id,
                "rule": entry.rule,
                "from": entry.source,
                "import": entry.target,
                "status": entry.status,
            }
            for entry in allowlist if entry.used == 0
        ],
        "pending_exceptions": [
            {
                "id": entry.id,
                "rule": entry.rule,
                "from": entry.source,
                "import": entry.target,
                "status": entry.status,
                "used": entry.used,
            }
            for entry in pending
        ],
        "port_exceptions_used_count": len(used_ports),
        "port_location_exceptions": [
            {
                "id": entry.id,
                "path": entry.path,
                "symbols": entry.symbols,
                "kind": entry.kind,
                "status": entry.status,
                "owner": entry.owner,
                "reason": entry.reason,
                "close_condition": entry.close_condition,
                "evidence": entry.evidence,
                "used": entry.used,
            }
            for entry in port_exceptions
        ],
        "port_exceptions_used": [
            {
                "id": entry.id,
                "path": entry.path,
                "symbols": entry.symbols,
                "kind": entry.kind,
                "status": entry.status,
                "used": entry.used,
            }
            for entry in used_ports
        ],
        "port_exceptions_unused": [
            {
                "id": entry.id,
                "path": entry.path,
                "status": entry.status,
            }
            for entry in port_exceptions if entry.used == 0
        ],
        "port_pending_exceptions": [
            {
                "id": entry.id,
                "path": entry.path,
                "status": entry.status,
                "used": entry.used,
            }
            for entry in pending_ports
        ],
    }


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--report", help="write JSON report to this path")
    parser.add_argument("--allowlist", help="override allowlist path")
    parser.add_argument("--list-exceptions", action="store_true",
                        help="print the versioned exceptions and exit")
    args = parser.parse_args(list(argv) if argv is not None else None)
    root = Path(args.root).resolve()
    explicit_allowlist = Path(args.allowlist) if args.allowlist else None
    try:
        allowlist = load_allowlist(root, explicit_allowlist)
        port_exceptions = load_port_location_exceptions(root, explicit_allowlist)
        if args.list_exceptions:
            for entry in allowlist:
                print(f"{entry.rule}\t{entry.source}\t{entry.target}\t{entry.status}\t{entry.reason}")
            for entry in port_exceptions:
                print(f"PORT\t{entry.path}\t{entry.kind}\t{entry.status}\t{entry.owner}")
            return 0
        violations, skipped = evaluate(root, allowlist, port_exceptions)
    except (FileNotFoundError, ValueError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    except Exception as error:  # pragma: no cover - defensive input error
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    report = render_report(root, violations, skipped, allowlist, port_exceptions)
    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                               encoding="utf-8")
    pending = [entry for entry in allowlist if entry.status != ACCEPTED_D12_STATUS]
    pending_used = [entry for entry in pending if entry.used > 0]
    port_pending = [entry for entry in port_exceptions
                    if entry.status != PORT_ACCEPTED_STATUS]
    port_pending_used = [entry for entry in port_pending if entry.used > 0]
    print(f"check_layering: files={report['file_count']} violations={len(violations)} "
          f"exceptions_used={report['exceptions_used_count']} pending={len(pending)} "
          f"pending_used={len(pending_used)} "
          f"port_exceptions_used={report['port_exceptions_used_count']} "
          f"port_pending={len(port_pending)} port_pending_used={len(port_pending_used)}")
    for item in violations:
        print(f"  {item.rule} {item.path}:{item.line} {item.spec} -- {item.message}")
    for entry in pending:
        print(f"  PENDING {entry.rule} {entry.source} -> {entry.target} "
              f"({entry.status}, used={entry.used})")
    for entry in port_pending:
        print(f"  PORT PENDING {entry.id or entry.path} ({entry.status}, used={entry.used})")
    if violations:
        print(f"check_layering: FAIL ({len(violations)} violation(s))")
        return 1
    print("check_layering: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
