#!/usr/bin/env python3
"""YaoCore i18n checker (CHK-01..CHK-09).

Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
Contract: DES-B §7.4.4; I18N-DESIGN §6; TEST-001 §6

Usage:
  python3 entry/src/test/i18n/check_i18n.py \
    --root . \
    --report entry/src/test/evidence/t10-i18n-report.json \
    --allowlist entry/src/test/i18n/allowlist.json \
    --strict-ui

Exit codes:
  0  all blocking checks pass (warnings may remain)
  1  at least one blocking check failed
  2  tool/input error (missing file, malformed JSON)

The checker is a development/CI tool. It is not part of the ArkTS build graph.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

CHECK_IDS = [f"CHK-{index:02d}" for index in range(1, 10)]
RAW_LOCALES = ["zh-CN", "en-US"]
STRING_LOCALES = {"base": "zh-CN", "en_US": "en-US"}
PARAM_RE = re.compile(r"\{([^{}]*)\}")
PARAM_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
ENGLISH_WORD_RE = re.compile(r"[A-Za-z][A-Za-z']*")
CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
KEY_TOKEN_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){0,3}$")
T_CALL_RE = re.compile(r"\bt\(\s*(['\"])([^'\"]+)\1")
TKEY_CALL_RE = re.compile(r"\bI18nKey\(\s*(['\"])([^'\"]+)\1")
R_CALL_RE = re.compile(r"\$r\(\s*(['\"])app\.string\.([A-Za-z0-9_]+)\1")
SQL_RE = re.compile(
    r"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|FROM|WHERE|VALUES|TABLE|INDEX|PRAGMA|"
    r"JOIN|TEXT|INTEGER|REAL|BLOB|PRIMARY|KEY|NOT|NULL|ORDER|BY|SET|CHECK|CONSTRAINT|UNIQUE|DEFAULT)\b",
    re.IGNORECASE,
)
METADATA_RE = re.compile(r"\$string:([A-Za-z0-9_]+)")
STRING_LITERAL_RE = re.compile(r"(['\"])((?:\\.|(?!\1).)*)\1")


class ToolError(Exception):
    pass


def load_json(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ToolError(f"cannot read {path}: {error}") from error
    try:
        return json.loads(text, object_pairs_hook=reject_duplicate_pairs(path))
    except json.JSONDecodeError as error:
        raise ToolError(f"invalid JSON in {path}: {error}") from error


def reject_duplicate_pairs(path: Path):
    def hook(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ToolError(f"duplicate key {key!r} in {path}")
            result[key] = value
        return result

    return hook


def flatten(node, prefix, out, path):
    if isinstance(node, dict):
        if not node:
            raise ToolError(f"empty object at {prefix or '<root>'} in {path}")
        for key, value in node.items():
            flatten(value, f"{prefix}.{key}" if prefix else key, out, path)
        return
    if not isinstance(node, str):
        raise ToolError(f"non-string leaf {prefix!r} in {path}")
    if prefix in out:
        raise ToolError(f"duplicate flattened key {prefix!r} in {path}")
    out[prefix] = node


def normalize_plural(key: str) -> str:
    for suffix in ("_one", "_other"):
        if key.endswith(suffix):
            return key[: -len(suffix)]
    return key


def params_of(value: str) -> set[str]:
    return {name for name in PARAM_RE.findall(value)}


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def relative(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def finding(file: str = "", line: int = 0, key: str = "", message: str = "", severity: str = "blocking"):
    item = {"message": message, "severity": severity}
    if file:
        item["file"] = file
    if line:
        item["line"] = line
    if key:
        item["key"] = key
    return item


def read_source_files(root: Path):
    source_root = root / "entry/src/main/ets"
    files = []
    if source_root.exists():
        for path in sorted(source_root.rglob("*")):
            if path.suffix in (".ets", ".ts"):
                files.append(path)
    return files


def strip_and_extract_literals(text: str):
    """Return (clean_text_for_keys, [(literal, line, prefix)]) without comments.

    String literals are returned for CHK-07. `clean_text_for_keys` preserves
    strings and replaces comments with spaces (newlines preserved).
    """
    literals = []
    clean = list(text)
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        nxt = text[index + 1] if index + 1 < length else ""
        if char == "/" and nxt == "/":
            start = index
            while index < length and text[index] != "\n":
                index += 1
            for pos in range(start, index):
                clean[pos] = " "
            continue
        if char == "/" and nxt == "*":
            start = index
            index += 2
            while index + 1 < length and not (text[index] == "*" and text[index + 1] == "/"):
                index += 1
            index = min(index + 2, length)
            for pos in range(start, index):
                if clean[pos] != "\n":
                    clean[pos] = " "
            continue
        if char in ("'", '"', "`"):
            start = index
            quote = char
            index += 1
            value = []
            while index < length:
                current = text[index]
                if current == "\\" and index + 1 < length:
                    value.append(text[index + 1])
                    index += 2
                    continue
                if current == quote:
                    index += 1
                    break
                value.append(current)
                index += 1
            prefix = text[max(0, start - 4):start]
            literals.append(("".join(value), line_of(text, start), prefix, text[start:index]))
            continue
        index += 1
    return "".join(clean), literals


def load_allowlist(path: Path | None):
    if path is None or not path.exists():
        return {"entries": [], "keyPrefixes": [], "keyEntries": []}
    data = load_json(path)
    if not isinstance(data, dict):
        raise ToolError(f"allowlist must be a JSON object: {path}")
    entries = data.get("entries", [])
    key_prefixes = data.get("keyPrefixes", [])
    key_entries = data.get("keyEntries", [])
    if not isinstance(entries, list) or not isinstance(key_prefixes, list) or not isinstance(key_entries, list):
        raise ToolError(f"allowlist lists are malformed: {path}")
    return {"entries": entries, "keyPrefixes": key_prefixes, "keyEntries": key_entries}


def allowlist_lookup(allowlist, file: str, line: int) -> bool:
    for entry in allowlist["entries"]:
        if entry.get("file") == file and int(entry.get("line", 0)) == line:
            return True
    return False


def key_allowlisted(allowlist, key: str) -> bool:
    for entry in allowlist["keyEntries"]:
        if entry.get("key") == key:
            return True
    return False


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="YaoCore CHK-01..CHK-09 i18n checker")
    parser.add_argument("--root", default=".")
    parser.add_argument("--report", default="")
    parser.add_argument("--allowlist", default="")
    parser.add_argument("--strict-ui", action="store_true",
                        help="treat hardcoded UI text as blocking (default behaviour; kept for the documented command)")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    report_path = Path(args.report).resolve() if args.report else None
    allowlist_path = Path(args.allowlist).resolve() if args.allowlist else None
    allowlist = load_allowlist(allowlist_path)

    checks = []

    def add_check(check_id: str, findings, blocking: bool = True):
        status = "PASS" if not any(item["severity"] == "blocking" for item in findings) else "FAIL"
        checks.append({
            "id": check_id,
            "status": status,
            "blocking": blocking,
            "findings": findings,
        })

    try:
        raw_paths = {
            locale: root / "entry/src/main/resources/rawfile/i18n" / f"{locale}.json"
            for locale in RAW_LOCALES
        }
        string_paths = {
            folder: root / f"entry/src/main/resources/{folder}/element/string.json"
            for folder in STRING_LOCALES
        }
        for path in list(raw_paths.values()) + list(string_paths.values()):
            if not path.exists():
                raise ToolError(f"missing resource file: {path}")

        raw = {}
        for locale, path in raw_paths.items():
            flat = {}
            flatten(load_json(path), "", flat, path)
            raw[locale] = flat
        strings = {}
        for folder, path in string_paths.items():
            data = load_json(path)
            entries = data.get("string") if isinstance(data, dict) else None
            if not isinstance(entries, list):
                raise ToolError(f"string.json must contain a 'string' array: {path}")
            flat = {}
            for entry in entries:
                if not isinstance(entry, dict) or "name" not in entry or "value" not in entry:
                    raise ToolError(f"invalid string entry in {path}")
                name = entry["name"]
                if name in flat:
                    raise ToolError(f"duplicate string key {name!r} in {path}")
                flat[name] = entry["value"]
            strings[folder] = flat

        appscope_keys = set()
        appscope_path = root / "AppScope/resources/base/element/string.json"
        if appscope_path.exists():
            appscope_data = load_json(appscope_path)
            appscope_entries = appscope_data.get("string") if isinstance(appscope_data, dict) else None
            if isinstance(appscope_entries, list):
                for entry in appscope_entries:
                    if isinstance(entry, dict) and "name" in entry:
                        appscope_keys.add(entry["name"])

        source_files = read_source_files(root)

        # CHK-01 rawfile key parity, including plural variant expansion.
        findings = []
        zh_keys = set(raw["zh-CN"])
        en_keys = set(raw["en-US"])
        zh_norm = {normalize_plural(key) for key in zh_keys}
        en_norm = {normalize_plural(key) for key in en_keys}
        for key in sorted(zh_norm - en_norm):
            findings.append(finding(message="key exists in zh-CN but not en-US", key=key))
        for key in sorted(en_norm - zh_norm):
            findings.append(finding(message="key exists in en-US but not zh-CN", key=key))
        for key in sorted(zh_keys):
            if key.endswith(("_one", "_other")):
                findings.append(finding(message="zh-CN must use the base key only (no plural suffix)", key=key))
        en_variants = {}
        for key in en_keys:
            base = normalize_plural(key)
            if base != key:
                en_variants.setdefault(base, set()).add(key)
        for base, variants in sorted(en_variants.items()):
            if variants != {f"{base}_one", f"{base}_other"}:
                findings.append(finding(message="English plural key must provide both _one and _other",
                                        key=base))
        add_check("CHK-01", findings)

        # CHK-02 string.json key parity.
        findings = []
        base_keys = set(strings["base"])
        en_string_keys = set(strings["en_US"])
        for key in sorted(base_keys - en_string_keys):
            findings.append(finding(message="key exists in base but not en_US", key=key))
        for key in sorted(en_string_keys - base_keys):
            findings.append(finding(message="key exists in en_US but not base", key=key))
        add_check("CHK-02", findings)

        # CHK-03 interpolation parameter parity and parameter-name syntax.
        findings = []
        for key in sorted(zh_norm & en_norm):
            zh_value = raw["zh-CN"].get(key)
            if zh_value is None:
                continue
            zh_params = params_of(zh_value)
            for name in zh_params:
                if not PARAM_NAME_RE.match(name):
                    findings.append(finding(message=f"invalid parameter name {{{name}}}", key=key))
            for key_name, value in raw["en-US"].items():
                if normalize_plural(key_name) != key:
                    continue
                en_params = params_of(value)
                for name in en_params:
                    if not PARAM_NAME_RE.match(name):
                        findings.append(finding(message=f"invalid parameter name {{{name}}}", key=key))
                if en_params != zh_params:
                    findings.append(finding(
                        message=f"parameter sets differ: zh-CN={sorted(zh_params)} en-US={sorted(en_params)}",
                        key=key))
        add_check("CHK-03", findings)

        # CHK-04 empty/placeholder/unbalanced values.
        findings = []
        for locale, bundle in raw.items():
            for key, value in sorted(bundle.items()):
                if not value.strip():
                    findings.append(finding(message="empty value", key=key))
                if "TODO" in value or "??" in value:
                    findings.append(finding(message="placeholder value", key=key))
                if value.count("{") != value.count("}"):
                    findings.append(finding(message="unbalanced braces", key=key))
        for folder, bundle in strings.items():
            for key, value in sorted(bundle.items()):
                if not isinstance(value, str):
                    findings.append(finding(message="non-string value", key=key))
                elif not value.strip():
                    findings.append(finding(message="empty value", key=key))
        add_check("CHK-04", findings)

        # Collect source references for CHK-05/CHK-06.
        raw_references = set()
        string_references = set()
        metadata_references = set()
        for path in source_files:
            text = path.read_text(encoding="utf-8")
            raw_references.update(match[1] for match in T_CALL_RE.findall(text))
            raw_references.update(match[1] for match in TKEY_CALL_RE.findall(text))
            string_references.update(match[1] for match in R_CALL_RE.findall(text))
        for metadata_path in (root / "AppScope/app.json5", root / "entry/src/main/module.json5"):
            if metadata_path.exists():
                metadata_references.update(METADATA_RE.findall(metadata_path.read_text(encoding="utf-8")))

        # CHK-05 unused keys (warnings + review).
        findings = []
        exact_literals = set()
        prefix_literals = set()
        for path in source_files:
            text = path.read_text(encoding="utf-8")
            for literal in STRING_LITERAL_RE.findall(text):
                value = literal[1]
                if value in raw["zh-CN"] or value in raw["en-US"]:
                    exact_literals.add(value)
                if value.endswith(".") and len(value) > 1:
                    prefix_literals.add(value)
        used_raw = set(raw_references) | exact_literals
        for prefix in prefix_literals:
            used_raw.update(key for key in set(raw["zh-CN"]) | set(raw["en-US"]) if key.startswith(prefix))
        used_strings = set(string_references) | set(metadata_references)
        for key in sorted(zh_norm | en_norm):
            if key in used_raw or key_allowlisted(allowlist, key):
                continue
            if any(key.startswith(entry.get("prefix", "")) for entry in allowlist["keyPrefixes"]):
                continue
            findings.append(finding(message="rawfile key is not referenced by product code",
                                    key=key, severity="warning"))
        for key in sorted(base_keys):
            if key in used_strings or key_allowlisted(allowlist, key):
                continue
            if any(key.startswith(entry.get("prefix", "")) for entry in allowlist["keyPrefixes"]):
                continue
            findings.append(finding(message="string.json key is not referenced by product code",
                                    key=key, severity="warning"))
        add_check("CHK-05", findings, blocking=False)

        # CHK-06 undefined keys used by t()/I18nKey()/$r()/metadata.
        findings = []
        all_raw = set(raw["zh-CN"]) | set(raw["en-US"])
        for key in sorted(raw_references):
            if key.endswith("."):
                continue  # A key prefix consumed by a builder, not a complete key.
            if key not in all_raw:
                findings.append(finding(message="t()/I18nKey() references an undefined rawfile key", key=key))
        for key in sorted(string_references | metadata_references):
            if key not in base_keys and key not in appscope_keys:
                findings.append(finding(message="$r()/$string: references an undefined string.json key", key=key))
        add_check("CHK-06", findings)

        # CHK-07 hardcoded text scan.
        findings = []
        ui_roots = [root / "entry/src/main/ets/pages", root / "entry/src/main/ets/components"]
        for path in source_files:
            text = path.read_text(encoding="utf-8")
            rel = relative(root, path)
            is_ui = any(str(path).startswith(str(ui_root)) for ui_root in ui_roots)
            _clean, literals = strip_and_extract_literals(text)
            for literal, line, prefix, _raw in literals:
                if not literal or len(literal.strip()) < 2:
                    continue
                line_text = text.splitlines()[line - 1] if line - 1 < len(text.splitlines()) else ""
                stripped = line_text.lstrip()
                if stripped.startswith("import ") or stripped.startswith("export ") and " from " in line_text:
                    continue
                if literal.startswith(("app.string.", "app.color.", "app.media.")):
                    continue
                if literal.startswith(("/", "http://", "https://", "@", "./", "../")):
                    continue
                cjk = bool(CJK_RE.search(literal))
                words = ENGLISH_WORD_RE.findall(literal)
                sentence = len(words) >= 3 and bool(re.search(r"\s", literal))
                if not cjk and not sentence:
                    continue
                technical = any(token in line_text for token in
                                ("console.", "hilog.", ".debug(", ".info(", ".warn(", ".error(",
                                 "throw new ", "new AppError(", "new Error(", "super("))
                # SQL/DDL, column lists and SCREAMING_SNAKE constants are
                # technical strings, not user-visible prose (allowlist §6.4).
                if SQL_RE.search(literal):
                    technical = True
                if literal.count("_") >= 2 and any(char in literal for char in ",() "):
                    technical = True
                if literal.count("_") >= 1 and literal.isupper():
                    technical = True
                if technical and not cjk:
                    continue
                if allowlist_lookup(allowlist, rel, line):
                    continue
                severity = "blocking" if is_ui else "warning"
                findings.append(finding(file=rel, line=line,
                                        message="hardcoded CJK text" if cjk else "hardcoded English sentence",
                                        severity=severity))
        add_check("CHK-07", findings)

        # CHK-08 multi-language code forks.
        findings = []
        fork_name_re = re.compile(r"(_en|_zh|English|Chinese)", re.IGNORECASE)
        for path in source_files:
            rel = relative(root, path)
            if fork_name_re.search(path.name):
                findings.append(finding(file=rel, message="file name suggests a language-specific fork"))
            text = path.read_text(encoding="utf-8")
            if re.search(r"\bisChinese\s*\(", text) or re.search(r"\b(isEnglish|isZh|isEn)\s*\(", text):
                findings.append(finding(file=rel, message="language branch helper detected"))
        add_check("CHK-08", findings)

        # CHK-09 locale directory structure.
        findings = []
        declared_folders = set(STRING_LOCALES)
        element_root = root / "entry/src/main/resources"
        for folder in sorted(element_root.iterdir()) if element_root.exists() else []:
            if not folder.is_dir():
                continue
            string_file = folder / "element/string.json"
            if string_file.exists() and folder.name not in declared_folders:
                findings.append(finding(file=relative(root, string_file),
                                        message=f"undeclared locale resource folder {folder.name!r}"))
        raw_dir = root / "entry/src/main/resources/rawfile/i18n"
        expected_raw = {f"{locale}.json" for locale in RAW_LOCALES}
        if raw_dir.exists():
            for path in sorted(raw_dir.iterdir()):
                if path.is_file() and path.suffix == ".json" and path.name not in expected_raw:
                    findings.append(finding(file=relative(root, path),
                                            message=f"undeclared rawfile locale {path.name!r}"))
        if len(declared_folders) != len(RAW_LOCALES):
            findings.append(finding(message="string.json and rawfile locale counts differ"))
        add_check("CHK-09", findings)

    except ToolError as error:
        print(f"i18n checker tool error: {error}", file=sys.stderr)
        if report_path is not None:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps({
                "schemaVersion": 1,
                "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "root": str(root),
                "toolError": str(error),
                "checks": [],
                "summary": {"blockingFailures": 1, "warnings": 0, "missingKeys": 0, "hardcoded": 0},
                "allowlist": {"path": str(allowlist_path or ""), "entries": len(allowlist["entries"])},
            }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 2

    blocking_failures = sum(
        1 for check in checks for item in check["findings"] if item["severity"] == "blocking"
    )
    warnings = sum(1 for check in checks for item in check["findings"] if item["severity"] == "warning")
    missing_keys = sum(1 for check in checks if check["id"] in ("CHK-01", "CHK-02", "CHK-06")
                       for item in check["findings"] if "key" in item and item["severity"] == "blocking")
    hardcoded = sum(1 for check in checks if check["id"] == "CHK-07" for _ in check["findings"])

    report = {
        "schemaVersion": 1,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "root": str(root),
        "locales": RAW_LOCALES,
        "checks": checks,
        "summary": {
            "blockingFailures": blocking_failures,
            "warnings": warnings,
            "missingKeys": missing_keys,
            "hardcoded": hardcoded,
        },
        "allowlist": {
            "path": str(allowlist_path or ""),
            "entries": len(allowlist["entries"]) + len(allowlist["keyEntries"]) + len(allowlist["keyPrefixes"]),
        },
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for check in checks:
        print(f"{check['id']} {check['status']} ({len(check['findings'])} findings)")
        for item in check["findings"]:
            location = ""
            if item.get("file"):
                location = f" {item['file']}:{item.get('line', 0)}"
            key_text = f" [{item['key']}]" if item.get("key") else ""
            print(f"  - {item['severity']}:{location}{key_text} {item['message']}")
    print(f"summary: blockingFailures={blocking_failures} warnings={warnings} "
          f"missingKeys={missing_keys} hardcoded={hardcoded}")
    return 1 if blocking_failures else 0


if __name__ == "__main__":
    sys.exit(main())
