"""Exercise release orchestration with real Git and a recording GitHub fixture."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ReleaseDispatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = Path(__file__).resolve().parents[1]
        shutil.copytree(source, self.root / "script", ignore=shutil.ignore_patterns("__pycache__"))
        (self.root / "script/verify_installer.sh").write_text(
            '#!/bin/bash\nprintf "installer\\n" >> "$CALL_LOG"\n'
            'exit "${FAIL_INSTALLER:-0}"\n'
        )
        (self.root / ".gitignore").write_text("dist/\nbin/\ncalls.jsonl\nsummary.md\n__pycache__/\n")
        self.git("init", "-q", "-b", "main")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.com", "commit", "-qm", "fixture")
        self.commit = self.git("rev-parse", "HEAD").strip()
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
tag_state = Path(os.environ["CALL_LOG"]).parent / "bin/remote-tag"
with open(os.environ["CALL_LOG"], "a") as out:
    out.write(json.dumps(args) + "\\n")
if args[:2] == ["api", "repos/owner/repo/releases"]:
    if os.environ.get("FAIL_API"):
        sys.exit(1)
    print(os.environ.get("EXISTING_RELEASE", ""))
elif args[:2] == ["run", "list"]:
    print("" if os.environ.get("NO_CI") else "123")
elif args[:2] == ["run", "view"]:
    names = ["Compile app and tests", "Portable regression tests", "Workflow and script checks"]
    print(json.dumps({"jobs": [{"name": name, "conclusion": "failure" if os.environ.get("FAILED_JOB") else "success"} for name in names]}))
elif args[0] == "api" and "/git/matching-refs/" in args[1]:
    if os.environ.get("FAIL_TAG_LOOKUP"):
        sys.exit(1)
    print("refs/tags/" + os.environ["RELEASE_TAG"] if tag_state.exists() else "")
elif args[:2] == ["api", "repos/owner/repo/git/refs"]:
    if tag_state.exists() or os.environ.get("TAG_CREATE_RACE"):
        sys.exit(1)
    assert "POST" in args and "ref=refs/tags/" + os.environ["RELEASE_TAG"] in args
    assert "sha=" + os.environ["GITHUB_SHA"] in args
    tag_state.write_text(os.environ["GITHUB_SHA"])
elif args[0] == "api" and "/commits/" in args[1]:
    if not tag_state.exists() or os.environ.get("FAIL_COMMIT_LOOKUP"):
        sys.exit(1)
    print(tag_state.read_text())
elif args[:2] == ["release", "create"]:
    # A draft never creates its tag. --verify-tag must find the explicit ref.
    if "--verify-tag" not in args or not tag_state.exists():
        sys.exit(1)
elif args[:2] == ["release", "download"] and os.environ.get("FAIL_DOWNLOAD"):
    sys.exit(1)
elif args[:2] == ["release", "view"]:
    print("https://github.com/owner/repo/releases/tag/v1.2.3")
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", RELEASE_TAG="v1.2.3",
                        BUILD_NUMBER="2", GITHUB_SHA=self.commit, GITHUB_REPOSITORY="owner/repo",
                        RELEASE_BRANCH="main", GITHUB_REF="refs/heads/main", PUBLISH_RELEASE="false",
                        NATIVE_TESTED="false", CALL_LOG=str(self.root / "calls.jsonl"),
                        GITHUB_STEP_SUMMARY=str(self.root / "summary.md"))

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True)

    def run_dispatch(self, mode="prepare", success=True, **environment):
        result = subprocess.run(["bash", "script/release_dispatch.sh", mode], cwd=self.root,
                                env=dict(self.env, **environment), text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def calls(self):
        path = self.root / "calls.jsonl"
        return path.read_text() if path.exists() else ""

    def test_prepare_requires_exact_source_ci_before_local_tag(self):
        self.run_dispatch()
        self.assertEqual(self.git("rev-parse", "v1.2.3").strip(), self.commit)
        self.assertIn(self.commit, self.calls())
        self.assertIn('"--branch", "main", "--event", "push"', self.calls())
        self.assertNotIn('"release", "create"', self.calls())

    def test_missing_or_incomplete_ci_does_not_tag(self):
        for env in ({"NO_CI": "1"}, {"FAILED_JOB": "1"}):
            with self.subTest(env=env):
                self.run_dispatch(success=False, **env)
                self.assertEqual(self.git("tag"), "")

    def test_release_lookup_failure_is_not_treated_as_absence(self):
        self.run_dispatch(success=False, FAIL_API="1")
        self.assertEqual(self.git("tag"), "")

    def test_existing_release_cannot_be_overwritten(self):
        self.run_dispatch(success=False, EXISTING_RELEASE="v1.2.3")
        self.assertEqual(self.git("tag"), "")

    def test_bad_inputs_and_wrong_branch_are_rejected(self):
        for env in ({"RELEASE_TAG": "v1.2.3;echo bad"}, {"BUILD_NUMBER": "0"},
                    {"GITHUB_SHA": "a" * 40}, {"GITHUB_REF": "refs/heads/topic"},
                    {"PUBLISH_RELEASE": "yes"}):
            with self.subTest(env=env):
                self.run_dispatch(success=False, **env)
                self.assertEqual(self.git("tag"), "")

    def test_dirty_source_is_rejected(self):
        (self.root / "uncommitted.txt").write_text("dirty")
        self.run_dispatch(success=False)
        self.assertEqual(self.git("tag"), "")

    def test_existing_tag_must_match_source(self):
        self.git("tag", "v1.2.3")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.com",
                 "commit", "--allow-empty", "-qm", "later")
        self.run_dispatch(success=False, GITHUB_SHA=self.git("rev-parse", "HEAD").strip())
        self.assertNotIn('"run", "list"', self.calls())

    def test_publish_requires_native_confirmation(self):
        self.run_dispatch(success=False, PUBLISH_RELEASE="true")
        self.assertEqual(self.git("tag"), "")

    def test_default_creates_verified_draft(self):
        self.run_dispatch("publish")
        calls = self.calls()
        self.assertIn('"--verify-tag", "--draft"', calls)
        self.assertLess(calls.index('"repos/owner/repo/git/refs"'), calls.index('"release", "create"'))
        self.assertEqual((self.root / "bin/remote-tag").read_text(), self.commit)
        self.assertIn('"release", "download"', calls)
        self.assertNotIn('"release", "edit"', calls)

    def test_explicit_publication_happens_after_download_verification(self):
        self.run_dispatch("publish", PUBLISH_RELEASE="true", NATIVE_TESTED="true")
        calls = self.calls()
        self.assertLess(calls.index('"release", "download"'), calls.index('"release", "edit"'))
        self.assertIn('"--draft=false"', calls)

    def test_failed_download_leaves_draft_unpublished(self):
        self.run_dispatch("publish", success=False, PUBLISH_RELEASE="true", NATIVE_TESTED="true", FAIL_DOWNLOAD="1")
        self.assertIn('"release", "create"', self.calls())
        self.assertNotIn('"release", "edit"', self.calls())

    def test_failed_installer_check_creates_no_release(self):
        self.run_dispatch("publish", success=False, FAIL_INSTALLER="1")
        self.assertNotIn('"release", "create"', self.calls())
        self.assertFalse((self.root / "bin/remote-tag").exists())

    def test_existing_remote_tag_is_reused_only_at_exact_source(self):
        (self.root / "bin/remote-tag").write_text(self.commit)
        self.run_dispatch("publish")
        self.assertNotIn('"repos/owner/repo/git/refs"', self.calls())

    def test_mismatched_remote_tag_is_never_moved(self):
        (self.root / "bin/remote-tag").write_text("b" * 40)
        self.run_dispatch("publish", success=False)
        self.assertEqual((self.root / "bin/remote-tag").read_text(), "b" * 40)
        self.assertNotIn('"release", "create"', self.calls())

    def test_tag_lookup_failure_or_creation_race_prevents_draft(self):
        for env in ({"FAIL_TAG_LOOKUP": "1"}, {"TAG_CREATE_RACE": "1"}):
            with self.subTest(env=env):
                self.run_dispatch("publish", success=False, **env)
                self.assertNotIn('"release", "create"', self.calls())
                self.assertFalse((self.root / "bin/remote-tag").exists())

    def test_commit_lookup_failure_prevents_draft(self):
        self.run_dispatch("publish", success=False, FAIL_COMMIT_LOOKUP="1")
        self.assertNotIn('"release", "create"', self.calls())

    def test_verifier_cannot_resolve_tag_without_explicit_creation(self):
        result = subprocess.run(["bash", "script/verify_release.sh"], cwd=self.root,
                                env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('"release", "download"', self.calls())


if __name__ == "__main__":
    unittest.main()
