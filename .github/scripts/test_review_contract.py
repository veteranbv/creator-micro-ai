# Vendored from veteranbv/homelab (docs/standards/templates/review/files/).
# Standard-library smoke test for the vendored review contract; the full
# conformance matrix runs at the source (tools/tests/test_review_contract.py).
"""The vendored contract loads uninstalled and still qualifies real evidence."""

from __future__ import annotations

import ast
import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "review_contract.py"
FIXTURE = HERE / "fixtures" / "codex_review" / "qualified_homelab_547.json"

_spec = importlib.util.spec_from_file_location("review_contract", CONTRACT)
assert _spec is not None and _spec.loader is not None
rc = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = rc  # dataclasses resolve annotations via sys.modules
_spec.loader.exec_module(rc)

TRAILER = "Co-Authored-By: Claude <noreply@example.test>"


def _base() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def _request(snapshot: dict) -> dict:
    return next(c for c in snapshot["comments"] if c["body"].startswith("@codex"))


class ReviewContractSmokeTest(unittest.TestCase):
    def assert_blocked(self, snapshot: dict, reason: str) -> None:
        verdict = rc.evaluate(snapshot)
        self.assertFalse(verdict.qualified)
        self.assertIn(reason, verdict.reasons)

    def test_real_evidence_qualifies(self) -> None:
        verdict = rc.evaluate(_base())
        self.assertTrue(verdict.qualified, verdict.reasons)

    def test_contract_is_standard_library_only(self) -> None:
        tree = ast.parse(CONTRACT.read_text(encoding="utf-8"))
        modules = {
            alias.name.split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, ast.Import)
            for alias in node.names
        } | {
            (node.module or "").split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom) and node.level == 0
        }
        self.assertLessEqual(modules, set(sys.stdlib_module_names))

    def test_missing_owner_request_blocks(self) -> None:
        snapshot = _base()
        snapshot["comments"].remove(_request(snapshot))
        verdict = rc.evaluate(snapshot)
        self.assertFalse(verdict.qualified)

    def test_request_from_someone_else_blocks(self) -> None:
        snapshot = _base()
        _request(snapshot)["author"] = "someone-else"
        self.assertFalse(rc.evaluate(snapshot).qualified)

    def test_edited_request_blocks(self) -> None:
        snapshot = _base()
        _request(snapshot)["edited"] = True
        self.assertFalse(rc.evaluate(snapshot).qualified)

    def test_new_head_invalidates_review(self) -> None:
        snapshot = _base()
        snapshot["head_sha"] = "0" * 40
        self.assertFalse(rc.evaluate(snapshot).qualified)

    def test_unresolved_thread_blocks(self) -> None:
        snapshot = _base()
        snapshot["unresolved_threads"] = 1
        self.assert_blocked(snapshot, "unresolved_threads")

    def test_ai_attribution_blocks(self) -> None:
        snapshot = copy.deepcopy(_base())
        snapshot["commits"][0]["message"] += f"\n\n{TRAILER}"
        self.assertFalse(rc.evaluate(snapshot).qualified)


if __name__ == "__main__":
    unittest.main()
