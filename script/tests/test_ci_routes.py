"""Routing contracts plus real Git/event integration (no GitHub API dependency)."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "ci_routes.py"
spec = importlib.util.spec_from_file_location("ci_routes", SCRIPT)
routes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routes)


class CoverageTests(unittest.TestCase):
    def test_readme_gif_and_removed_worklog_skip_native(self):
        self.assertEqual(routes.coverage([
            "README.md", ".github/assets/foundation-evals-demo.gif", ".gitignore", "worklog.md"
        ]), (False, False))

    def test_docs_demo_and_release_scripts_only_need_quality(self):
        for path in ["docs/workflow-traces.md", "demo-video/src/index.tsx",
                     "script/release.sh", "script/tests/test_release_validation.py",
                     "examples/custom_model_fixture_server.py"]:
            with self.subTest(path=path):
                self.assertEqual(routes.coverage([path]), (False, False))

    def test_backend_changes_skip_ui(self):
        for path in ["Services/MetricScorer.swift", "MCP/MCPServer.swift"]:
            with self.subTest(path=path):
                self.assertEqual(routes.coverage([routes.APP + path]), (True, False))
        self.assertEqual(routes.coverage([
            "FoundationEvals/FoundationEvalsTests/MetricScorerTests.swift"
        ]), (True, False))

    def test_ui_and_shared_state_require_ui(self):
        for path in ["Views/WorkflowTraceView.swift", "Models/EvaluationModels.swift",
                     "Stores/EvaluationStore.swift", "ContentView.swift",
                     "FoundationEvalsApp.swift", "Assets.xcassets/icon.png",
                     "MCP/Installer/MCPSettingsController.swift",
                     "Services/TelemetryController.swift"]:
            with self.subTest(path=path):
                self.assertEqual(routes.coverage([routes.APP + path]), (True, True))
        for path in ["FoundationEvals/FoundationEvalsUITests/WorkflowTraceUITests.swift",
                     "FoundationEvals/FoundationEvalsTests/TimelineRenderingTests.swift",
                     "FoundationEvals/FoundationEvals.xcodeproj/project.pbxproj"]:
            with self.subTest(path=path):
                self.assertEqual(routes.coverage([path]), (True, True))

    def test_ci_dependencies_unknown_and_mixed_changes_run_full(self):
        for path in [".github/workflows/ci.yml", "script/ci_routes.py",
                     "script/tests/test_ci_routes.py", "script/ci_core_scheme.py",
                     "script/tests/test_ci_core_scheme.py", "Package.swift",
                     "new-runtime/code.swift", "version.txt"]:
            with self.subTest(path=path):
                self.assertEqual(routes.coverage(["README.md", path]), (True, True))


class GitEventTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "CI fixture")
        self.base = self.commit("README.md", "start")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def commit(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        self.git("add", "--all")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def run_event(self, name, event):
        event_path = self.root / "event.json"
        event_path.write_text(json.dumps(event))
        output = self.root / "outputs"
        output.write_text("")
        subprocess.run([sys.executable, str(SCRIPT)], cwd=self.root, check=True,
                       capture_output=True, env=dict(os.environ,
                       GITHUB_EVENT_NAME=name, GITHUB_EVENT_PATH=str(event_path),
                       GITHUB_OUTPUT=str(output), GITHUB_STEP_SUMMARY=str(self.root / "summary")))
        return output.read_text()

    def test_pull_request_routes_entire_branch_despite_latest_docs_commit(self):
        self.git("checkout", "-qb", "feature")
        self.commit(routes.APP + "Services/MetricScorer.swift", "native")
        head = self.commit("README.md", "docs")
        self.git("checkout", "main")
        base = self.commit("CHANGELOG.md", "unrelated base change")
        self.assertEqual(self.run_event("pull_request", {
            "pull_request": {"base": {"sha": base}, "head": {"sha": head}}
        }), "native=true\nui=false\n")

    def test_push_uses_previous_tip_not_parent(self):
        self.commit(routes.APP + "Views/View.swift", "UI")
        head = self.commit("README.md", "docs")
        self.assertEqual(self.run_event("push", {"before": self.base, "after": head}),
                         "native=true\nui=true\n")

    def test_deletion_and_rename_out_of_native_tree_still_require_coverage(self):
        native = routes.APP + "Views/View.swift"
        base = self.commit(native, "UI")
        self.git("mv", native, "README.md", "--force")
        self.git("commit", "-qm", "move UI to docs")
        head = self.git("rev-parse", "HEAD")
        paths = routes.changed_paths("push", {"before": base, "after": head}, self.root)
        self.assertIn(native, paths)
        self.assertEqual(routes.coverage(paths), (True, True))

    def test_zero_missing_and_manual_events_use_full_coverage(self):
        for name, event in [
            ("workflow_dispatch", {}),
            ("push", {"before": "0" * 40, "after": self.base}),
            ("push", {"before": "a" * 40, "after": self.base}),
            ("push", {"before": "--bad-option", "after": self.base}),
        ]:
            with self.subTest(name=name, event=event):
                self.assertEqual(self.run_event(name, event), "native=true\nui=true\n")

    def test_gif_push_with_whitespace_filename_skips_native(self):
        head = self.commit(".github/assets/new demo\nrecording.gif", "GIF fixture")
        self.assertEqual(self.run_event("push", {"before": self.base, "after": head}),
                         "native=false\nui=false\n")


if __name__ == "__main__":
    unittest.main()
