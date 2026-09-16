"""Exercise bundle assembly with synthetic compiler and signing commands."""
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class BuildTests(unittest.TestCase):
    def test_production_build_uses_explicit_tools_without_path_rewrites(self):
        script = (ROOT / "scripts/build.sh").read_text()
        for tool in ("dirname", "uname", "mktemp", "plutil", "xcrun", "otool", "awk", "lipo", "codesign"):
            self.assertIn("/usr/bin/" + tool + " ", script)
        for tool in ("mkdir", "cp", "rm", "mv", "rmdir"):
            self.assertIn("/bin/" + tool + " ", script)
        self.assertIn('"$compiler"', script)
        self.assertIn('-tools-directory "${compiler%/*}"', script)
        self.assertNotRegex(script, r"\bPATH\s*=")

    def assemble(self, signing_fails=False, minimum="13.2", actual="13.2", universal=False):
        temporary = tempfile.TemporaryDirectory(prefix="bundle-test-")
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        for directory in ("scripts", "helper/Sources", "helper/Resources", "assets", "bin", "device", "docs/assets"):
            (root / directory).mkdir(parents=True)
        script = (ROOT / "scripts/build.sh").read_text()
        for name in ("helper/Sources/main.swift", "helper/Info.plist",
                     "helper/Resources/worklouder_device_bridge.js", "assets/AppIcon.icns",
                     "device/configure.js", "device/keymap.json", "docs/layout.html",
                     "docs/assets/keycaps.svg", "docs/assets/creator-micro-device.png"):
            (root / name).write_text("synthetic fixture")
        commands = {
            "xcrun": '#!/bin/sh\nif [ "$1" = --sdk ]; then printf "%s/sdk\\n" "$PWD"; else printf "%s/bin/swiftc\\n" "$PWD"; fi\n',
            "uname": '#!/bin/sh\nif [ "$1" = -m ]; then echo arm64; else echo Darwin; fi\n',
            "plutil": '#!/bin/sh\nprintf "%s\\n" "' + minimum + '"\n',
            "otool": '#!/bin/sh\nprintf "cmd LC_BUILD_VERSION\\nplatform 1\\nminos %s\\n" "' + actual + '"\n',
            "swiftc": '#!/bin/sh\nprintf "%s\\n" "$@" > compiler-arguments\nwhile [ "$#" -gt 0 ]; do\nif [ "$1" = -o ]; then shift; printf fixture > "$1"; exit 0; fi\nshift\ndone\nexit 1\n',
            "codesign": "#!/bin/sh\nexit " + ("1" if signing_fails else "0") + "\n",
            "lipo": '#!/bin/sh\nprintf "%s\\n" "$@" >> lipo-arguments\nif [ "$1" = -create ]; then\nwhile [ "$1" != -output ]; do shift; done\nshift; printf fixture > "$1"\nfi\n',
        }
        for name, body in commands.items():
            command = root / "bin" / name
            command.write_text(body)
            command.chmod(0o755)
            # Substitute only the fixture copy; production has no tool override.
            script = script.replace("/usr/bin/" + name, str(command))
        (root / "scripts/build.sh").write_text(script)
        app = root / "build/Creator Micro AI.app"
        stale = app / "Contents/Resources/obsolete.fixture"
        stale.parent.mkdir(parents=True)
        stale.write_text("previous build fixture")
        result = subprocess.run(
            ["/bin/bash", "scripts/build.sh"] + (["--universal"] if universal else []), cwd=root,
            env=os.environ.copy(),
            capture_output=True, text=True,
        )
        return root, app, result

    def test_universal_build_combines_and_verifies_both_architectures(self):
        root, app, result = self.assemble(universal=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (root / "lipo-arguments").read_text().splitlines()
        self.assertEqual(arguments[0], "-create")
        self.assertTrue(arguments[1].endswith("CreatorMicroAI-arm64"))
        self.assertTrue(arguments[2].endswith("CreatorMicroAI-x86_64"))
        self.assertIn("-verify_arch", arguments)
        self.assertTrue(arguments[-4].endswith("Contents/MacOS/CreatorMicroAI"))
        self.assertEqual(arguments[-3:], ["-verify_arch", "arm64", "x86_64"])
        self.assertTrue((app / "Contents/MacOS/CreatorMicroAI").is_file())

    def test_rebuild_excludes_stale_resources_and_preserves_previous_bundle(self):
        root, app, result = self.assemble()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((app / "Contents/Resources/obsolete.fixture").exists())
        self.assertTrue((app / "Contents/Resources/worklouder_device_bridge.js").is_file())
        self.assertTrue((app / "Contents/Resources/AppIcon.icns").is_file())
        for resource in ("device/configure.js", "device/keymap.json", "helper/Resources/worklouder_device_bridge.js",
                         "reference/layout.html", "reference/assets/keycaps.svg", "reference/assets/creator-micro-device.png"):
            self.assertTrue((app / "Contents/Resources" / resource).is_file(), resource)
        self.assertTrue((app / "Contents/MacOS/CreatorMicroAI").is_file())
        recovery = list((root / "build").glob("previous-app.*/Creator Micro AI.app/Contents/Resources/obsolete.fixture"))
        self.assertEqual(len(recovery), 1)
        self.assertEqual(recovery[0].read_text(), "previous build fixture")
        arguments = (root / "compiler-arguments").read_text().splitlines()
        self.assertEqual(arguments[arguments.index("-target") + 1], "arm64-apple-macosx13.2")
        self.assertEqual(pathlib.Path(arguments[arguments.index("-tools-directory") + 1]), (root / "bin").resolve())
        self.assertEqual(pathlib.Path(arguments[arguments.index("-sdk") + 1]), (root / "sdk").resolve())

    def test_wrong_executable_minimum_keeps_existing_bundle(self):
        root, app, result = self.assemble(actual="26.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("minimum macOS version", result.stderr)
        self.assertEqual((app / "Contents/Resources/obsolete.fixture").read_text(), "previous build fixture")
        self.assertFalse(list((root / "build").glob("previous-app.*")))

    def test_signing_failure_keeps_existing_bundle(self):
        root, app, result = self.assemble(signing_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app / "Contents/Resources/obsolete.fixture").read_text(), "previous build fixture")
        self.assertFalse(list((root / "build").glob("previous-app.*")))


if __name__ == "__main__":
    unittest.main()
