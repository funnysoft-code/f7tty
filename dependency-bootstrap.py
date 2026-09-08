#!/usr/bin/env python3
"""Fetch the pinned GhosttyKit once; reject checkout drift before every build."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
DEPENDENCY = ROOT / "GhosttyKit"
URL = "https://github.com/briannadoubt/GhosttyKit.git"
PIN = "f3756807a61a42dba3dc1d866a1fd865f1ddfe21"
PATCHES = [ROOT / "patches" / name for name in (
    "GhosttyTerminalSession.patch", "GhosttyTerminalView.patch",
)]


def git(*args):
    return subprocess.check_output(
        ["git", "--no-optional-locks", *args], cwd=DEPENDENCY
    )


def validate():
    if DEPENDENCY.is_symlink() or not (DEPENDENCY / ".git").is_dir():
        raise RuntimeError("GhosttyKit must be a standalone local checkout, not a symlink or worktree.")
    if Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve() != DEPENDENCY:
        raise RuntimeError("Unexpected GhosttyKit repository root.")
    if git("rev-parse", "HEAD").decode().strip() != PIN:
        raise RuntimeError("GhosttyKit HEAD does not match the pinned revision.")
    if git("remote", "get-url", "origin").decode().strip() != URL:
        raise RuntimeError("Unexpected GhosttyKit origin.")
    if git("diff", "--cached", "--name-only") or git("ls-files", "--others", "--exclude-standard"):
        raise RuntimeError("GhosttyKit has staged or untracked changes.")
    actual = git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--binary", "--full-index", PIN)
    expected = b"".join(path.read_bytes() for path in PATCHES)
    if actual != expected:
        raise RuntimeError("GhosttyKit must contain exactly the checked-in patches, with no other changes.")
    git("apply", "--reverse", "--check", *map(str, PATCHES))


def main():
    for patch in PATCHES:
        if not patch.is_file():
            raise RuntimeError(f"Missing dependency patch: {patch.name}")
    if not DEPENDENCY.exists() and not DEPENDENCY.is_symlink():
        subprocess.run(["git", "clone", "--no-checkout", URL, str(DEPENDENCY)], cwd=ROOT, check=True)
        git("checkout", "--detach", PIN)
        git("apply", "--check", *map(str, PATCHES))
        git("apply", *map(str, PATCHES))
    validate()
    print(f"GhosttyKit verified at {PIN} with F7TTY wrapper patches.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Dependency bootstrap refused: {error}\nExisting checkouts are never reset or repaired automatically.")
