"""Validate release evidence without executing downloaded metadata."""
import hashlib
import json
from pathlib import Path
import re
import sys

REQUIRED_CHECKS = {
    "Compile app and tests",
    "Portable regression tests",
    "Workflow and script checks",
}


def validate_checks(jobs):
    conclusions = {job["name"]: job["conclusion"] for job in jobs}
    missing = sorted(name for name in REQUIRED_CHECKS if conclusions.get(name) != "success")
    if missing:
        raise ValueError("Release requires successful checks: " + ", ".join(missing))


def verify_checksum(directory, filename):
    checksum = (directory / "SHA256SUMS.txt").read_text().strip()
    match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *]" + re.escape(filename), checksum)
    if not match:
        raise ValueError("Checksum file must name exactly the expected installer.")
    digest = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
    if digest != match[1].lower():
        raise ValueError("Installer checksum does not match.")
    return digest


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "checks":
            validate_checks(json.loads(Path(sys.argv[2]).read_text())["jobs"])
        elif len(sys.argv) == 4 and sys.argv[1] == "checksum":
            print("Installer checksum verified:", verify_checksum(Path(sys.argv[2]), sys.argv[3]))
        else:
            raise ValueError("Usage: release_validation.py checks FILE | checksum DIRECTORY FILENAME")
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
