"""Verify the generated scheme retains core coverage and never edits the source."""

import importlib.util
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "ci_core_scheme", ROOT / "script/ci_core_scheme.py"
)
scheme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scheme)


class CoreSchemeTests(unittest.TestCase):
    def test_ci_generates_and_executes_core_scheme_without_running_ui_tests(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("name: Compile app and tests", workflow)
        self.assertIn("python3 script/ci_core_scheme.py", workflow)

        build_step = re.search(
            r"      - name: Build app and selected test bundles\n"
            r"        env:\n"
            r"          INCLUDE_UI:.*\n"
            r"        run: \|\n(?P<script>(?:          .*\n)+)",
            workflow,
        )
        self.assertIsNotNone(build_step)
        script = build_step.group("script")
        self.assertRegex(
            script,
            r"xcodebuild test \\\n"
            r"\s+-project FoundationEvals/FoundationEvals\.xcodeproj \\\n"
            r"\s+-scheme FoundationEvalsCoreCI \\\n"
            r"\s+-configuration Debug \\\n"
            r"\s+-destination 'platform=macOS'",
        )
        self.assertNotIn("FoundationEvalsUITests", script)

    def test_ci_compiles_full_scheme_only_for_ui_coverage(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        build_step = re.search(
            r"      - name: Build app and selected test bundles\n"
            r"        env:\n"
            r"          INCLUDE_UI:.*\n"
            r"        run: \|\n(?P<script>(?:          .*\n)+)",
            workflow,
        )
        self.assertIsNotNone(build_step)
        script = build_step.group("script")
        self.assertRegex(
            script,
            r"if \[\[ \"\$INCLUDE_UI\" == true \]\]; then\n"
            r"\s+xcodebuild build-for-testing \\\n"
            r"\s+-project FoundationEvals/FoundationEvals\.xcodeproj \\\n"
            r"\s+-scheme FoundationEvals \\\n"
            r"\s+-configuration Debug",
        )
        self.assertNotRegex(
            script,
            r"xcodebuild test[\s\S]*-scheme FoundationEvals(?:\s|$)",
        )

    def test_push_ci_is_not_cancelled_by_later_commits_on_the_same_branch(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("group: ci-${{ github.ref }}", workflow)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", workflow)
        self.assertNotRegex(
            workflow,
            r"concurrency:\n  group: ci-\$\{\{ github\.ref \}\}\n  cancel-in-progress: true\n",
        )

    def test_real_scheme_excludes_ui_and_preserves_core_and_build_settings(self):
        source = ROOT / scheme.SCHEMES / "FoundationEvals.xcscheme"
        before = source.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "Core.xcscheme"
            scheme.create_core_scheme(source, output)
            tree = ET.parse(output)
        names = [
            node.get("BlueprintName")
            for node in tree.findall(
                "TestAction/Testables/TestableReference/BuildableReference"
            )
        ]
        self.assertEqual(names, ["FoundationEvalsTests"])
        self.assertEqual(source.read_bytes(), before)
        self.assertEqual(
            ET.tostring(tree.find("BuildAction")),
            ET.tostring(ET.fromstring(before).find("BuildAction")),
        )

    def test_missing_ui_or_core_target_fails_instead_of_omitting_tests(self):
        for name in ["FoundationEvalsUITests", "FoundationEvalsTests"]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                source = Path(temporary) / "Input.xcscheme"
                tree = ET.parse(ROOT / scheme.SCHEMES / "FoundationEvals.xcscheme")
                testables = tree.find("TestAction/Testables")
                for test in list(testables):
                    if test.find("BuildableReference").get("BlueprintName") == name:
                        testables.remove(test)
                tree.write(source)
                with self.assertRaises(ValueError):
                    scheme.create_core_scheme(
                        source, Path(temporary) / "Output.xcscheme"
                    )


if __name__ == "__main__":
    unittest.main()
