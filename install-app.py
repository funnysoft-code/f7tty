#!/usr/bin/env python3
"""Build and install F7TTY, removing older app bundles without quitting terminals."""

import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent
BUNDLE_ID = "pt.funnysoft.f7tty.development"


def is_f7tty(app):
    """Recognize renamed installations by identity and old previews by filename."""
    if app.is_symlink() or not app.is_dir():
        return False
    name = app.stem.casefold()
    if name == "f7tty" or name.startswith("f7tty-"):
        return True
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        identifier = info.get("CFBundleIdentifier", "")
        return isinstance(identifier, str) and (
            identifier == "pt.funnysoft.f7tty" or identifier.startswith("pt.funnysoft.f7tty.")
        )
    except (OSError, ValueError, plistlib.InvalidFileException, AttributeError):
        return False


def find_installations(roots):
    found = set()
    for root in roots:
        if not root.is_dir() or root.is_symlink():
            continue
        for directory, children, _ in os.walk(root, followlinks=False):
            for name in list(children):
                app = pathlib.Path(directory) / name
                if app.is_symlink():
                    children.remove(name)
                elif app.suffix.casefold() == ".app":
                    children.remove(name)  # Never inspect or delete another app's contents.
                    if is_f7tty(app):
                        found.add(app)
    return sorted(found)


def remove_bundles(apps):
    for app in apps:
        if not is_f7tty(app):
            raise RuntimeError(f"App identity changed during installation: {app}")
        shutil.rmtree(app)
        print(f"Removed {app}", flush=True)


def replace_installation(staged, destination, backup):
    if destination.is_symlink() or (destination.exists() and not is_f7tty(destination)):
        raise RuntimeError(f"Refusing to replace an unrelated app or symlink: {destination}")
    had_previous = destination.exists()
    if had_previous:
        destination.rename(backup)
    try:
        staged.rename(destination)
    except OSError:
        if had_previous:
            backup.rename(destination)
        raise
    if had_previous:
        shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="List cleanup and installation actions without changing files")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("F7TTY installation requires macOS.")

    dist = ROOT / "dist"
    built = dist / "F7TTY.app"
    applications = pathlib.Path("/Applications")
    roots = [applications, pathlib.Path.home() / "Applications"]
    destination = applications / "F7TTY.app"
    previous = find_installations(roots)
    previews = find_installations([dist])
    if args.dry_run:
        for app in previews:
            print(f"Remove old build: {app}")
        print(f"Build with {ROOT / 'build-app.py'}")
        print(f"Install: {destination}")
        for app in previous:
            print(f"{'Replace' if app == destination else 'Remove duplicate'}: {app}")
        print(f"Remove fresh build after installation: {dist / 'F7TTY.app'}")
        return

    if dist.is_symlink():
        raise RuntimeError(f"Refusing to build through a symlink: {dist}")
    if built.is_symlink():
        raise RuntimeError(f"Refusing to overwrite a build symlink: {built}")
    if destination.is_symlink() or (destination.exists() and not is_f7tty(destination)):
        raise RuntimeError(f"Refusing to replace an unrelated app or symlink: {destination}")
    for parent in {applications, *(app.parent for app in previous + previews)}:
        if not os.access(parent, os.W_OK):
            raise RuntimeError(f"Write permission required: {parent}")

    remove_bundles(previews)
    subprocess.run([sys.executable, str(ROOT / "build-app.py")], cwd=ROOT, check=True)
    info = plistlib.loads((built / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError(f"Unexpected build identity: {built}")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(built)], check=True)

    # Stage on the destination filesystem so replacing the app uses renames.
    staging = pathlib.Path(tempfile.mkdtemp(prefix=".f7tty-install-", dir=applications))
    backup = staging / "previous.app"
    try:
        staged = staging / "F7TTY.app"
        subprocess.run(["ditto", str(built), str(staged)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
        replace_installation(staged, destination, backup)
    finally:
        if backup.exists():
            print(f"Previous installation retained for recovery: {backup}", file=sys.stderr)
        else:
            shutil.rmtree(staging)

    print(f"Installed {destination}", flush=True)
    remove_bundles([app for app in previous if app != destination])
    remove_bundles([built])
    print("Done. Quit and reopen F7TTY to use the new build. Running terminals were left open.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Installation failed: {error}", file=sys.stderr)
        sys.exit(1)
