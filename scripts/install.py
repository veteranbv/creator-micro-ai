"""Install a built app without launching it or changing system permissions."""
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "build" / "Creator Micro AI.app"
destination = pathlib.Path.home() / "Applications" / source.name
if sys.platform != "darwin" or not source.is_dir():
    sys.exit("Build the app on macOS first with bash scripts/build.sh.")
for process in ("CreatorMicroAI", "WorkLouderFocusHelper"):
    if subprocess.run(["pgrep", "-x", process], stdout=subprocess.DEVNULL).returncode == 0:
        sys.exit("Quit conflicting controller helpers before installing.")
if destination.exists() or destination.is_symlink():
    sys.exit("An installation already exists. Keep a recovery copy and remove it from this destination before installing an update.")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)], check=True)
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, destination)
print(f"Installed: {destination}")
print("Not launched. Open this app and grant Accessibility and Input Monitoring to the installed copy. See docs/setup.md.")
