"""Exercise bundle assembly with synthetic compiler and signing commands."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class BuildTests(unittest.TestCase):
    def assemble(self, signing_fails=False):
        temporary = tempfile.TemporaryDirectory(prefix="bundle-test-")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        for directory in ("scripts", "helper/Sources", "helper/Resources", "assets", "bin"):
            (root / directory).mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/build.sh", root / "scripts/build.sh")
        for name in ("helper/Sources/main.swift", "helper/Info.plist",
                     "helper/Resources/worklouder_device_bridge.js", "assets/AppIcon.icns"):
            (root / name).write_text("synthetic fixture")
        commands = {
            "uname": "#!/bin/sh\necho Darwin\n",
            "swiftc": '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\nif [ "$1" = -o ]; then shift; printf fixture > "$1"; exit 0; fi\nshift\ndone\nexit 1\n',
            "codesign": "#!/bin/sh\nexit " + ("1" if signing_fails else "0") + "\n",
        }
        for name, body in commands.items():
            command = root / "bin" / name
            command.write_text(body)
            command.chmod(0o755)
        app = root / "build/Creator Micro AI.app"
        stale = app / "Contents/Resources/obsolete.fixture"
        stale.parent.mkdir(parents=True)
        stale.write_text("previous build fixture")
        result = subprocess.run(
            ["bash", "scripts/build.sh"], cwd=root,
            env={**os.environ, "PATH": str(root / "bin") + os.pathsep + os.environ["PATH"]},
            capture_output=True, text=True,
        )
        return root, app, result

    def test_rebuild_excludes_stale_resources_and_preserves_previous_bundle(self):
        root, app, result = self.assemble()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((app / "Contents/Resources/obsolete.fixture").exists())
        self.assertTrue((app / "Contents/Resources/worklouder_device_bridge.js").is_file())
        self.assertTrue((app / "Contents/Resources/AppIcon.icns").is_file())
        self.assertTrue((app / "Contents/MacOS/CreatorMicroAI").is_file())
        recovery = list((root / "build").glob("previous-app.*/Creator Micro AI.app/Contents/Resources/obsolete.fixture"))
        self.assertEqual(len(recovery), 1)
        self.assertEqual(recovery[0].read_text(), "previous build fixture")

    def test_signing_failure_keeps_existing_bundle(self):
        root, app, result = self.assemble(signing_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "Contents/Resources/obsolete.fixture").read_text(), "previous build fixture")
        self.assertFalse(list((root / "build").glob("previous-app.*")))


if __name__ == "__main__":
    unittest.main()
