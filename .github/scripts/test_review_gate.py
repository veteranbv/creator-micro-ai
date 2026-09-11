"""Regression tests for the review gate's trust and freshness boundaries."""

import copy
import json
import os
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

import review_gate as gate

HEAD = "a" * 40
OLD_HEAD = "b" * 40
PUSHED = "2026-09-06T10:00:00Z"
REQUESTED = "2026-09-06T10:01:00Z"
REVIEWED = "2026-09-06T10:02:00Z"


def comment(body, author="owner", when=REQUESTED):
    return {"body": body, "author": {"login": author}, "createdAt": when}


def state():
    return {
        "state": "OPEN",
        "headRefOid": HEAD,
        "commits": {"nodes": [{"commit": {"oid": HEAD, "pushedDate": PUSHED}}]},
        "comments": {"nodes": [comment(f"@codex review {HEAD}")]},
        "reviews": {"nodes": []},
        "reviewThreads": {"nodes": []},
        "reactions": {"nodes": []},
    }


def review(review_id=1, head=HEAD, when=REVIEWED, body=None):
    return {
        "databaseId": review_id,
        "state": "COMMENTED",
        "author": {"login": gate.CODEX_LOGIN},
        "commit": {"oid": head},
        "submittedAt": when,
        "body": body if body is not None else f"### Codex Review\nReviewed commit: `{head}`",
    }


def finding(review_id=1, priority="P1", resolved=False):
    return {
        "isResolved": resolved,
        "comments": {"nodes": [{
            "author": {"login": gate.CODEX_LOGIN},
            "body": f"![{priority} Badge](https://example.test/badge/{priority}-red) Fix issue",
            "path": "src/example.ts",
            "line": 12,
            "pullRequestReview": {"databaseId": review_id},
        }]},
    }


class ReviewGateTests(unittest.TestCase):
    def setUp(self):
        self.data = state()
        self.cutoff = gate._owner_review_cutoff(
            self.data, "owner", HEAD, gate._head_time(self.data)
        )

    def engaged(self):
        return gate.engaged_bots(
            self.data, "owner/repo", HEAD, gate._head_time(self.data), "owner"
        )

    def findings(self):
        return gate.collect_findings(self.data, HEAD, self.cutoff)

    def test_owner_must_request_exact_current_commit(self):
        self.data["reviews"]["nodes"] = [review()]
        for author, body in (
            ("contributor", f"@codex review {HEAD}"),
            ("owner", "@codex review"),
            ("owner", f"@codex review {OLD_HEAD}"),
        ):
            with self.subTest(author=author, body=body):
                self.data["comments"]["nodes"] = [comment(body, author)]
                self.assertEqual(self.engaged(), set())

    def test_prose_mentions_do_not_authorize_a_different_command(self):
        self.data["reviews"]["nodes"] = [review()]
        for body in (
            f"@codex review {OLD_HEAD}\nThe new head is {HEAD}.",
            f"@codex review\nThe new head is {HEAD}.",
            f"Please do not run @codex review {HEAD}",
            f"@codex review {HEAD}0",
        ):
            with self.subTest(body=body):
                self.data["comments"]["nodes"] = [comment(body)]
                self.assertEqual(self.engaged(), set())

    def test_retrigger_uses_the_same_command_boundary(self):
        workflow = Path(__file__).parents[1] / "workflows/review-gate-retrigger.yml"
        snippet = workflow.read_text().split("python3 - <<'PYTHON'\n", 1)[1].split("          PYTHON", 1)[0]
        for body, expected in (
            (f"@codex review {HEAD}", 0),
            (f"@codex review {HEAD}\n\nFixed the findings.", 0),
            (f"@codex  review\t{HEAD}", 0),
            (f"@codex review {HEAD}\r\n\r\nFixed the findings.", 0),
            (f"@codex review {OLD_HEAD}\nCurrent head: {HEAD}", 1),
            (f"Do not run @codex review {HEAD}", 1),
        ):
            with self.subTest(body=body):
                result = subprocess.run(
                    [sys.executable, "-c", textwrap.dedent(snippet)],
                    env={**os.environ, "COMMENT_BODY": body, "HEAD_SHA": HEAD},
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_owner_comments_reach_parser_without_a_narrow_text_guard(self):
        workflow = Path(__file__).parents[1] / "workflows/review-gate-retrigger.yml"
        guard = workflow.read_text().split("    if: >-", 1)[1].split("    runs-on:", 1)[0]
        owner_clause = guard.split("|| (")[-1]
        self.assertIn("github.event_name == 'issue_comment'", owner_clause)
        self.assertIn("github.event.comment.user.login == github.repository_owner", owner_clause)
        self.assertNotIn("contains(", owner_clause)

    def test_reopening_reruns_the_existing_gate_without_checkout(self):
        workflows = Path(__file__).parents[1] / "workflows"
        gate_workflow = (workflows / "review-gate.yml").read_text()
        retrigger = (workflows / "review-gate-retrigger.yml").read_text()
        self.assertIn("types: [opened, synchronize]", gate_workflow)
        self.assertIn("pull_request_target:\n    types: [reopened]", retrigger)
        self.assertIn("github.event_name == 'pull_request_target'", retrigger)
        self.assertNotIn("actions/checkout@", retrigger)

    def test_review_removal_retriggers_evaluation(self):
        workflow = Path(__file__).parents[1] / "workflows/review-gate-retrigger.yml"
        source = workflow.read_text()
        self.assertIn("issue_comment:\n    types: [created, edited, deleted]", source)
        self.assertNotIn("contains(github.event.comment.body", source)
        self.assertIn('[ "${EVENT_ACTION}" = "created" ]', source)

    def test_retrigger_selects_the_matching_pr_across_pages(self):
        workflow = Path(__file__).parents[1] / "workflows/review-gate-retrigger.yml"
        source = workflow.read_text()
        query = source.split('jq --argjson pr "${PR_NUMBER}" ', 1)[1].split("'", 2)[1]
        pages = [
            {"workflow_runs": [{"id": 3, "created_at": "2026-09-06T12:00:00Z", "pull_requests": [{"number": 8}]}]},
            {"workflow_runs": [
                {"id": 2, "created_at": "2026-09-06T11:00:00Z", "pull_requests": [{"number": 9}]},
                {"id": 1, "created_at": "2026-09-06T10:00:00Z", "pull_requests": [{"number": 9}]},
            ]},
        ]
        for pr, expected in ((9, 2), (8, 3), (10, None)):
            with self.subTest(pr=pr):
                result = subprocess.run(
                    ["jq", "--argjson", "pr", str(pr), query], input=json.dumps(pages),
                    capture_output=True, text=True, check=True,
                )
                selected = json.loads(result.stdout)
                self.assertEqual(selected["id"] if selected else None, expected)
        self.assertIn("--paginate --slurp", source)

    def test_completed_review_engages_after_owner_request(self):
        self.data["reviews"]["nodes"] = [review()]
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})

    def test_empty_task_review_does_not_count(self):
        self.data["reviews"]["nodes"] = [review(body="")]
        self.assertEqual(self.engaged(), set())

    def test_nonblocking_inline_findings_prove_review_completion(self):
        for priority in ("P2", "P3"):
            with self.subTest(priority=priority):
                self.data["reviews"]["nodes"] = [review(body="")]
                self.data["reviewThreads"]["nodes"] = [finding(priority=priority)]
                self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})
                self.assertEqual(self.findings(), [])
                self.data["reviews"]["nodes"][0]["commit"]["oid"] = OLD_HEAD
                self.assertEqual(self.engaged(), set())

    def test_stale_review_does_not_count(self):
        for item in (review(head=OLD_HEAD), review(when=PUSHED)):
            with self.subTest(review=item):
                self.data["reviews"]["nodes"] = [item]
                self.assertEqual(self.engaged(), set())

    def test_editing_request_requires_a_new_response(self):
        self.data["reviews"]["nodes"] = [review()]
        self.data["comments"]["nodes"][0]["updatedAt"] = "2026-09-06T10:03:00Z"
        self.assertEqual(self.engaged(), set())

    def test_clean_comment_requires_bot_identity_commit_and_freshness(self):
        body = f"Codex Review: Didn't find any major issues.\nReviewed commit: `{HEAD}`"
        for author, text, when, expected in (
            (gate.CODEX_LOGIN, body, REVIEWED, True),
            ("contributor", body, REVIEWED, False),
            (gate.CODEX_LOGIN, body.replace(HEAD, OLD_HEAD), REVIEWED, False),
            (gate.CODEX_LOGIN, body, PUSHED, False),
        ):
            with self.subTest(author=author, body=text, when=when):
                self.data["comments"]["nodes"] = [comment(f"@codex review {HEAD}"), comment(text, author, when)]
                self.assertEqual(bool(self.engaged()), expected)

    def test_edited_clean_comment_uses_the_current_body_timestamp(self):
        body = f"Codex Review: Didn't find any major issues.\nReviewed commit: `{HEAD}`"
        edited = comment(body, gate.CODEX_LOGIN, PUSHED)
        edited["updatedAt"] = REVIEWED
        self.data["comments"]["nodes"].append(edited)
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})
        edited["updatedAt"] = PUSHED
        self.assertEqual(self.engaged(), set())

    def test_reactions_never_certify_a_commit(self):
        for login, when, expected in (
            (gate.CODEX_LOGIN, REVIEWED, False),
            (gate.CODEX_LOGIN + "[bot]", REVIEWED, False),
            (gate.CODEX_LOGIN, PUSHED, False),
            ("owner", REVIEWED, False),
        ):
            with self.subTest(login=login, when=when):
                self.data["reactions"]["nodes"] = [{"user": {"login": login}, "createdAt": when}]
                self.assertEqual(bool(self.engaged()), expected)

    def test_delayed_reaction_cannot_clear_blocking_findings(self):
        self.data["reviews"]["nodes"] = [review()]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.data["reactions"]["nodes"] = [{"user": {"login": gate.CODEX_LOGIN}, "createdAt": "2026-09-06T10:03:00Z"}]
        self.assertEqual(len(self.findings()), 1)

    def test_short_clean_commit_is_not_accepted_without_resolution(self):
        self.data["comments"]["nodes"].append(comment(
            f"Codex Review: Didn't find any major issues.\nReviewed commit: `{HEAD[:10]}`",
            gate.CODEX_LOGIN, REVIEWED,
        ))
        self.assertEqual(self.engaged(), set())

    def test_short_clean_commit_resolves_to_full_id(self):
        self.data["comments"]["nodes"].append(comment(
            f"Codex Review: Didn't find any major issues.\nReviewed commit: `{HEAD[:10]}`",
            gate.CODEX_LOGIN, REVIEWED,
        ))
        for resolved, expected in ((HEAD, {gate.CODEX_LOGIN}), (OLD_HEAD, set())):
            with self.subTest(resolved=resolved):
                payload = {"data": {"repository": {"pullRequest": copy.deepcopy(self.data)}}}
                with patch.object(gate, "gh_api", side_effect=[payload, {"sha": resolved}]) as api:
                    result = gate.fetch_pr_state("owner/repo", 1)
                self.assertEqual(api.call_args.args[0], [f"repos/owner/repo/commits/{HEAD[:10]}"])
                self.assertEqual(gate.engaged_bots(result, "owner/repo", HEAD, self.cutoff, "owner"), expected)

    def test_ambiguous_or_missing_commit_resolution_fails_closed(self):
        self.data["comments"]["nodes"].append(comment(
            f"Codex Review: Didn't find any major issues.\nReviewed commit: `{HEAD[:10]}`",
            gate.CODEX_LOGIN, REVIEWED,
        ))
        payload = {"data": {"repository": {"pullRequest": self.data}}}
        with patch.object(gate, "gh_api", side_effect=[payload, RuntimeError("ambiguous commit")]):
            with self.assertRaisesRegex(RuntimeError, "ambiguous commit"):
                gate.fetch_pr_state("owner/repo", 1)

    def test_only_p0_and_p1_block(self):
        self.data["reviews"]["nodes"] = [review()]
        self.data["reviewThreads"]["nodes"] = [finding(priority=p) for p in ("P0", "P1", "P2", "P3")]
        self.assertEqual(len(self.findings()), 2)

    def test_review_body_findings_engage_and_block_without_inline_threads(self):
        self.data["reviews"]["nodes"] = [review(body="### Codex Review\n![P1 Badge](https://example.test/badge/P1-red) Fix asset")]
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})
        self.assertEqual(len(self.findings()), 1)

    def test_review_body_p2_engages_but_does_not_block(self):
        self.data["reviews"]["nodes"] = [review(body="![P2 Badge](https://example.test/badge/P2-yellow) Check asset")]
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})
        self.assertEqual(self.findings(), [])

    def test_fresh_review_supersedes_review_body_findings(self):
        self.data["reviews"]["nodes"] = [review(head=OLD_HEAD, body="![P1 Badge](https://example.test/badge/P1-red) Fix asset"), review(2)]
        self.assertEqual(self.findings(), [])

    def test_dismissed_review_body_does_not_block(self):
        item = review(body="![P1 Badge](https://example.test/badge/P1-red) Fix asset")
        item["state"] = "DISMISSED"
        self.data["reviews"]["nodes"] = [item]
        self.assertEqual(self.findings(), [])

    def test_resolved_findings_clear(self):
        self.data["reviewThreads"]["nodes"] = [finding(resolved=True)]
        self.assertEqual(self.findings(), [])

    def test_dismissed_review_clears_findings_but_counts_as_engagement(self):
        item = review()
        item["state"] = "DISMISSED"
        self.data["reviews"]["nodes"] = [item]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})
        self.assertEqual(self.findings(), [])

    def test_new_full_review_supersedes_older_findings(self):
        self.data["reviews"]["nodes"] = [review(head=OLD_HEAD), review(2)]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.assertEqual(self.findings(), [])

    def test_empty_task_review_does_not_clear_findings(self):
        self.data["reviews"]["nodes"] = [review(), review(2, when="2026-09-06T10:03:00Z", body="")]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.assertEqual(len(self.findings()), 1)

    def test_older_clean_signal_cannot_clear_newer_blocking_review(self):
        self.data["reactions"]["nodes"] = [{"user": {"login": gate.CODEX_LOGIN}, "createdAt": REQUESTED}]
        self.data["reviews"]["nodes"] = [review()]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.assertEqual(len(self.findings()), 1)

    def test_missing_push_date_uses_commit_specific_request(self):
        del self.data["commits"]["nodes"][0]["commit"]["pushedDate"]
        self.assertIsNone(gate._head_time(self.data))
        self.assertEqual(gate._owner_review_cutoff(self.data, "owner", HEAD, None), gate._parse_iso(REQUESTED))
        self.data["comments"]["nodes"] = []
        self.assertIsNone(gate._owner_review_cutoff(self.data, "owner", HEAD, None))

    def test_contributor_cannot_move_review_freshness_without_push_date(self):
        self.data["commits"]["nodes"][0]["commit"]["pushedDate"] = None
        self.data["comments"]["nodes"].append(comment(f"@codex review {HEAD}", "contributor", "2026-09-06T10:03:00Z"))
        self.data["reviews"]["nodes"] = [review()]
        self.assertEqual(self.engaged(), {gate.CODEX_LOGIN})

    def test_incomplete_pagination_fails_closed(self):
        self.data["reviews"]["pageInfo"] = {"hasNextPage": True}
        payload = {"data": {"repository": {"pullRequest": self.data}}}
        with patch.object(gate, "gh_api", return_value=payload):
            with self.assertRaisesRegex(RuntimeError, "pagination overflow"):
                gate.fetch_pr_state("owner/repo", 1)

    def test_nested_comment_pagination_fails_closed(self):
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.data["reviewThreads"]["nodes"][0]["comments"]["pageInfo"] = {"hasNextPage": True}
        self.assertEqual(gate._pagination_overflows(self.data), ["reviewThreads[0].comments"])

    def run_main(self, states):
        with patch.dict(gate.os.environ, {"GITHUB_REPOSITORY": "owner/repo", "PR_NUMBER": "1", "PR_HEAD_SHA": HEAD}):
            with patch.object(gate, "fetch_pr_state", side_effect=states), patch.object(gate, "write_summary"), patch.object(gate.time, "sleep"):
                return gate.main()

    def test_missing_review_times_out_with_failure(self):
        with patch.object(gate, "POLL_BUDGET_SECONDS", 0):
            self.assertEqual(self.run_main([self.data]), 1)

    def test_disconnected_codex_fails(self):
        self.data["comments"]["nodes"].append(comment("To use Codex here, connect the repository.", gate.CODEX_LOGIN, REVIEWED))
        self.assertEqual(self.run_main([self.data]), 1)

    def test_clean_completed_review_passes(self):
        self.data["reviews"]["nodes"] = [review()]
        self.assertEqual(self.run_main([self.data]), 0)

    def test_blocking_review_fails(self):
        self.data["reviews"]["nodes"] = [review()]
        self.data["reviewThreads"]["nodes"] = [finding()]
        self.assertEqual(self.run_main([self.data]), 1)

    def test_superseded_run_exits_without_waiting(self):
        moved = copy.deepcopy(self.data)
        moved["headRefOid"] = OLD_HEAD
        self.assertEqual(self.run_main([moved]), 0)
        self.assertEqual(self.run_main([self.data, moved]), 0)

    def test_closed_and_merged_prs_exit_without_waiting(self):
        for status in ("CLOSED", "MERGED"):
            with self.subTest(status=status):
                ended = copy.deepcopy(self.data)
                ended["state"] = status
                self.assertEqual(self.run_main([ended]), 0)
                self.assertEqual(self.run_main([self.data, ended]), 0)


if __name__ == "__main__":
    unittest.main()
