"""Exercise native preference, Flatpak fallback, missing browsers, and Exec escaping."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import gi

gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix


FUNCTION = Path(__file__).resolve().parents[1] / "functions/make-webapp.fish"
FISH = shutil.which("fish")
assert FISH, "Fish is required"


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="make-webapp-test-") as temporary:
    for backend in ("native", "flatpak", "missing"):
        root = Path(temporary) / backend
        binaries = root / "bin"
        binaries.mkdir(parents=True)
        home = root / "home with spaces $cash"
        home.mkdir()
        capture = root / "arguments.json"
        environment = dict(os.environ, HOME=str(home), PATH=str(binaries), CAPTURE=str(capture))
        for utility in ("mkdir", "mktemp", "mv", "rm", "chmod"):
            (binaries / utility).symlink_to(shutil.which(utility))

        recorder = (
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "path = os.environ['CAPTURE']\n"
            "with open(path + '.tmp', 'w') as output: json.dump(sys.argv[1:], output)\n"
            "os.replace(path + '.tmp', path)\n"
        )
        if backend == "native":
            executable(binaries / "chromium", recorder)
        if backend != "missing":
            executable(
                binaries / "flatpak",
                recorder.replace(
                    "path = os.environ['CAPTURE']",
                    "if sys.argv[1] == 'info': sys.exit(0)\npath = os.environ['CAPTURE']",
                ),
            )
        executable(binaries / "curl", "#!/bin/sh\nexit 22\n")

        name = 'App "Quoted" \\ Demo'
        url = 'https://example.org/a%20b?q=$x&quote="yes"&tick=`x`'
        invocation = [FISH, "--no-config", "-c", "source $argv[1]; make-webapp $argv[2..]", "--", str(FUNCTION)]
        result = subprocess.run(invocation + [name, url], env=environment, capture_output=True, text=True, timeout=10)
        desktop = home / ".local/share/applications/webapp-app-quoted-demo.desktop"
        if backend == "missing":
            assert result.returncode == 1 and "install Chromium" in result.stderr
            assert not desktop.exists()
            continue

        assert result.returncode == 0, result.stderr
        original_path = os.environ["PATH"]
        os.environ["PATH"] = str(binaries)
        app = GioUnix.DesktopAppInfo.new_from_filename(str(desktop))
        assert app.get_name() == name
        assert app.get_icon().to_string() == ("chromium" if backend == "native" else "org.chromium.Chromium")
        context = Gio.AppLaunchContext()
        for key, value in environment.items():
            context.setenv(key, value)
        assert app.launch([], context)
        os.environ["PATH"] = original_path
        deadline = time.monotonic() + 5
        while not capture.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert capture.exists(), "Launcher did not execute"
        profile = str(home / ".config/chromium-app-quoted-demo")
        expected = ["--user-data-dir=" + profile, "--app=" + url]
        if backend == "flatpak":
            expected = ["run", "--filesystem=" + profile + ":create", "org.chromium.Chromium"] + expected
        assert json.loads(capture.read_text()) == expected

        for invalid in ([], ["Only name"], ["App", "ftp://example.org"], ["App", "https://example.org/\nName=injected"]):
            rejected = subprocess.run(invocation + invalid, env=environment, capture_output=True, text=True, timeout=10)
            assert rejected.returncode == 1, invalid

print("PASS: native preference, Flatpak fallback, missing browser, exact name/Exec arguments, icon fallback, invalid input")
