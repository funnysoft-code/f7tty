#!/usr/bin/env python3
"""Exercise installer cleanup and rollback using disposable app bundles."""

import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("installer", pathlib.Path(__file__).resolve().parents[1] / "install-app.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)

    def app(self, name, identifier="pt.funnysoft.f7tty.development"):
        app = self.root / name
        contents = app / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
        return app

    def test_discovery_finds_renamed_and_nested_apps_but_not_other_apps_contents(self):
        renamed = self.app("Renamed.app")
        nested = self.app("Tools/F7TTY-Preview.app")
        self.app("Other.app", "org.example.other")
        self.app("Other.app/Contents/F7TTY.app")
        self.app("Similar.app", "pt.funnysoft.f7tty-unrelated")
        self.assertEqual(installer.find_installations([self.root]), sorted([renamed, nested]))

    def test_discovery_does_not_follow_symlinks(self):
        app = self.app("Storage/F7TTY.app")
        links = self.root / "Links"
        links.mkdir()
        (links / "F7TTY.app").symlink_to(app, target_is_directory=True)
        (links / "Folder").symlink_to(app.parent, target_is_directory=True)
        self.assertEqual(installer.find_installations([links]), [])
        self.assertFalse(installer.is_f7tty(links / "F7TTY.app"))

    def test_cleanup_preserves_measurements_and_unrelated_bundles(self):
        old = self.app("F7TTY-Old.app")
        other = self.app("Other.app", "org.example.other")
        measurement = self.root / "measurement.json"
        measurement.write_text("{}")
        installer.remove_bundles(installer.find_installations([self.root]))
        self.assertFalse(old.exists())
        self.assertTrue(other.exists())
        self.assertEqual(measurement.read_text(), "{}")

    def test_replacement_installs_new_bundle_and_removes_backup(self):
        destination = self.app("F7TTY.app")
        staged = self.app("Staging/F7TTY.app")
        (staged / "new-build").touch()
        backup = self.root / "previous.app"
        installer.replace_installation(staged, destination, backup)
        self.assertTrue((destination / "new-build").exists())
        self.assertFalse(staged.exists())
        self.assertFalse(backup.exists())

    def test_failed_replacement_restores_previous_installation(self):
        destination = self.app("F7TTY.app")
        (destination / "old-build").touch()
        staged = self.app("Staging/F7TTY.app")
        backup = self.root / "previous.app"
        rename = pathlib.Path.rename

        def fail_install(path, target):
            if path == staged:
                raise OSError("Simulated installation failure")
            return rename(path, target)

        with patch.object(pathlib.Path, "rename", fail_install):
            with self.assertRaises(OSError):
                installer.replace_installation(staged, destination, backup)
        self.assertTrue((destination / "old-build").exists())
        self.assertTrue(staged.exists())
        self.assertFalse(backup.exists())

    def test_replacement_rejects_symlink_destination(self):
        original = self.app("Original.app")
        destination = self.root / "F7TTY.app"
        destination.symlink_to(original, target_is_directory=True)
        staged = self.app("Staging/F7TTY.app")
        with self.assertRaises(RuntimeError):
            installer.replace_installation(staged, destination, self.root / "previous.app")
        self.assertTrue(original.exists())
        self.assertTrue(staged.exists())

    def test_build_symlink_is_rejected_before_build_or_cleanup(self):
        original = self.app("Original.app")
        dist = self.root / "dist"
        dist.mkdir()
        (dist / "F7TTY.app").symlink_to(original, target_is_directory=True)
        with patch.object(installer, "ROOT", self.root), \
             patch.object(installer.sys, "argv", ["install-app.py"]), \
             patch.object(installer.sys, "platform", "darwin"), \
             patch.object(installer, "find_installations", return_value=[]), \
             patch.object(installer, "remove_bundles") as cleanup, \
             patch.object(installer.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "build symlink"):
                installer.main()
            cleanup.assert_not_called()
            run.assert_not_called()
        self.assertTrue(original.exists())


if __name__ == "__main__":
    unittest.main()
