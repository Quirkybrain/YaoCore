"""Fixture self-test for tools/contract/check_layering.py (C-29 / T-19).

Producer: agent:test-engineer | Task: T-19 / wp-082-verify
Contract: DES-B §18.1 (checker must have legal/illegal fixture self-tests);
          DES-B §2.3 D-01..D-17; T-18 ruling 4b99e64.
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


def run(root: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--root", str(root), *extra],
        text=True,
        capture_output=True,
        check=False,
    )


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
        for rule in ("D-01", "D-02", "D-06", "D-08", "D-09", "D-11",
                     "D-12", "D-13", "D-17"):
            self.assertIn(rule, result.stdout, f"missing fixture coverage for {rule}")

    def test_repository_tree_passes_with_versioned_exceptions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "layering.json"
            result = run(REPO_ROOT, "--report", str(report))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["violation_count"], 0)
            self.assertIn("exceptions", payload)
            self.assertTrue(any(item["status"] == "pending-T-20"
                                for item in payload["exceptions"]),
                            "R3-01 exceptions must stay visible as pending-T-20")

    def test_missing_main_root_is_exit_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run(Path(directory))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("does not exist", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
