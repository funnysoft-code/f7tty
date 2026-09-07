#!/usr/bin/env python3
"""Build a local, ad-hoc-signed prototype app. Does not install it."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--output", default="dist/F7TTY.app", help="Separate app bundle for attended previews")
args = parser.parse_args()

root = pathlib.Path(__file__).resolve().parent
subprocess.run([sys.executable, str(root / "dependency-bootstrap.py")], cwd=root, check=True)
subprocess.run(["swift", "build", "-c", "release", "--product", "F7TTY"], cwd=root, check=True)
release = root / ".build/release"
contents = root / args.output / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(exist_ok=True)
shutil.copy2(release / "F7TTY", contents / "MacOS/F7TTY")
shutil.copytree(release / "F7TTY_F7TTY.bundle", contents / "Resources/F7TTY_F7TTY.bundle", dirs_exist_ok=True)
subprocess.run([str(release / "F7TTY"), "--export-icon", str(contents / "Resources/F7TTY.png")], check=True)
with (contents / "Info.plist").open("wb") as output:
    plistlib.dump({
        "CFBundleName": "F7TTY", "CFBundleDisplayName": "F7TTY",
        "CFBundleIdentifier": "pt.funnysoft.f7tty.development" if args.output == "dist/F7TTY.app" else "pt.funnysoft.f7tty.polish",
        "CFBundleExecutable": "F7TTY", "CFBundlePackageType": "APPL",
        "CFBundleIconFile": "F7TTY.png",
        "CFBundleShortVersionString": "0.3", "CFBundleVersion": "3",
        "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
        "NSSupportsAutomaticTermination": False,
    }, output)
subprocess.run(["codesign", "--force", "--sign", "-", str(contents.parent)], check=True)
print(contents.parent)
