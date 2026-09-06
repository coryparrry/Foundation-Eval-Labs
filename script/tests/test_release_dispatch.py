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
        self.git("tag", "v1.2.3")
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as out:
    out.write(json.dumps(args) + "\\n")
if args[:2] == ["run", "list"]:
    print("" if os.environ.get("NO_CI") else "123")
elif args[:2] == ["run", "view"]:
    names = ["Compile app and tests", "Portable regression tests", "Workflow and script checks"]
    print(json.dumps({"jobs": [{"name": name, "conclusion": "failure" if os.environ.get("FAILED_JOB") else "success"} for name in names]}))
elif args[0] == "api" and "/commits/" in args[1]:
    if os.environ.get("FAIL_API"):
        sys.exit(1)
    print(os.environ.get("REMOTE_SHA", os.environ["GITHUB_SHA"]))
elif args[:2] == ["release", "upload"]:
    assert "--clobber" not in args
    sys.exit(1 if os.environ.get("EXISTING_ASSET") else 0)
elif args[:2] == ["release", "download"]:
    sys.exit(1 if os.environ.get("FAIL_DOWNLOAD") else 0)
elif args[:2] == ["release", "view"]:
    if os.environ.get("MISSING_RELEASE"):
        sys.exit(1)
    print("https://github.com/owner/repo/releases/tag/v1.2.3")
else:
    sys.exit("Unexpected GitHub operation: " + repr(args))
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", RELEASE_TAG="v1.2.3",
                        BUILD_NUMBER="2", GITHUB_SHA=self.commit, GITHUB_REPOSITORY="owner/repo",
                        RELEASE_BRANCH="main", GITHUB_REF="refs/heads/main", CALL_LOG=str(self.root / "calls.jsonl"),
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

    def test_prepare_existing_release(self):
        self.run_dispatch()
        self.assertIn('"run", "list"', self.calls())
        self.assertNotIn('"release", "upload"', self.calls())

    def test_reject_invalid_inputs(self):
        for variables in ({"RELEASE_TAG": "bad"}, {"BUILD_NUMBER": "0"},
                          {"GITHUB_REF": "refs/heads/feature"}):
            with self.subTest(variables=variables):
                self.run_dispatch(success=False, **variables)

    def test_reject_missing_release_or_source_mismatch(self):
        for variables in ({"MISSING_RELEASE": "1"}, {"REMOTE_SHA": "a" * 40},
                          {"FAIL_API": "1"}, {"NO_CI": "1"}, {"FAILED_JOB": "1"}):
            with self.subTest(variables=variables):
                self.run_dispatch(success=False, **variables)
        self.assertNotIn('"release", "upload"', self.calls())

    def test_reject_dirty_checkout(self):
        (self.root / "unexpected.txt").write_text("dirty")
        self.run_dispatch(success=False)

    def test_upload_and_verify_existing_release(self):
        self.run_dispatch("publish")
        self.assertIn('"release", "upload"', self.calls())
        self.assertIn('"release", "download"', self.calls())
        self.assertNotIn('"release", "create"', self.calls())
        self.assertNotIn('"release", "edit"', self.calls())

    def test_upload_failure_does_not_verify_or_overwrite(self):
        self.run_dispatch("publish", success=False, EXISTING_ASSET="1")
        self.assertNotIn('"release", "download"', self.calls())
        self.assertNotIn('--clobber', self.calls())

    def test_invalid_installer_never_uploads(self):
        self.run_dispatch("publish", success=False, FAIL_INSTALLER="1")
        self.assertNotIn('"release", "upload"', self.calls())

    def test_download_failure_fails_job(self):
        self.run_dispatch("publish", success=False, FAIL_DOWNLOAD="1")

    def test_protected_scripts_package_separate_source_without_scripts(self):
        source = self.root / "bin/source"
        subprocess.check_call(["git", "clone", "-q", str(self.root), str(source)])
        subprocess.check_call(["git", "rm", "-rq", "script"], cwd=source)
        subprocess.check_call(["git", "-c", "user.name=Fixture", "-c",
                               "user.email=fixture@example.com", "commit", "-qm", "source only"], cwd=source)
        subprocess.check_call(["git", "tag", "-f", "v1.2.3"], cwd=source, stdout=subprocess.DEVNULL)
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        self.run_dispatch(SOURCE_DIR=str(source), REMOTE_SHA=commit)
        self.run_dispatch("publish", SOURCE_DIR=str(source), REMOTE_SHA=commit)
        self.assertIn('"release", "download"', self.calls())

    def test_tag_need_not_be_current_main(self):
        self.run_dispatch(GITHUB_SHA="b" * 40, REMOTE_SHA=self.commit)


if __name__ == "__main__":
    unittest.main()
