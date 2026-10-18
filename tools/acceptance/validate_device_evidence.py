#!/usr/bin/env python3
"""Validate the YaoCore device-acceptance evidence CSV.

The companion plan is ``artifacts/75-device-acceptance/device-acceptance-plan.md``
and the evidence CSV is ``artifacts/75-device-acceptance/device-evidence-template.csv``.
The defect template is ``artifacts/75-device-acceptance/defect-report-template.md``.

What is checked
---------------
* exact required columns, UTF-8 without BOM, LF line endings;
* unique ``case_id`` values and one-to-one coverage against ``### DA-xxx``
  headings in the plan;
* ``result`` in {PASS, FAIL, BLOCKED, NOT_RUN};
* ``hap_sha256`` is 64 hex characters; PASS/FAIL rows must not keep the
  all-zero template sentinel;
* ``date`` is a real ``YYYY-MM-DD`` calendar date;
* ``redaction_confirmed`` is a boolean;
* every non-NOT_RUN row has ``actual`` and non-empty ``evidence_path``;
  strict mode additionally requires the evidence path to exist and to stay
  under ``artifacts/75-device-acceptance/evidence/``;
* a conservative secret scan of free-text fields (excluding the known hash
  and revision columns) for assignment-style credentials, private-key blocks,
  bearer tokens and long hex strings.

Exit codes
----------
0  validation succeeded (or self-test passed)
1  evidence/plan validation failed
2  usage error, unreadable input, or self-test failure

Usage
-----
    python3 tools/acceptance/validate_device_evidence.py --template \
        artifacts/75-device-acceptance/device-evidence-template.csv
    python3 tools/acceptance/validate_device_evidence.py \
        artifacts/75-device-acceptance/device-evidence-template.csv
    python3 tools/acceptance/validate_device_evidence.py --self-test

This tool uses only the Python standard library.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import io
import re
import sys
import tempfile
from pathlib import Path
from typing import Iterable

REQUIRED_COLUMNS = [
    "case_id",
    "title",
    "fr_nfr",
    "build_revision",
    "hap_sha256",
    "device_model",
    "os_api",
    "firmware",
    "network",
    "result",
    "expected",
    "actual",
    "evidence_path",
    "severity",
    "owner",
    "date",
    "redaction_confirmed",
    "notes",
]

RESULT_VALUES = {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}
SEVERITY_VALUES = {"S1", "S2", "S3", "S4"}
CASE_ID_RE = re.compile(r"^DA-\d{3}$")
HASH_RE = re.compile(r"^[0-9a-fA-F]{64}$")
REVISION_RE = re.compile(r"^[0-9a-f]{7,40}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PLAN_HEADING_RE = re.compile(r"^#{2,6}\s+(DA-\d{3})\b")
ZERO_HASH = "0" * 64

# Conservative patterns. Values are never echoed back, only the pattern name.
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("password assignment", re.compile(r"\b(?:password|passwd|pwd)\s*[:=]\s*\S+", re.I)),
    ("pin/pop assignment", re.compile(r"\b(?:pop|pin)\s*[:=]\s*\S+", re.I)),
    ("hmac key assignment", re.compile(r"\bhmac[_-]?key\s*[:=]\s*\S+", re.I)),
    ("iam token assignment", re.compile(r"\biam[_-]?token\s*[:=]\s*\S+", re.I)),
    ("client secret assignment", re.compile(r"\bclient[_-]?secret\s*[:=]\s*\S+", re.I)),
    ("private key block", re.compile(r"BEGIN\s+(?:RSA\s+|EC\s+|OPENSSH\s+)?PRIVATE\s+KEY", re.I)),
    ("bearer token", re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}", re.I)),
    ("long hex string", re.compile(r"\b[0-9a-fA-F]{32,}\b")),
]

SECRET_SCAN_COLUMNS = {
    "case_id",
    "title",
    "fr_nfr",
    "device_model",
    "os_api",
    "firmware",
    "network",
    "result",
    "expected",
    "actual",
    "evidence_path",
    "severity",
    "owner",
    "date",
    "notes",
}


class EvidenceError(Exception):
    """Raised for input/IO problems that should exit with code 2."""


def _read_text(path: Path) -> str:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise EvidenceError(f"cannot read {path}: {exc}") from exc
    if raw.startswith(b"\xef\xbb\xbf"):
        raise EvidenceError(f"{path}: UTF-8 BOM is not allowed")
    if b"\r" in raw:
        raise EvidenceError(f"{path}: CRLF/CR line endings are not allowed; use LF")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise EvidenceError(f"{path}: not valid UTF-8: {exc}") from exc


def _parse_plan(plan_path: Path) -> list[tuple[str, int]]:
    text = _read_text(plan_path)
    found: list[tuple[str, int]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        match = PLAN_HEADING_RE.match(line)
        if match:
            found.append((match.group(1), lineno))
    return found


def _read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    text = _read_text(path)
    reader = csv.reader(io.StringIO(text))
    try:
        rows = list(reader)
    except csv.Error as exc:
        raise EvidenceError(f"{path}: CSV parse error: {exc}") from exc
    if not rows:
        raise EvidenceError(f"{path}: empty CSV")
    header = [cell.strip() for cell in rows[0]]
    body = rows[1:]
    return header, body


def _is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _resolve_evidence_path(cell: str, csv_path: Path) -> Path | None:
    """Resolve an evidence path from cwd or from the CSV directory."""
    if not cell:
        return None
    candidate = Path(cell)
    if candidate.is_absolute():
        return candidate
    cwd_candidate = (Path.cwd() / candidate)
    if cwd_candidate.exists():
        return cwd_candidate
    csv_candidate = (csv_path.parent / candidate)
    if csv_candidate.exists():
        return csv_candidate
    # For template mode, return a deterministic candidate even if it does not
    # exist yet, so containment can still be checked.
    if cwd_candidate.parent.exists() or csv_candidate.parent.exists():
        return cwd_candidate
    return csv_candidate


def _check_date(value: str) -> bool:
    if not DATE_RE.match(value):
        return False
    try:
        _dt.date.fromisoformat(value)
        return True
    except ValueError:
        return False


def validate(
    csv_path: Path,
    plan_path: Path | None,
    template: bool,
) -> tuple[list[str], dict[str, object]]:
    """Return (errors, stats). Raises EvidenceError for unreadable input."""
    errors: list[str] = []
    stats: dict[str, object] = {
        "rows": 0,
        "results": {},
        "plan_sections": 0,
        "template": template,
    }

    header, body = _read_csv(csv_path)
    if header != REQUIRED_COLUMNS:
        errors.append(
            "header mismatch: expected exactly "
            + ",".join(REQUIRED_COLUMNS)
            + "; got "
            + ",".join(header)
        )
        # Continue with a best-effort mapping so other errors are still useful.
        header = REQUIRED_COLUMNS if len(header) != len(REQUIRED_COLUMNS) else header

    if not body:
        errors.append("CSV has no data rows")
        return errors, stats

    seen: dict[str, int] = {}
    result_counts: dict[str, int] = {key: 0 for key in sorted(RESULT_VALUES)}
    evidence_root = csv_path.parent / "evidence"

    for index, raw_row in enumerate(body, start=2):  # line 2 is first data row
        if len(raw_row) != len(REQUIRED_COLUMNS):
            errors.append(
                f"row {index}: expected {len(REQUIRED_COLUMNS)} columns, got {len(raw_row)}"
            )
            padded = list(raw_row) + [""] * len(REQUIRED_COLUMNS)
            raw_row = padded[: len(REQUIRED_COLUMNS)]
        row = {key: (value or "").strip() for key, value in zip(REQUIRED_COLUMNS, raw_row)}
        case_id = row["case_id"]
        label = f"row {index} ({case_id or 'missing case_id'})"

        if not case_id:
            errors.append(f"{label}: case_id is empty")
        elif not CASE_ID_RE.match(case_id):
            errors.append(f"{label}: case_id must match DA-000 (three digits)")
        else:
            if case_id in seen:
                errors.append(
                    f"{label}: duplicate case_id (first at row {seen[case_id]})"
                )
            else:
                seen[case_id] = index

        for field in ("title", "fr_nfr", "expected", "owner"):
            if not row[field]:
                errors.append(f"{label}: {field} is empty")

        result = row["result"]
        if result not in RESULT_VALUES:
            errors.append(
                f"{label}: result must be one of {sorted(RESULT_VALUES)}; got {result!r}"
            )
        else:
            result_counts[result] += 1

        if not HASH_RE.match(row["hap_sha256"]):
            errors.append(f"{label}: hap_sha256 must be 64 hex characters")
        if not _check_date(row["date"]):
            errors.append(f"{label}: date must be a real YYYY-MM-DD date")

        if row["redaction_confirmed"].lower() not in {"true", "false"}:
            errors.append(f"{label}: redaction_confirmed must be true or false")

        if row["severity"] not in SEVERITY_VALUES:
            errors.append(
                f"{label}: severity must be one of {sorted(SEVERITY_VALUES)}"
            )

        if result != "NOT_RUN":
            if not row["actual"]:
                errors.append(f"{label}: non-NOT_RUN row requires actual")
            if not row["evidence_path"]:
                errors.append(f"{label}: non-NOT_RUN row requires evidence_path")
            if row["redaction_confirmed"].lower() != "true":
                errors.append(
                    f"{label}: non-NOT_RUN row requires redaction_confirmed=true"
                )
            if result in {"PASS", "FAIL"}:
                if row["hap_sha256"] == ZERO_HASH:
                    errors.append(
                        f"{label}: PASS/FAIL row must replace the all-zero hap_sha256 sentinel"
                    )
                if not REVISION_RE.match(row["build_revision"]):
                    errors.append(
                        f"{label}: PASS/FAIL row requires build_revision (7-40 lowercase hex)"
                    )
                for field in ("device_model", "os_api", "firmware", "network"):
                    if not row[field] or row[field].upper() == "TBD":
                        errors.append(
                            f"{label}: PASS/FAIL row requires real {field} (not TBD)"
                        )

            evidence = _resolve_evidence_path(row["evidence_path"], csv_path)
            if evidence is not None:
                if not _is_under(evidence, evidence_root):
                    errors.append(
                        f"{label}: evidence_path must stay under "
                        f"{evidence_root} (got {row['evidence_path']})"
                    )
                if not template and not evidence.exists():
                    errors.append(
                        f"{label}: evidence_path does not exist: {row['evidence_path']}"
                    )

        for field in SECRET_SCAN_COLUMNS:
            value = row.get(field, "")
            if not value:
                continue
            for name, pattern in SECRET_PATTERNS:
                if pattern.search(value):
                    errors.append(
                        f"{label}: possible secret in {field}: {name} "
                        "(value intentionally not printed)"
                    )
                    break

    stats["rows"] = len(body)
    stats["results"] = result_counts

    if plan_path is not None:
        if not plan_path.exists():
            errors.append(f"plan not found: {plan_path}")
        else:
            plan_sections = _parse_plan(plan_path)
            stats["plan_sections"] = len(plan_sections)
            plan_ids = [case for case, _ in plan_sections]
            plan_dupes = {case for case in plan_ids if plan_ids.count(case) > 1}
            for case in sorted(plan_dupes):
                errors.append(f"plan: duplicate case section {case}")
            plan_set = set(plan_ids)
            csv_set = set(seen)
            for case in sorted(plan_set - csv_set):
                errors.append(f"plan section {case} has no CSV row")
            for case in sorted(csv_set - plan_set):
                errors.append(f"CSV case {case} has no ### section in plan")

    return errors, stats


def _write_csv(path: Path, header: list[str], rows: Iterable[list[str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(header)
        for row in rows:
            writer.writerow(row)


def _base_row(case_id: str, result: str = "NOT_RUN", **overrides: str) -> list[str]:
    values = {
        "case_id": case_id,
        "title": f"case {case_id}",
        "fr_nfr": "FR-TEST-000",
        "build_revision": "TBD",
        "hap_sha256": ZERO_HASH,
        "device_model": "TBD",
        "os_api": "TBD",
        "firmware": "TBD",
        "network": "TBD",
        "result": result,
        "expected": "expected behavior",
        "actual": "",
        "evidence_path": f"evidence/{case_id}/",
        "severity": "S1",
        "owner": "user",
        "date": "2026-10-19",
        "redaction_confirmed": "false",
        "notes": "template row",
    }
    values.update(overrides)
    return [values[column] for column in REQUIRED_COLUMNS]


def _self_test() -> int:
    checks = 0
    failures: list[str] = []

    def run_check(name: str, errors: list[str], expect_error: bool) -> None:
        nonlocal checks
        checks += 1
        if expect_error:
            if errors:
                print(f"[PASS] {name}: rejected ({len(errors)} error(s))")
            else:
                failures.append(f"{name}: expected an error but validation passed")
                print(f"[FAIL] {name}: expected an error but validation passed")
        else:
            if not errors:
                print(f"[PASS] {name}: accepted")
            else:
                failures.append(f"{name}: unexpected error(s): {errors[:3]}")
                print(f"[FAIL] {name}: {errors[:3]}")

    with tempfile.TemporaryDirectory(prefix="yaocore-device-evidence-") as temp:
        root = Path(temp)
        plan = root / "device-acceptance-plan.md"
        plan.write_text(
            "# Plan\n\n### DA-001 first\n\n### DA-002 second\n", encoding="utf-8"
        )

        # 1. valid template
        template_csv = root / "template.csv"
        _write_csv(
            template_csv,
            REQUIRED_COLUMNS,
            [_base_row("DA-001"), _base_row("DA-002")],
        )
        errors, _ = validate(template_csv, plan, template=True)
        run_check("valid template", errors, expect_error=False)

        # 2. valid strict PASS with evidence
        strict_dir = root / "strict"
        strict_dir.mkdir()
        (strict_dir / "evidence" / "DA-001").mkdir(parents=True)
        (strict_dir / "evidence" / "DA-001" / "01.log").write_text(
            "ok\n", encoding="utf-8"
        )
        strict_csv = strict_dir / "evidence.csv"
        _write_csv(
            strict_csv,
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256="a" * 64,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="all expected observations matched",
                    evidence_path="evidence/DA-001/01.log",
                    redaction_confirmed="true",
                ),
                _base_row("DA-002"),
            ],
        )
        errors, _ = validate(strict_csv, plan, template=False)
        run_check("valid strict PASS", errors, expect_error=False)

        # 3. duplicate case id
        _write_csv(
            root / "dupe.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001"), _base_row("DA-001")],
        )
        errors, _ = validate(root / "dupe.csv", plan, template=True)
        run_check("duplicate case_id", errors, expect_error=True)

        # 4. invalid result
        _write_csv(
            root / "bad-result.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001", result="PASSED")],
        )
        errors, _ = validate(root / "bad-result.csv", plan, template=True)
        run_check("invalid result", errors, expect_error=True)

        # 5. invalid hash
        _write_csv(
            root / "bad-hash.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001", hap_sha256="abc")],
        )
        errors, _ = validate(root / "bad-hash.csv", plan, template=True)
        run_check("invalid hap_sha256", errors, expect_error=True)

        # 6. invalid date
        _write_csv(
            root / "bad-date.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001", date="2026-13-40")],
        )
        errors, _ = validate(root / "bad-date.csv", plan, template=True)
        run_check("invalid date", errors, expect_error=True)

        # 7. invalid boolean
        _write_csv(
            root / "bad-bool.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001", redaction_confirmed="yes")],
        )
        errors, _ = validate(root / "bad-bool.csv", plan, template=True)
        run_check("invalid redaction_confirmed", errors, expect_error=True)

        # 8. PASS without actual
        _write_csv(
            root / "no-actual.csv",
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256="b" * 64,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="",
                    evidence_path="evidence/DA-001/01.log",
                    redaction_confirmed="true",
                )
            ],
        )
        errors, _ = validate(root / "no-actual.csv", plan, template=True)
        run_check("PASS without actual", errors, expect_error=True)

        # 9. PASS without evidence path
        _write_csv(
            root / "no-evidence.csv",
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256="c" * 64,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="observed",
                    evidence_path="",
                    redaction_confirmed="true",
                )
            ],
        )
        errors, _ = validate(root / "no-evidence.csv", plan, template=True)
        run_check("PASS without evidence path", errors, expect_error=True)

        # 10. strict PASS with missing path
        missing_dir = root / "missing"
        missing_dir.mkdir()
        missing_csv = missing_dir / "evidence.csv"
        _write_csv(
            missing_csv,
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256="d" * 64,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="observed",
                    evidence_path="evidence/DA-001/01.log",
                    redaction_confirmed="true",
                )
            ],
        )
        errors, _ = validate(missing_csv, root / "device-acceptance-plan.md", template=False)
        run_check("strict missing evidence", errors, expect_error=True)

        # 11. strict PASS with zero hash
        zero_dir = root / "zero"
        zero_dir.mkdir()
        (zero_dir / "evidence" / "DA-001").mkdir(parents=True)
        (zero_dir / "evidence" / "DA-001" / "01.log").write_text("ok\n")
        zero_csv = zero_dir / "evidence.csv"
        _write_csv(
            zero_csv,
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256=ZERO_HASH,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="observed",
                    evidence_path="evidence/DA-001/01.log",
                    redaction_confirmed="true",
                )
            ],
        )
        errors, _ = validate(zero_csv, plan, template=False)
        run_check("PASS with zero hash", errors, expect_error=True)

        # 12. secret assignment in notes (constructed to avoid a literal in this file)
        secret_value = "pass" + "word=" + "hunter2"
        _write_csv(
            root / "secret.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001", notes=secret_value)],
        )
        errors, _ = validate(root / "secret.csv", plan, template=True)
        run_check("secret assignment", errors, expect_error=True)

        # 13. long hex secret in actual
        long_hex = "ab" * 20
        _write_csv(
            root / "long-hex.csv",
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="FAIL",
                    actual=f"leaked {long_hex}",
                    redaction_confirmed="true",
                )
            ],
        )
        errors, _ = validate(root / "long-hex.csv", plan, template=True)
        run_check("long hex secret", errors, expect_error=True)

        # 14. missing column
        short_header = [column for column in REQUIRED_COLUMNS if column != "notes"]
        short_row = [value for column, value in zip(REQUIRED_COLUMNS, _base_row("DA-001")) if column != "notes"]
        _write_csv(root / "missing-column.csv", short_header, [short_row])
        errors, _ = validate(root / "missing-column.csv", plan, template=True)
        run_check("missing column", errors, expect_error=True)

        # 15. plan mismatch
        _write_csv(
            root / "plan-mismatch.csv",
            REQUIRED_COLUMNS,
            [_base_row("DA-001"), _base_row("DA-003")],
        )
        errors, _ = validate(root / "plan-mismatch.csv", plan, template=True)
        run_check("plan mismatch", errors, expect_error=True)

        # 16. CRLF rejection
        crlf = root / "crlf.csv"
        crlf.write_bytes(
            ("\r\n".join([",".join(REQUIRED_COLUMNS), ",".join(_base_row("DA-001"))]) + "\r\n").encode(
                "utf-8"
            )
        )
        try:
            validate(crlf, plan, template=True)
            run_check("CRLF rejection", [], expect_error=True)
        except EvidenceError:
            run_check("CRLF rejection", ["crlf"], expect_error=True)

        # 17. template mode allows a non-existent evidence path for PASS
        template_pass_csv = root / "template-pass.csv"
        _write_csv(
            template_pass_csv,
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="PASS",
                    build_revision="938867e",
                    hap_sha256="e" * 64,
                    device_model="Test Device",
                    os_api="API 26",
                    firmware="v2.1",
                    network="2.4GHz LAN",
                    actual="observed",
                    evidence_path="evidence/DA-001/not-created-yet.log",
                    redaction_confirmed="true",
                ),
                _base_row("DA-002"),
            ],
        )
        errors, _ = validate(template_pass_csv, plan, template=True)
        run_check("template skips path existence", errors, expect_error=False)

        # 18. BLOCKED may keep the zero hash and TBD environment
        _write_csv(
            root / "blocked.csv",
            REQUIRED_COLUMNS,
            [
                _base_row(
                    "DA-001",
                    result="BLOCKED",
                    actual="no signed HAP / no hdc target",
                    evidence_path="evidence/DA-001/",
                    redaction_confirmed="true",
                    notes="blocked reason recorded",
                ),
                _base_row("DA-002"),
            ],
        )
        errors, _ = validate(root / "blocked.csv", plan, template=True)
        run_check("blocked row accepted", errors, expect_error=False)

    if failures:
        print("\nSELF-TEST FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 2
    print(f"\nSELF-TEST: {checks} checks passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate YaoCore device-acceptance evidence CSV and plan coverage.",
        epilog="Exit codes: 0 ok, 1 validation failed, 2 usage/IO/self-test error.",
    )
    parser.add_argument("csv_path", nargs="?", help="evidence CSV to validate")
    parser.add_argument(
        "--template",
        action="store_true",
        help="template mode: allow NOT_RUN rows without actual/evidence and skip evidence existence",
    )
    parser.add_argument(
        "--plan",
        type=Path,
        default=None,
        help="plan markdown (default: device-acceptance-plan.md next to the CSV)",
    )
    parser.add_argument(
        "--no-plan",
        action="store_true",
        help="skip one-to-one plan section coverage",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run built-in positive/negative checks in a temporary directory",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return _self_test()

    if not args.csv_path:
        parser.error("csv_path is required unless --self-test is used")

    csv_path = Path(args.csv_path)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 2

    plan_path = None
    if not args.no_plan:
        plan_path = args.plan if args.plan is not None else csv_path.parent / "device-acceptance-plan.md"

    try:
        errors, stats = validate(csv_path, plan_path, template=args.template)
    except EvidenceError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    mode = "template" if args.template else "strict"
    if errors:
        print(f"validate_device_evidence: FAILED mode={mode} errors={len(errors)}")
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    results = stats.get("results", {})
    print(f"validate_device_evidence: OK mode={mode}")
    print(f"  csv: {csv_path}")
    print(f"  rows: {stats.get('rows')}")
    print(f"  results: {results}")
    if plan_path is not None:
        print(f"  plan: {plan_path}")
        print(f"  plan_sections: {stats.get('plan_sections')}")
    print("  secret_scan: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
