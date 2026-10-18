"""Fixture self-test for tools/contract/check_layering.py (C-29 / T-20).

Producer: agent:test-engineer | Updated: agent:implementation-engineer / Task: T-23 / wp-090-ports
Contract: DES-B §18.1 (checker must have legal/illegal fixture self-tests and
          enforce exception status/symbols); DES-B §2.3 D-01..D-17;
          DES-A §27.6 port_location_exceptions; T-20 review F-01/F-02/F-06.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
CHECKER = HERE / "check_layering.py"
GOOD = HERE / "fixtures/layering/good"
BAD = HERE / "fixtures/layering/bad"
PORTS = HERE / "fixtures/layering/port-exceptions"
PENDING_D12 = HERE / "fixtures/layering/pending-d12"
POST_MIGRATION = HERE / "fixtures/layering/post-migration"
POST_MIGRATION_BAD = HERE / "fixtures/layering/post-migration-bad"


def run(root: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--root", str(root), *extra],
        text=True,
        capture_output=True,
        check=False,
    )


def run_port(name: str, *extra: str) -> subprocess.CompletedProcess[str]:
    root = PORTS / name
    return run(root, "--allowlist", str(root / "allowlist.json"), *extra)


class CheckLayeringFixtureTests(unittest.TestCase):
    def test_legal_fixture_passes(self) -> None:
        result = run(GOOD)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("check_layering: PASS", result.stdout)
        self.assertIn("violations=0", result.stdout)

    def test_illegal_fixture_fails_with_every_rule_class(self) -> None:
        result = run(BAD)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("check_layering: FAIL", result.stdout)
        for rule in ("D-01", "D-02", "D-03", "D-05", "D-06", "D-08", "D-09",
                     "D-11", "D-12", "D-13", "D-17"):
            self.assertIn(rule, result.stdout, f"missing fixture coverage for {rule}")

    def test_repository_tree_passes_with_versioned_exceptions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "layering.json"
            result = run(REPO_ROOT, "--report", str(report))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["violation_count"], 0)
            self.assertEqual(payload["exceptions_used_count"], 6)
            self.assertTrue(all(item["status"] == "accepted"
                                for item in payload["exceptions"]),
                            "T-20 D-12 entries must all be accepted")
            self.assertEqual(payload["pending_exceptions"], [])
            self.assertEqual(payload["port_pending_exceptions"], [])
            self.assertIn("pending=0", result.stdout)
            self.assertIn("port_exceptions_used=0", result.stdout)
            self.assertEqual(len(payload["port_location_exceptions"]), 1)
            self.assertEqual(payload["port_location_exceptions"][0]["id"], "PORT-LOC-01")
            self.assertEqual(payload["port_location_exceptions"][0]["symbols"],
                             ["ClockPort", "IdPort"])
            self.assertEqual(payload["port_exceptions_used"], [])
            used_d12 = {item["id"] for item in payload["exceptions"]}
            self.assertTrue(used_d12.issubset({
                "T20-D12-06", "T20-D12-07", "T20-D12-08",
                "T20-D12-11", "T20-D12-12", "T20-D12-13"}),
                f"unexpected D-12 usage after T-23 migration: {sorted(used_d12)}")

    def test_port_exception_legal_tree_passes_including_pure_seam(self) -> None:
        result = run_port("legal")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("violations=0", result.stdout)
        self.assertIn("port_exceptions_used=3", result.stdout)

    def test_unregistered_port_paths_fail_d09_d11_and_d12_stays_strict(self) -> None:
        result = run_port("bad")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("D-09", result.stdout)
        self.assertIn("D-11", result.stdout)
        self.assertIn("D-12", result.stdout)
        self.assertIn("not registered in port_location_exceptions", result.stdout)
        self.assertIn("pages/** may only import C-14 i18n public types", result.stdout)

    def test_port_symbol_overflow_fails(self) -> None:
        result = run_port("symbol-overflow")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("D-11", result.stdout)
        self.assertIn("not covered", result.stdout)

    def test_pending_port_status_fails_and_is_counted(self) -> None:
        result = run_port("pending")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("D-11", result.stdout)
        self.assertIn("status 'pending-T-20'", result.stdout)
        self.assertIn("port_pending=1", result.stdout)
        self.assertIn("port_pending_used=1", result.stdout)

    def test_pending_d12_status_fails_and_is_counted(self) -> None:
        result = run(PENDING_D12, "--allowlist", str(PENDING_D12 / "allowlist.json"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("D-12", result.stdout)
        self.assertIn("status 'pending-T-20'", result.stdout)
        self.assertIn("pending=1", result.stdout)
        self.assertIn("pending_used=1", result.stdout)

    def test_post_migration_contracts_ports_are_legal(self) -> None:
        result = run(POST_MIGRATION, "--allowlist", str(POST_MIGRATION / "allowlist.json"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("violations=0", result.stdout)
        self.assertIn("port_exceptions_used=0", result.stdout)

    def test_post_migration_unregistered_service_ports_fail(self) -> None:
        result = run(POST_MIGRATION_BAD,
                     "--allowlist", str(POST_MIGRATION_BAD / "allowlist.json"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for rule in ("D-09", "D-11", "D-12"):
            self.assertIn(rule, result.stdout)
        self.assertIn("not registered in port_location_exceptions", result.stdout)

    def test_missing_main_root_is_exit_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run(Path(directory))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("does not exist", result.stderr)

    def test_wildcard_port_path_is_rejected_as_input_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "tree"
            (root / "entry/src/main/ets").mkdir(parents=True)
            allowlist = Path(directory) / "allowlist.json"
            allowlist.write_text(json.dumps({
                "entries": [],
                "port_location_exceptions": [{
                    "id": "PORT-LOC-X",
                    "path": "entry/src/main/ets/service/**",
                    "symbols": ["Port"],
                    "kind": "port-only",
                    "status": "accepted-location-exception",
                }],
            }), encoding="utf-8")
            result = run(root, "--allowlist", str(allowlist))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("must be exact", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
