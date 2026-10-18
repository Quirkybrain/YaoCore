#!/usr/bin/env python3
"""Evidence-based triage of the 615-row legacy i18n register.

Producer: agent:implementation-engineer | Task: wp-096-i18n-triage
Inputs:
  entry/src/test/i18n/legacy-migration.csv
  entry/src/main/resources/rawfile/i18n/{zh-CN,en-US}.json
  entry/src/main/resources/base/element/string.json
  entry/src/main/resources/en_US/element/string.json (B evidence only)
  entry/src/main/ets/** and entry/src/main/resources/** (source references)

Status semantics:
  ACCEPTED          Human-reviewed row (T-10 only). Never produced by this tool.
  MIGRATED          The trimmed legacy Chinese value occurs exactly once in the
                    current zh-CN locale stores. The target key is machine
                    evidence, not human sign-off.
  PENDING_REVIEW    The value occurs under multiple current keys. A human must
                    choose the semantically correct key.
  INLINE_LITERAL    No locale key, but the literal still occurs in current
                    source/resources. It must be extracted to a semantic key.
  OBSOLETE_LEGACY   No exact current locale/source reference. This is not proof
                    of business obsolescence: T-18 rewrote many legacy texts
                    non-verbatim. T-17/T-18 must confirm before archival.

Usage:
  python3 tools/i18n/triage_legacy.py --write
  python3 tools/i18n/triage_legacy.py --check
  python3 tools/i18n/triage_legacy.py --summary

Exit codes:
  0  success / check matched
  1  --check found CSV drift or an invariant violation
  2  tool/input error
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

EXPECTED_COLUMNS = [
    "旧中文",
    "旧英文",
    "分类",
    "目标存储",
    "目标键",
    "审查结论",
    "负责人",
    "批次",
    "备注",
    "重译审查",
    "复核标记",
]

STATUS_ACCEPTED = "ACCEPTED"
STATUS_MIGRATED = "MIGRATED"
STATUS_PENDING = "PENDING_REVIEW"
STATUS_INLINE = "INLINE_LITERAL"
STATUS_OBSOLETE = "OBSOLETE_LEGACY"
STATUS_DEPRECATED = "DEPRECATED (heuristic)"
STATUS_EXCLUDED = "EXCLUDED (brand data)"

A_STATUSES = {
    STATUS_ACCEPTED,
    STATUS_MIGRATED,
    STATUS_PENDING,
    STATUS_INLINE,
    STATUS_OBSOLETE,
}
C_STATUSES = {STATUS_DEPRECATED}
D_STATUSES = {STATUS_EXCLUDED}
C_RECHECK_FLAGS = {"RECHECK_REQUIRED", "SAFETY_RECHECK_REQUIRED"}

# Human-reviewed baseline from T-10. ACCEPTED is intentionally closed: this
# triage tool must not promote any other row. If a later human review adds a
# row, update this baseline in the same change as the review evidence.
EXPECTED_ACCEPTED = {
    "Wi-Fi 认证失败，请检查密码",
    "保存失败，请重试",
    "编辑",
    "查看",
    "成功",
    "删除",
    "设备离线",
    "失败",
    "取消",
    "刷新失败，请重试",
}

# Pre-identified legacy machine/file translations from T-10/T-18. The triage
# tool keeps this sub-review state and adds current-English evidence; it does
# not silently clear or expand the set.
EXPECTED_B_REWRITE = {
    "本机安全档案保存失败",
    "本机档案已解锁",
    "本机使用档案",
    "本机使用档案锁定失败",
    "本机使用档案已锁定",
    "本机已有使用档案，请直接解锁",
    "创建本机档案",
    "档案已创建，但解锁状态未保存，请重新解锁",
    "该档案仅保存在本机，不是云端账号，不提供家庭成员身份或设备控制授权。",
    "解锁本机档案",
    "锁定本机档案",
}

RAW_ZH = "entry/src/main/resources/rawfile/i18n/zh-CN.json"
RAW_EN = "entry/src/main/resources/rawfile/i18n/en-US.json"
STRING_BASE = "entry/src/main/resources/base/element/string.json"
STRING_EN = "entry/src/main/resources/en_US/element/string.json"
SOURCE_ROOT = "entry/src/main/ets"
RESOURCE_ROOT = "entry/src/main/resources"

MACHINE_FILE_RE = re.compile(r"\b(machines?|files?)\b", re.IGNORECASE)
JS_SOURCE_SUFFIXES = {".ets", ".ts"}
RESOURCE_TEXT_SUFFIXES = {
    ".json",
    ".json5",
    ".xml",
    ".txt",
    ".md",
    ".html",
    ".properties",
    ".yaml",
    ".yml",
    ".ets",
    ".ts",
}


class ToolError(Exception):
    pass


@dataclass(frozen=True)
class Match:
    storage: str
    key: str
    file: str


@dataclass
class TriageResult:
    row: dict
    status: str
    candidates: list[Match] = field(default_factory=list)
    refs: list[str] = field(default_factory=list)
    b_terms: list[str] = field(default_factory=list)
    en_evidence: str = ""


def repo_root_default() -> Path:
    # tools/i18n/triage_legacy.py -> repository root
    return Path(__file__).resolve().parents[2]


def reject_duplicate_pairs(path: Path):
    def hook(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ToolError(f"duplicate key {key!r} in {path}")
            result[key] = value
        return result

    return hook


def load_json(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ToolError(f"cannot read {path}: {error}") from error
    try:
        return json.loads(text, object_pairs_hook=reject_duplicate_pairs(path))
    except json.JSONDecodeError as error:
        raise ToolError(f"invalid JSON in {path}: {error}") from error


def flatten_string_leaves(node, prefix: str, out: list[tuple[str, str]]):
    """Flatten dict/list/string trees into (dot-path, string) leaves.

    rawfile locale files are nested objects; element/string.json values are
    normally strings but this also handles future plural/array values without
    silently dropping them.
    """
    if isinstance(node, dict):
        if not node:
            raise ToolError(f"empty object at {prefix or '<root>'}")
        for key, value in node.items():
            flatten_string_leaves(value, f"{prefix}.{key}" if prefix else str(key), out)
        return
    if isinstance(node, list):
        for index, value in enumerate(node):
            flatten_string_leaves(value, f"{prefix}[{index}]", out)
        return
    if isinstance(node, str):
        out.append((prefix, node))
        return
    raise ToolError(f"non-string leaf {prefix!r} (type {type(node).__name__})")


def load_raw_locale(path: Path, storage: str, root: Path):
    data = load_json(path)
    if not isinstance(data, dict):
        raise ToolError(f"raw locale must be a JSON object: {path}")
    leaves: list[tuple[str, str]] = []
    flatten_string_leaves(data, "", leaves)
    rel = relative(root, path)
    return [(storage, key, value, rel) for key, value in leaves]


def load_element_strings(path: Path, storage: str, root: Path):
    data = load_json(path)
    entries = data.get("string") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        raise ToolError(f"element string file must contain a 'string' array: {path}")
    rel = relative(root, path)
    out: list[tuple[str, str, str, str]] = []
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or "name" not in entry or "value" not in entry:
            raise ToolError(f"invalid string entry in {path}")
        name = str(entry["name"])
        if name in seen:
            raise ToolError(f"duplicate string key {name!r} in {path}")
        seen.add(name)
        leaves: list[tuple[str, str]] = []
        flatten_string_leaves(entry["value"], name, leaves)
        for key, value in leaves:
            out.append((storage, key, value, rel))
    return out


def relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def build_value_index(entries):
    index: dict[str, list[Match]] = defaultdict(list)
    for storage, key, value, file in entries:
        if not value.strip():
            continue
        index[value.strip()].append(Match(storage=storage, key=key, file=file))
    for matches in index.values():
        matches.sort(key=lambda item: (item.storage, item.key, item.file))
    return index


def build_key_index(entries):
    index: dict[str, list[str]] = defaultdict(list)
    for _storage, key, value, _file in entries:
        index[key].append(value)
    return index


def line_of(text: str, position: int) -> int:
    return text.count("\n", 0, position) + 1


def decode_js_escape(raw: str) -> str:
    result = []
    index = 0
    length = len(raw)
    simple = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "b": "\b",
        "f": "\f",
        "v": "\v",
        "0": "\0",
        "'": "'",
        '"': '"',
        "`": "`",
        "\\": "\\",
    }
    while index < length:
        char = raw[index]
        if char != "\\" or index + 1 >= length:
            result.append(char)
            index += 1
            continue
        nxt = raw[index + 1]
        if nxt in simple:
            result.append(simple[nxt])
            index += 2
            continue
        if nxt == "u" and re.match(r"^[0-9a-fA-F]{4}$", raw[index + 2:index + 6]):
            result.append(chr(int(raw[index + 2:index + 6], 16)))
            index += 6
            continue
        if nxt == "x" and re.match(r"^[0-9a-fA-F]{2}$", raw[index + 2:index + 4]):
            result.append(chr(int(raw[index + 2:index + 4], 16)))
            index += 4
            continue
        result.append(nxt)
        index += 2
    return "".join(result)


def extract_js_literals(text: str):
    """Return [(decoded literal, line)] while ignoring // and /* */ comments."""
    literals: list[tuple[str, int]] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        nxt = text[index + 1] if index + 1 < length else ""
        if char == "/" and nxt == "/":
            while index < length and text[index] != "\n":
                index += 1
            continue
        if char == "/" and nxt == "*":
            index += 2
            while index + 1 < length and not (text[index] == "*" and text[index + 1] == "/"):
                index += 1
            index = min(index + 2, length)
            continue
        if char in ("'", '"', "`"):
            quote = char
            start = index
            index += 1
            raw = []
            while index < length:
                current = text[index]
                if current == "\\" and index + 1 < length:
                    raw.append(current)
                    raw.append(text[index + 1])
                    index += 2
                    continue
                if current == quote:
                    index += 1
                    break
                raw.append(current)
                index += 1
            literals.append((decode_js_escape("".join(raw)), line_of(text, start)))
            continue
        index += 1
    return literals


def extract_quoted_literals(text: str):
    literals: list[tuple[str, int]] = []
    pattern = re.compile(r"(['\"])((?:\\.|(?!\1).)*)\1")
    for match in pattern.finditer(text):
        literals.append((decode_js_escape(match.group(2)), line_of(text, match.start())))
    return literals


def build_source_reference_index(root: Path):
    index: dict[str, list[str]] = defaultdict(list)
    source_root = root / SOURCE_ROOT
    if not source_root.exists():
        raise ToolError(f"missing source root: {source_root}")
    for path in sorted(source_root.rglob("*")):
        if not path.is_file() or path.suffix not in JS_SOURCE_SUFFIXES:
            continue
        rel = relative(root, path)
        text = path.read_text(encoding="utf-8")
        for literal, line in extract_js_literals(text):
            value = literal.strip()
            if value:
                index[value].append(f"{rel}:{line}")
    return index


def build_resource_reference_index(root: Path):
    index: dict[str, list[str]] = defaultdict(list)
    resource_root = root / RESOURCE_ROOT
    if not resource_root.exists():
        raise ToolError(f"missing resource root: {resource_root}")
    for path in sorted(resource_root.rglob("*")):
        if not path.is_file() or path.suffix not in RESOURCE_TEXT_SUFFIXES:
            continue
        rel = relative(root, path)
        if path.suffix in (".json", ".json5"):
            try:
                data = load_json(path)
                leaves: list[tuple[str, str]] = []
                flatten_string_leaves(data, "", leaves)
                for key, value in leaves:
                    value = value.strip()
                    if value:
                        index[value].append(f"{rel}#{key}")
                continue
            except ToolError:
                # JSON5/commented fixtures: fall back to quoted literals.
                pass
        text = path.read_text(encoding="utf-8")
        for literal, line in extract_quoted_literals(text):
            value = literal.strip()
            if value:
                index[value].append(f"{rel}:{line}")
    return index


def load_csv(path: Path):
    try:
        handle = path.open(encoding="utf-8", newline="")
    except OSError as error:
        raise ToolError(f"cannot read {path}: {error}") from error
    with handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != EXPECTED_COLUMNS:
            raise ToolError(
                f"unexpected columns in {path}: {reader.fieldnames!r}; "
                f"expected {EXPECTED_COLUMNS!r}"
            )
        rows = []
        for line_number, row in enumerate(reader, start=2):
            if None in row:
                raise ToolError(f"extra CSV fields at line {line_number}")
            for column in EXPECTED_COLUMNS:
                if row.get(column) is None:
                    raise ToolError(f"missing column {column!r} at line {line_number}")
            rows.append(row)
    if not rows:
        raise ToolError(f"empty CSV: {path}")
    return rows


def write_csv(path: Path, rows):
    before = [(row["旧中文"], row["旧英文"]) for row in rows]
    temp_path = path.with_name(path.name + ".tmp")
    with temp_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=EXPECTED_COLUMNS,
            lineterminator="\n",
            quoting=csv.QUOTE_MINIMAL,
        )
        writer.writeheader()
        writer.writerows(rows)
    # Re-read and prove that the legacy source text was not altered.
    rewritten = load_csv(temp_path)
    after = [(row["旧中文"], row["旧英文"]) for row in rewritten]
    if before != after:
        temp_path.unlink(missing_ok=True)
        raise ToolError("refusing to write: legacy Chinese/English text changed")
    os.replace(temp_path, path)


def machine_terms(value: str):
    return sorted({match.lower() for match in MACHINE_FILE_RE.findall(value)})


def en_values_for_key(en_key_index, key: str):
    values = []
    for candidate in (key, f"{key}_one", f"{key}_other"):
        values.extend(en_key_index.get(candidate, []))
    return values


def b_rewrite_evidence(row, matches, en_entries):
    terms = machine_terms(row["旧英文"])
    if not terms:
        return [], "legacy English contains no machine/file term"
    en_key_index = build_key_index(en_entries)
    if len(matches) == 1:
        key = matches[0].key
        current_values = en_values_for_key(en_key_index, key)
        if not current_values:
            evidence = (
                f"current en-US has no value for {key}; "
                "legacy English must still be rewritten"
            )
        else:
            current_terms = sorted({term for value in current_values for term in machine_terms(value)})
            if current_terms:
                evidence = (
                    f"current en-US at {key} still contains {', '.join(current_terms)}; "
                    "rewrite required"
                )
            else:
                evidence = (
                    f"current en-US at {key} contains no machine/file term "
                    "(profile terminology used); rewrite legacy English if reused"
                )
        return terms, evidence
    if len(matches) > 1:
        return terms, "multiple current keys; current en-US terminology is not determined"
    global_hits = sum(
        1 for _storage, _key, value, _file in en_entries if machine_terms(value)
    )
    return terms, (
        f"no matched current key; current en-US locale has {global_hits} "
        "machine/file(s) occurrence(s) (profile terminology used)"
    )


def triage_rows(rows, zh_index, source_index, resource_index, en_entries):
    results: list[TriageResult] = []
    for row in rows:
        computed = dict(row)
        category = row["分类"].strip()
        status = row["审查结论"].strip()
        result = TriageResult(row=computed, status=status)
        if category.startswith("D"):
            computed["审查结论"] = STATUS_EXCLUDED
            if not computed["目标存储"].strip():
                computed["目标存储"] = ""
            if not computed["目标键"].strip():
                computed["目标键"] = ""
            if not computed["备注"].strip():
                raise ToolError("D row has an empty remark")
            result.status = STATUS_EXCLUDED
            results.append(result)
            continue
        if category.startswith("C"):
            computed["审查结论"] = STATUS_DEPRECATED
            if computed["复核标记"].strip() not in C_RECHECK_FLAGS:
                computed["复核标记"] = "RECHECK_REQUIRED"
            if not computed["备注"].strip():
                raise ToolError("C row has an empty remark")
            result.status = STATUS_DEPRECATED
            results.append(result)
            continue
        if not category.startswith("A"):
            raise ToolError(f"unknown category {category!r} for {row['旧中文']!r}")
        if status == STATUS_ACCEPTED:
            # Human-owned row. The triage tool never recomputes or upgrades it.
            result.status = STATUS_ACCEPTED
            results.append(result)
            continue
        legacy = row["旧中文"].strip()
        if not legacy:
            raise ToolError("A row has an empty legacy Chinese value")
        matches = list(zh_index.get(legacy, []))
        result.candidates = matches
        if len(matches) == 1:
            match = matches[0]
            status = STATUS_MIGRATED
            computed["审查结论"] = STATUS_MIGRATED
            computed["目标存储"] = match.storage
            computed["目标键"] = match.key
            base = f"zh value match: {match.key} @ {match.file}"
        elif len(matches) > 1:
            status = STATUS_PENDING
            computed["审查结论"] = STATUS_PENDING
            computed["目标键"] = ""
            candidates = "; ".join(
                f"{match.key} @ {match.file}" for match in matches
            )
            base = (
                f"zh value match ambiguous: {len(matches)} candidates: {candidates}; "
                "semantic choice required"
            )
        else:
            refs = list(source_index.get(legacy, []))
            if not refs:
                refs = list(resource_index.get(legacy, []))
            if refs:
                status = STATUS_INLINE
                computed["审查结论"] = STATUS_INLINE
                computed["目标键"] = ""
                shown = refs[:10]
                ref_text = "; ".join(shown)
                if len(refs) > len(shown):
                    ref_text += f"; ... (+{len(refs) - len(shown)} more)"
                base = f"source literal reference: {ref_text}; extraction required"
                result.refs = refs
            else:
                status = STATUS_OBSOLETE
                computed["审查结论"] = STATUS_OBSOLETE
                computed["目标键"] = ""
                base = (
                    "no current locale/source reference (scanned "
                    "entry/src/main/ets/** and entry/src/main/resources/**); "
                    "not proof of business obsolescence (T-18 non-verbatim "
                    "rewrites possible); T-17/T-18 semantic confirmation required "
                    "before archival"
                )
        if row["重译审查"].strip() == "B_REWRITE_REQUIRED":
            terms, evidence = b_rewrite_evidence(row, matches, en_entries)
            result.b_terms = terms
            result.en_evidence = evidence
            base += (
                "; B_REWRITE_REQUIRED: legacy English contains "
                f"{', '.join(terms) if terms else 'no machine/file term'}; "
                f"{evidence}"
            )
        computed["备注"] = base
        result.status = status
        results.append(result)
    return results


def validate(rows, results):
    errors: list[str] = []
    if len(rows) != 615:
        errors.append(f"expected 615 rows, found {len(rows)}")
    if len(results) != len(rows):
        errors.append("internal error: result count differs from row count")
    accepted = 0
    accepted_legacy = set()
    b_legacy = set()
    for line_number, (row, result) in enumerate(zip(rows, results), start=2):
        computed = result.row
        category = computed["分类"].strip()
        status = computed["审查结论"].strip()
        legacy = computed["旧中文"].strip()
        if not status:
            errors.append(f"line {line_number}: empty 审查结论")
        if not computed["备注"].strip():
            errors.append(f"line {line_number}: empty 备注")
        if category.startswith("A"):
            if status not in A_STATUSES:
                errors.append(f"line {line_number}: illegal A status {status!r}")
            if status == STATUS_ACCEPTED:
                accepted += 1
                accepted_legacy.add(legacy)
                if row["负责人"].strip() != "T-10" or row["批次"].strip() != "T-10":
                    errors.append(
                        f"line {line_number}: ACCEPTED is reserved for T-10 human review"
                    )
                if row["重译审查"].strip() != "B_REVIEWED_ACCEPTED":
                    errors.append(
                        f"line {line_number}: ACCEPTED row must keep "
                        "B_REVIEWED_ACCEPTED"
                    )
                if not computed["目标存储"].strip() or not computed["目标键"].strip():
                    errors.append(f"line {line_number}: ACCEPTED row needs 目标存储/目标键")
            elif status == STATUS_MIGRATED:
                if not computed["目标存储"].strip() or not computed["目标键"].strip():
                    errors.append(
                        f"line {line_number}: MIGRATED row needs 目标存储/目标键"
                    )
            elif computed["目标键"].strip():
                errors.append(
                    f"line {line_number}: non-MIGRATED A row must not keep a target key"
                )
        elif category.startswith("C"):
            if status not in C_STATUSES:
                errors.append(f"line {line_number}: illegal C status {status!r}")
            if computed["复核标记"].strip() not in C_RECHECK_FLAGS:
                errors.append(
                    f"line {line_number}: C row must keep a recheck flag"
                )
            if computed["目标存储"].strip() or computed["目标键"].strip():
                errors.append(
                    f"line {line_number}: C row must not carry a target store/key"
                )
            if computed["重译审查"].strip() != "NOT_APPLICABLE":
                errors.append(
                    f"line {line_number}: C row must keep 重译审查=NOT_APPLICABLE"
                )
        elif category.startswith("D"):
            if status not in D_STATUSES:
                errors.append(f"line {line_number}: illegal D status {status!r}")
            if computed["目标存储"].strip() or computed["目标键"].strip():
                errors.append(
                    f"line {line_number}: D row must not carry a target store/key"
                )
            if computed["重译审查"].strip() != "NOT_APPLICABLE":
                errors.append(
                    f"line {line_number}: D row must keep 重译审查=NOT_APPLICABLE"
                )
        else:
            errors.append(f"line {line_number}: unknown category {category!r}")
        if computed["重译审查"].strip() == "B_REWRITE_REQUIRED":
            b_legacy.add(legacy)
            if "B_REWRITE_REQUIRED" not in computed["备注"]:
                errors.append(
                    f"line {line_number}: B row remark lost B_REWRITE_REQUIRED evidence"
                )
            if not machine_terms(computed["备注"]):
                errors.append(
                    f"line {line_number}: B row remark lost machine/file evidence"
                )
        elif legacy in EXPECTED_B_REWRITE:
            errors.append(
                f"line {line_number}: {legacy!r} must keep "
                "重译审查=B_REWRITE_REQUIRED"
            )
    if accepted != 10:
        errors.append(
            f"ACCEPTED count must remain 10 (T-10); found {accepted}"
        )
    if accepted_legacy != EXPECTED_ACCEPTED:
        errors.append(
            "ACCEPTED set differs from the T-10 baseline: "
            f"missing={sorted(EXPECTED_ACCEPTED - accepted_legacy)!r} "
            f"extra={sorted(accepted_legacy - EXPECTED_ACCEPTED)!r}"
        )
    if b_legacy != EXPECTED_B_REWRITE:
        errors.append(
            "B_REWRITE_REQUIRED set differs from the T-10/T-18 baseline: "
            f"missing={sorted(EXPECTED_B_REWRITE - b_legacy)!r} "
            f"extra={sorted(b_legacy - EXPECTED_B_REWRITE)!r}"
        )
    return errors


def compare(rows, results):
    differences: list[str] = []
    owned_fields = {"审查结论", "目标键", "备注"}
    for line_number, (row, result) in enumerate(zip(rows, results), start=2):
        computed = result.row
        fields = set(owned_fields)
        if computed["审查结论"] == STATUS_MIGRATED:
            fields.add("目标存储")
        if computed["分类"].strip().startswith("C"):
            fields.add("复核标记")
        for field in sorted(fields):
            if row[field] != computed[field]:
                differences.append(
                    f"row {line_number} [{field}]: "
                    f"csv={row[field]!r} computed={computed[field]!r}"
                )
    return differences


def print_summary(results):
    status_counts = Counter(result.status for result in results)
    category_counts = Counter(result.row["分类"] for result in results)
    print("i18n legacy triage summary")
    print(f"rows: {len(results)}")
    print("by category:")
    for category in sorted(category_counts):
        print(f"  {category}: {category_counts[category]}")
    print("by status:")
    for status in (
        STATUS_ACCEPTED,
        STATUS_MIGRATED,
        STATUS_PENDING,
        STATUS_INLINE,
        STATUS_OBSOLETE,
        STATUS_DEPRECATED,
        STATUS_EXCLUDED,
    ):
        print(f"  {status}: {status_counts.get(status, 0)}")
    print("pending_review:")
    pending = [result for result in results if result.status == STATUS_PENDING]
    if not pending:
        print("  (none)")
    for result in pending:
        candidates = "; ".join(
            f"{match.key} @ {match.file}" for match in result.candidates
        )
        print(
            f"  - {result.row['旧中文']!r} | {result.row['旧英文']!r} | "
            f"candidates: {candidates}"
        )
    print("inline_literal:")
    inline = [result for result in results if result.status == STATUS_INLINE]
    if not inline:
        print("  (none)")
    for result in inline:
        print(
            f"  - {result.row['旧中文']!r} | refs: "
            f"{'; '.join(result.refs)}"
        )
    print("b_rewrite_required:")
    b_rows = [
        result
        for result in results
        if result.row["重译审查"].strip() == "B_REWRITE_REQUIRED"
    ]
    if not b_rows:
        print("  (none)")
    for result in b_rows:
        print(
            f"  - {result.row['旧中文']!r} | status={result.status} | "
            f"{result.en_evidence}"
        )
    print("c_recheck:")
    for result in results:
        if result.row["分类"].strip().startswith("C"):
            print(
                f"  - {result.row['旧中文']!r} | "
                f"{result.row['复核标记']}"
            )
    print("d_excluded:")
    for result in results:
        if result.row["分类"].strip().startswith("D"):
            print(f"  - {result.row['旧中文']!r}")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Evidence-based triage of the 615-row legacy i18n register"
    )
    parser.add_argument("--root", default="", help="repository root (default: discovered)")
    parser.add_argument(
        "--csv",
        default="entry/src/test/i18n/legacy-migration.csv",
        help="register path relative to --root",
    )
    parser.add_argument("--write", action="store_true", help="write the triaged CSV in place")
    parser.add_argument("--check", action="store_true", help="read-only recompute and compare")
    parser.add_argument("--summary", action="store_true", help="read-only counts and residual details")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root_default()
    csv_path = (root / args.csv).resolve()

    try:
        rows = load_csv(csv_path)
        raw_zh = load_raw_locale(root / RAW_ZH, "rawfile/i18n", root)
        raw_en = load_raw_locale(root / RAW_EN, "rawfile/i18n", root)
        string_zh = load_element_strings(root / STRING_BASE, "string.json", root)
        string_en = load_element_strings(root / STRING_EN, "string.json", root)
        zh_index = build_value_index(raw_zh + string_zh)
        en_entries = raw_en + string_en
        source_index = build_source_reference_index(root)
        resource_index = build_resource_reference_index(root)
        results = triage_rows(rows, zh_index, source_index, resource_index, en_entries)
        errors = validate(rows, results)
        differences = compare(rows, results)
    except ToolError as error:
        print(f"i18n triage tool error: {error}", file=sys.stderr)
        return 2

    if args.summary:
        print_summary(results)
        if differences:
            print(f"csv_status: STALE ({len(differences)} difference(s))")
        else:
            print("csv_status: UP_TO_DATE")
        if errors:
            for error in errors:
                print(f"INVARIANT: {error}")
            return 1
        return 0

    if args.check:
        print(f"i18n legacy triage check: {len(rows)} rows")
        for difference in differences:
            print(f"DIFF {difference}")
        for error in errors:
            print(f"INVARIANT {error}")
        if differences or errors:
            print(
                f"FAIL: {len(differences)} difference(s), {len(errors)} invariant error(s)"
            )
            return 1
        print("OK: CSV matches computed triage; invariants pass")
        return 0

    if errors:
        for error in errors:
            print(f"INVARIANT {error}", file=sys.stderr)
        print("refusing to write with invariant errors", file=sys.stderr)
        return 2

    write_csv(csv_path, [result.row for result in results])
    print(f"updated: {relative(root, csv_path)} ({len(results)} rows)")
    print_summary(results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
