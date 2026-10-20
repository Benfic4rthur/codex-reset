#!/usr/bin/env python3
"""Check release contents and Git blobs locally without printing secret values."""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b",
    "OpenAI API key": rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b",
    "Private key": rb"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----",
    "AWS access key": rb"\bAKIA[A-Z0-9]{16}\b",
    "Credential assignment": rb"""(?im)^\s*(?:export\s+)?(?:OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|GH_TOKEN|AWS_SECRET_ACCESS_KEY)\s*=\s*["']?[A-Za-z0-9_./+=-]{12,}""",
}
failures = []
checked = 0


def check(name, data, distributed=False):
    global checked
    checked += 1
    path = Path(name)
    if (path.name in {"auth.json", ".env"} or
            path.suffix in {".pem", ".p12", ".pfx", ".key", ".sqlite", ".db", ".log"} or
            (path.name.startswith(".env.") and path.name != ".env.example")):
        failures.append((name, "personal configuration or database file"))
    for label, pattern in PATTERNS.items():
        if re.search(pattern, data):
            failures.append((name, label))
    if distributed and re.search(rb"/Users/[^/\x00\s]+/", data):
        failures.append((name, "personal build path"))


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--git-history", action="store_true")
parser.add_argument("apps", nargs="*", type=Path)
args = parser.parse_args()

if args.git_history:
    seen = set()
    commits = subprocess.check_output(["git", "rev-list", "--all"], cwd=ROOT, text=True).splitlines()
    for commit in commits:
        tree = subprocess.check_output(["git", "ls-tree", "-rz", "--full-tree", commit], cwd=ROOT)
        for entry in tree.split(b"\0"):
            if not entry:
                continue
            metadata, name = entry.split(b"\t", 1)
            _, kind, oid = metadata.split()
            if kind != b"blob" or oid in seen:
                continue
            seen.add(oid)
            data = subprocess.check_output(["git", "cat-file", "blob", oid.decode()], cwd=ROOT)
            check(f"git:{commit[:8]}/{name.decode()}", data)

for app in args.apps:
    if not app.is_dir() or app.suffix != ".app":
        parser.error(f"Not an application bundle: {app}")
    allowed = {
        "Contents/Info.plist",
        "Contents/MacOS/CodexReset",
        "Contents/MacOS/CodexResetCompanion",
        "Contents/Resources/CodexReset.icns",
        "Contents/_CodeSignature/CodeResources",
    }
    for path in app.rglob("*"):
        if path.is_symlink():
            failures.append((str(path.relative_to(app)), "unexpected symbolic link inside app"))
        elif path.is_file():
            relative = path.relative_to(app).as_posix()
            if relative not in allowed:
                failures.append((relative, "unexpected bundled file"))
            check(relative, path.read_bytes(), distributed=True)

if failures:
    for name, reason in failures:
        print(f"{name}: {reason}", file=sys.stderr)
    raise SystemExit(1)
print(f"Local privacy check: {checked} files/blobs checked; no matching credentials or personal release files found.")
