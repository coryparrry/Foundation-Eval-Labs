#!/usr/bin/env python3
"""Select native and UI coverage; unknown changes conservatively run everything."""
import json
import os
from pathlib import Path
import re
import subprocess

UI_TEST_FILES = {
    "NavigationInteractionTests.swift",
    "TimelineRenderingTests.swift",
    "RunToolbarProgressTests.swift",
    "WorkflowTimelineIntervalTests.swift",
}
APP = "FoundationEvals/FoundationEvals/"


def coverage(paths):
    native = ui = False
    for path in paths:
        # Configuration and routing changes exercise every route's consumers.
        if (path in {"Package.swift", "Package.resolved", "script/ci_routes.py",
                     "script/tests/test_ci_routes.py", "script/ci_core_scheme.py",
                     "script/tests/test_ci_core_scheme.py", "script/build_and_run.sh"}
                or path.startswith(".github/workflows/")):
            return True, True
        if path.startswith(APP):
            native = True
            # Models/stores are shared UI contracts, even without a view edit.
            if (path in {APP + "MCP/Installer/MCPSettingsController.swift",
                         APP + "Services/TelemetryController.swift"}
                    or not path.startswith((APP + "Services/", APP + "MCP/"))):
                ui = True
        elif path.startswith("FoundationEvals/FoundationEvalsTests/"):
            native = True
            ui |= Path(path).name in UI_TEST_FILES
        elif path.startswith("FoundationEvals/"):
            # Includes UI tests, project settings, schemes and resolved packages.
            return True, True
        elif (path in {"README.md", "CHANGELOG.md", "LICENSE", ".gitignore", "worklog.md"}
              or path.startswith(("docs/", ".github/assets/", "demo-video/"))):
            continue
        elif path.startswith(("script/", "examples/")) and path.endswith((".py", ".sh")):
            # Validated by the always-on Linux quality job.
            continue
        else:
            return True, True
    return native, ui


def changed_paths(event_name, event, root):
    if event_name == "pull_request":
        pull = event["pull_request"]
        base, head = pull["base"]["sha"], pull["head"]["sha"]
        separator = "..."  # Entire PR, not just its latest commit.
    elif event_name == "push":
        base, head = event["before"], event["after"]
        separator = ".."
    else:
        return None
    if not all(re.fullmatch(r"[0-9a-f]{40}", sha) and sha != "0" * 40
               for sha in (base, head)):
        return None
    try:
        result = subprocess.run(
            ["git", "diff", "--no-renames", "--name-only", "-z", f"{base}{separator}{head}", "--"],
            cwd=root, check=True, capture_output=True,
        )
    except subprocess.CalledProcessError:
        return None  # Missing history must never silently omit native coverage.
    return [os.fsdecode(path) for path in result.stdout.split(b"\0") if path]


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    paths = changed_paths(os.environ["GITHUB_EVENT_NAME"], event, Path.cwd())
    native, ui = (True, True) if paths is None else coverage(paths)
    outputs = f"native={str(native).lower()}\nui={str(ui).lower()}\n"
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(outputs)
    print(outputs, end="")
    reason = "Full coverage: manual/unsupported event or unavailable diff." if paths is None else f"Classified {len(paths)} changed paths (including deletions and both sides of renames)."
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
        summary.write(f"## CI coverage\n\n{reason}\n\n"
                      f"- Linux workflow and script checks: always\n"
                      f"- Native build and core regressions: {native}\n"
                      f"- UI components and UI test bundle compilation: {ui}\n")


if __name__ == "__main__":
    main()
